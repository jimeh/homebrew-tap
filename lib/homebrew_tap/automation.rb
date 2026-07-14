# typed: strict
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rubygems/version"

module HomebrewTap
  # Policy and mechanics shared by the tap's release automation scripts.
  module Automation
    class Error < StandardError; end

    Formula = Struct.new(:name, :repository, :path, keyword_init: true) do
      def archive_url(version)
        "https://github.com/#{repository}/archive/refs/tags/v#{version}.tar.gz"
      end
    end

    FORMULAE = {
      "airplan"                => Formula.new(
        name:       "airplan",
        repository: "jimeh/airplan",
        path:       "Formula/airplan.rb",
      ),
      "macos-battery-exporter" => Formula.new(
        name:       "macos-battery-exporter",
        repository: "jimeh/macos-battery-exporter",
        path:       "Formula/macos-battery-exporter.rb",
      ),
    }.freeze

    VERSION_PATTERN = /\A\d+\.\d+\.\d+\z/
    COMMIT_PATTERN = /\A[0-9a-f]{40}\z/
    SHA256_PATTERN = /\A[0-9a-f]{64}\z/

    Request = Struct.new(
      :formula,
      :version,
      :tag,
      :commit,
      :source_run,
      keyword_init: true,
    ) do
      def self.build(formula:, version:, tag:, commit:, source_run: nil)
        spec = FORMULAE[formula]
        raise Error, "unknown formula: #{formula.inspect}" unless spec
        raise Error, "version must be stable MAJOR.MINOR.PATCH" unless VERSION_PATTERN.match?(version)
        raise Error, "tag must be v#{version}" if tag != "v#{version}"
        raise Error, "commit must be a lowercase 40-character SHA" unless COMMIT_PATTERN.match?(commit)

        source_run = nil if source_run.to_s.empty?
        if source_run
          repository = Regexp.escape(spec.repository)
          run_pattern = %r{\Ahttps://github\.com/#{repository}/actions/runs/\d+\z}
          unless run_pattern.match?(source_run)
            raise Error,
                  "source_run must identify an allowlisted GitHub Actions run"
          end
        end

        new(
          formula:    spec,
          version:    version,
          tag:        tag,
          commit:     commit,
          source_run: source_run,
        )
      end
    end

    Result = Struct.new(
      :status,
      :request,
      :source_sha256,
      keyword_init: true,
    ) do
      def to_h
        {
          status:        status.to_s,
          formula:       request.formula.name,
          repository:    request.formula.repository,
          path:          request.formula.path,
          version:       request.version,
          tag:           request.tag,
          commit:        request.commit,
          archive_url:   request.formula.archive_url(request.version),
          source_sha256: source_sha256,
          source_run:    request.source_run,
        }.compact
      end
    end

    # Minimal GitHub client. It resolves all security-sensitive release data
    # independently instead of trusting repository_dispatch payload fields.
    class GitHubClient
      def initialize(token: ENV.fetch("GH_TOKEN", nil))
        @token = token
      end

      def verify_release!(request)
        release = gh_json(
          "repos/#{request.formula.repository}/releases/tags/#{request.tag}",
        )
        if release["tag_name"] != request.tag ||
           release["draft"] != false ||
           release["prerelease"] != false ||
           release["published_at"].to_s.empty?
          raise Error, "release must be published, non-draft, and stable"
        end

        resolved = gh_json(
          "repos/#{request.formula.repository}/commits/#{request.tag}",
        ).fetch("sha")
        return if resolved == request.commit

        raise Error, "tag resolves to #{resolved}, expected #{request.commit}"
      end

      def archive_sha256(request)
        url = request.formula.archive_url(request.version)
        stdout, stderr, status = Open3.capture3(
          "curl", "--fail", "--silent", "--show-error", "--location",
          "--proto", "=https", "--proto-redir", "=https", "--retry", "3",
          url
        )
        raise Error, "archive download failed: #{stderr.strip}" unless status.success?

        Digest::SHA256.hexdigest(stdout)
      end

      private

      def gh_json(endpoint)
        env = @token.to_s.empty? ? {} : { "GH_TOKEN" => @token }
        stdout, stderr, status = Open3.capture3(env, "gh", "api", endpoint)
        raise Error, "GitHub API failed: #{stderr.strip}" unless status.success?

        JSON.parse(stdout)
      rescue JSON::ParserError => e
        raise Error, "GitHub API returned invalid JSON: #{e.message}"
      end
    end

    # Performs the only permitted formula transformation for a version update.
    class FormulaEditor
      URL_PATTERN = %r{
        https://github\.com/[^/]+/[^/]+/archive/refs/tags/
        v(\d+\.\d+\.\d+)\.tar\.gz
      }x
      SOURCE_SHA_PATTERN = /^  sha256 "([0-9a-f]{64})"$/
      BOTTLE_START_PATTERN = /^  bottle do\s*$/
      BLOCK_END_PATTERN = /^  end\s*$/

      attr_reader :path

      def initialize(path)
        @path = path
      end

      def update!(request, source_sha256)
        raise Error, "invalid source SHA-256" unless SHA256_PATTERN.match?(source_sha256)
        raise Error, "formula does not exist: #{path}" unless File.file?(path)

        before = File.read(path)
        after, status = self.class.transform(before, request, source_sha256)
        File.write(path, after) if status == :updated
        status
      end

      def current_version(request)
        raise Error, "formula does not exist: #{path}" unless File.file?(path)

        match = File.read(path).match(URL_PATTERN)
        raise Error, "formula source URL is missing or unsupported" unless match
        unless self.class.supported_source_url?(match[0], match[1], request)
          raise Error, "formula source repository does not match allowlist"
        end

        match[1]
      end

      def self.transform(content, request, source_sha256)
        match = content.match(URL_PATTERN)
        raise Error, "formula source URL is missing or unsupported" unless match

        current_version = match[1]
        comparison = Gem::Version.new(request.version) <=>
                     Gem::Version.new(current_version)
        return [content, :noop] if comparison.zero?
        raise Error, "refusing downgrade from #{current_version} to #{request.version}" if comparison.negative?

        unless supported_source_url?(match[0], current_version, request)
          raise Error, "formula source repository does not match allowlist"
        end

        without_bottle = remove_bottle_block(content)
        url_matches = without_bottle.scan(URL_PATTERN)
        raise Error, "formula must contain exactly one supported source URL" if url_matches.length != 1

        sha_matches = without_bottle.scan(SOURCE_SHA_PATTERN)
        raise Error, "formula must contain exactly one source SHA-256" if sha_matches.length != 1

        updated = without_bottle.sub(
          URL_PATTERN,
          request.formula.archive_url(request.version),
        ).sub(SOURCE_SHA_PATTERN, %Q(  sha256 "#{source_sha256}"))
        [updated, :updated]
      end

      def self.supported_source_url?(url, version, request)
        url == request.formula.archive_url(version)
      end

      def self.remove_bottle_block(content)
        lines = content.lines
        start = lines.index { |line| BOTTLE_START_PATTERN.match?(line) }
        return content unless start

        finish = ((start + 1)...lines.length).find do |index|
          BLOCK_END_PATTERN.match?(lines[index])
        end
        raise Error, "unterminated bottle block" unless finish

        lines.slice!(start..finish)
        lines.delete_at(start) while lines[start] == "\n" && lines[start - 1] == "\n"
        lines.join
      end
    end

    # Coordinates release verification, checksum calculation, and mutation.
    class Updater
      def initialize(repo_root:, github: GitHubClient.new)
        @repo_root = repo_root
        @github = github
      end

      def call(request)
        editor = FormulaEditor.new(File.join(@repo_root, request.formula.path))
        current_version = editor.current_version(request)
        comparison = Gem::Version.new(request.version) <=>
                     Gem::Version.new(current_version)
        return Result.new(status: :noop, request: request, source_sha256: nil) if comparison.zero?
        raise Error, "refusing downgrade from #{current_version} to #{request.version}" if comparison.negative?

        @github.verify_release!(request)
        source_sha256 = @github.archive_sha256(request)
        @github.verify_release!(request)
        status = editor.update!(request, source_sha256)
        Result.new(status: status, request: request, source_sha256: source_sha256)
      end
    end

    # Validates normalized evidence before a future privileged publish. Phase 1
    # ships this policy and its tests but does not wire it to workflow_run.
    class PublishValidator
      REQUIRED_LABEL = "automated-formula-update"
      TAP_REPOSITORY = "jimeh/homebrew-tap"
      TEST_WORKFLOW = ".github/workflows/tests.yml"
      REQUIRED_CHECKS = [
        "automation tests",
        "brew test-bot (macos-14-arm64)",
        "brew test-bot (macos-14-x86_64)",
        "brew test-bot (ubuntu-latest)",
        "brew test-bot (ubuntu-24.04-arm)",
      ].freeze

      def initialize(evidence, expected_bot:)
        @evidence = evidence
        @expected_bot = expected_bot
      end

      def validate!
        request = Request.build(**symbolized_request)
        pr = fetch_hash("pr")
        workflow = fetch_hash("workflow")
        upstream = fetch_hash("upstream")
        diff = fetch_hash("diff")

        require_value(pr["state"] == "open", "pull request is not open")
        require_value(
          pr["author"] == @expected_bot,
          "unexpected pull request author",
        )
        require_value(
          pr["head_repository"] == TAP_REPOSITORY,
          "pull request is from a fork",
        )
        require_value(
          pr["number"].is_a?(Integer) && pr["number"].positive?,
          "invalid pull request number",
        )
        require_value(pr["base_ref"] == "main", "unexpected pull request base")
        expected_branch = "automation/#{request.formula.name}-#{request.version}"
        require_value(pr["head_ref"] == expected_branch, "unexpected automation branch")
        require_value(
          Array(pr["labels"]).include?(REQUIRED_LABEL),
          "trusted label is missing",
        )
        require_value(
          pr["head_sha"] == workflow["head_sha"],
          "tested SHA does not match pull request head",
        )
        require_value(
          workflow["conclusion"] == "success",
          "workflow did not succeed",
        )
        validate_workflow_identity!(workflow, pr)
        validate_checks!(workflow)
        require_value(
          Array(pr["changed_files"]) == [request.formula.path],
          "pull request changes unexpected files",
        )
        validate_upstream!(upstream, request)
        validate_diff!(diff, request)

        true
      end

      private

      def symbolized_request
        fetch_hash("request").transform_keys(&:to_sym)
      end

      def fetch_hash(key)
        value = @evidence[key]
        raise Error, "missing #{key} evidence" unless value.is_a?(Hash)

        value
      end

      def require_value(condition, message)
        raise Error, message unless condition
      end

      def validate_checks!(workflow)
        checks = Array(workflow["checks"])
        by_name = checks.group_by { |check| check["name"] }
        ambiguous = REQUIRED_CHECKS.reject do |name|
          by_name.fetch(name, []).length == 1
        end
        require_value(
          ambiguous.empty?,
          "required checks are missing or ambiguous: #{ambiguous.join(", ")}",
        )
        conclusions = by_name.transform_values { |runs| runs.fetch(0)["conclusion"] }
        failed = REQUIRED_CHECKS.reject do |name|
          conclusions[name] == "success"
        end
        require_value(
          failed.empty?,
          "required checks did not succeed: #{failed.join(", ")}",
        )
      end

      def validate_workflow_identity!(workflow, pull_request)
        valid = workflow["path"] == TEST_WORKFLOW &&
                workflow["event"] == "pull_request" &&
                workflow["repository"] == TAP_REPOSITORY &&
                Array(workflow["pull_requests"]) == [pull_request["number"]]
        require_value(valid, "workflow is not the expected pull request run")
      end

      def validate_upstream!(upstream, request)
        valid = upstream["repository"] == request.formula.repository &&
                upstream["tag"] == request.tag &&
                upstream["commit"] == request.commit &&
                upstream["source_sha256"] == @evidence["source_sha256"] &&
                upstream["draft"] == false &&
                upstream["prerelease"] == false &&
                !upstream["published_at"].to_s.empty?
        require_value(valid, "upstream release evidence does not match request")
      end

      def validate_diff!(diff, request)
        source_sha256 = @evidence["source_sha256"]
        require_value(
          SHA256_PATTERN.match?(source_sha256.to_s),
          "invalid source SHA-256 evidence",
        )
        before = diff["before"]
        after = diff["after"]
        require_value(
          before.is_a?(String) && after.is_a?(String),
          "formula diff content is missing",
        )
        # First bottles stay on the manual bootstrap path. Automatic updates
        # must replace bottle metadata that was already published and reviewed.
        require_value(
          FormulaEditor::BOTTLE_START_PATTERN.match?(before),
          "updated formula did not previously contain a bottle block",
        )
        expected, status = FormulaEditor.transform(before, request, source_sha256)
        require_value(
          status == :updated && expected == after,
          "formula diff is not permitted",
        )
      end
    end
  end
end
