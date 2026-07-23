# typed: strict
# frozen_string_literal: true

require "base64"
require_relative "test_helper"

# Exercises live evidence normalization and complete REST pagination.
class CollectPublishEvidenceTest < Minitest::Test
  include AutomationTestHelpers

  HEAD_SHA = "c" * 40
  BASE_SHA = "d" * 40
  RUN_ID = 1234

  class FakeArchive
    def archive_sha256(_request)
      AutomationTestHelpers::SOURCE_SHA256
    end
  end

  class FakeRest
    attr_reader :requests

    def initialize(
      extra_files: [],
      extra_jobs: [],
      extra_artifacts: [],
      moved_commit: false,
      changed_pr: nil
    )
      @extra_files = extra_files
      @extra_jobs = extra_jobs
      @extra_artifacts = extra_artifacts
      @moved_commit = moved_commit
      @changed_pr = changed_pr
      @commit_requests = 0
      @pull_request_requests = 0
      @requests = []
    end

    def get(endpoint, query: {})
      @requests << [endpoint, query]
      page = Integer(query.fetch("page", 1))
      case endpoint
      when "repos/jimeh/homebrew-tap/actions/runs/#{RUN_ID}"
        workflow_run
      when "repos/jimeh/homebrew-tap/pulls/42"
        @pull_request_requests += 1
        result = pull_request
        if @pull_request_requests > 1
          case @changed_pr
          when :head
            result["head"]["sha"] = "e" * 40
          when :state
            result["state"] = "closed"
          end
        end
        result
      when "repos/jimeh/macos-battery-exporter/releases/tags/v0.0.7"
        release
      when "repos/jimeh/macos-battery-exporter/commits/v0.0.7"
        @commit_requests += 1
        sha = if @moved_commit && @commit_requests > 1
          "f" * 40
        else
          AutomationTestHelpers::COMMIT
        end
        { "sha" => sha }
      when "repos/jimeh/homebrew-tap/pulls/42/files"
        page([{ "filename" => "Formula/macos-battery-exporter.rb" }] +
             @extra_files, page)
      when "repos/jimeh/homebrew-tap/actions/runs/#{RUN_ID}/jobs"
        paginated_hash("jobs", required_jobs + @extra_jobs, page)
      when "repos/jimeh/homebrew-tap/actions/runs/#{RUN_ID}/artifacts"
        paginated_hash("artifacts", @extra_artifacts + [artifact], page)
      when "repos/jimeh/homebrew-tap/contents/Formula/macos-battery-exporter.rb"
        formula_content(query.fetch("ref"))
      else
        raise "unexpected request: #{endpoint} #{query.inspect}"
      end
    end

    private

    def workflow_run
      {
        "id"            => RUN_ID,
        "status"        => "completed",
        "conclusion"    => "success",
        "path"          => ".github/workflows/tests.yml",
        "event"         => "pull_request",
        "repository"    => { "full_name" => "jimeh/homebrew-tap" },
        "head_branch"   => "automation/macos-battery-exporter-0.0.7",
        "head_sha"      => HEAD_SHA,
        "pull_requests" => [{ "number" => 42 }],
      }
    end

    def pull_request
      files = 1 + @extra_files.length
      {
        "number"        => 42,
        "state"         => "open",
        "user"          => { "login" => "jimehbot[bot]" },
        "changed_files" => files,
        "labels"        => [{ "name" => "automated-formula-update" }],
        "head"          => {
          "ref"  => "automation/macos-battery-exporter-0.0.7",
          "sha"  => HEAD_SHA,
          "repo" => { "full_name" => "jimeh/homebrew-tap" },
        },
        "base"          => {
          "ref"  => "main",
          "sha"  => BASE_SHA,
          "repo" => { "full_name" => "jimeh/homebrew-tap" },
        },
      }
    end

    def release
      {
        "tag_name"     => "v0.0.7",
        "draft"        => false,
        "prerelease"   => false,
        "published_at" => "2026-07-14T00:00:00Z",
      }
    end

    def required_jobs
      HomebrewTap::Automation::PublishValidator::REQUIRED_CHECKS.map do |name|
        { "name" => name, "conclusion" => "success" }
      end
    end

    def artifact
      {
        "id"           => 9876,
        "name"         => "bottles_macos-15-arm64",
        "expired"      => false,
        "workflow_run" => { "id" => RUN_ID, "head_sha" => HEAD_SHA },
      }
    end

    def formula_content(ref)
      fixture_name = case ref
      when BASE_SHA then "macos-battery-exporter-0.0.6.txt"
      when HEAD_SHA then "macos-battery-exporter-0.0.7.txt"
      else raise "unexpected content ref: #{ref}"
      end
      content = File.read(
        File.join(__dir__, "fixtures", "formulae", fixture_name),
      )
      { "encoding" => "base64", "content" => Base64.encode64(content) }
    end

    def page(items, number)
      start = (number - 1) * 100
      items.slice(start, 100) || []
    end

    def paginated_hash(key, items, number)
      { "total_count" => items.length, key => page(items, number) }
    end
  end

  def test_collects_and_validates_independent_live_evidence
    evidence = collector.call(RUN_ID)

    assert_equal "0.0.7", evidence.dig("request", "version")
    assert_equal COMMIT, evidence.dig("request", "commit")
    assert_equal 9876, evidence.dig("workflow", "artifact", "id")
    assert HomebrewTap::Automation::PublishValidator.new(
      evidence,
      expected_bot: "jimehbot[bot]",
    ).validate!
  end

  def test_paginates_jobs_and_artifacts_without_omitting_later_pages
    extra_jobs = 99.times.map do |index|
      { "name" => "extra job #{index}", "conclusion" => "success" }
    end
    extra_artifacts = 100.times.map do |index|
      {
        "id"           => index + 1,
        "name"         => "unrelated-#{index}",
        "expired"      => false,
        "workflow_run" => { "id" => RUN_ID, "head_sha" => HEAD_SHA },
      }
    end
    github = FakeRest.new(
      extra_jobs: extra_jobs,
      extra_artifacts: extra_artifacts,
    )
    evidence = collector(github: github).call(RUN_ID)

    assert_equal 101, evidence.dig("workflow", "checks").length
    assert_includes github.requests,
                    ["repos/jimeh/homebrew-tap/actions/runs/#{RUN_ID}/jobs",
                     { "per_page" => 100, "page" => 2 }]
    assert_includes github.requests,
                    ["repos/jimeh/homebrew-tap/actions/runs/#{RUN_ID}/artifacts",
                     { "per_page" => 100, "page" => 2 }]
  end

  def test_rejects_ambiguous_bottle_artifacts
    duplicate = {
      "id"           => 8765,
      "name"         => "bottles_macos-15-arm64",
      "expired"      => false,
      "workflow_run" => { "id" => RUN_ID, "head_sha" => HEAD_SHA },
    }
    error = assert_raises(HomebrewTap::Automation::Error) do
      collector(
        github: FakeRest.new(extra_artifacts: [duplicate]),
      ).call(RUN_ID)
    end
    assert_match(/expected exactly one/, error.message)
  end

  def test_extra_changed_files_are_fully_collected_and_rejected
    extra_files = 100.times.map do |index|
      { "filename" => "unexpected/file-#{index}" }
    end
    github = FakeRest.new(extra_files: extra_files)
    evidence = collector(github: github).call(RUN_ID)

    assert_equal 101, evidence.dig("pr", "changed_files").length
    assert_includes github.requests,
                    ["repos/jimeh/homebrew-tap/pulls/42/files",
                     { "per_page" => 100, "page" => 2 }]
    error = assert_raises(HomebrewTap::Automation::Error) do
      HomebrewTap::Automation::PublishValidator.new(
        evidence,
        expected_bot: "jimehbot[bot]",
      ).validate!
    end
    assert_match(/unexpected files/, error.message)
  end

  def test_rejects_ambiguous_run_pull_request_association
    github = FakeRest.new
    github.define_singleton_method(:get) do |endpoint, query: {}|
      result = super(endpoint, query: query)
      if endpoint == "repos/jimeh/homebrew-tap/actions/runs/#{RUN_ID}"
        result.merge("pull_requests" => [{ "number" => 42 }, { "number" => 43 }])
      else
        result
      end
    end

    error = assert_raises(HomebrewTap::Automation::Error) do
      collector(github: github).call(RUN_ID)
    end
    assert_match(/exactly one pull request/, error.message)
  end

  def test_rejects_upstream_tag_moving_during_collection
    error = assert_raises(HomebrewTap::Automation::Error) do
      collector(github: FakeRest.new(moved_commit: true)).call(RUN_ID)
    end
    assert_match(/changed during evidence collection/, error.message)
  end

  def test_rejects_pull_request_changing_during_collection
    %i[head state].each do |change|
      error = assert_raises(HomebrewTap::Automation::Error) do
        collector(github: FakeRest.new(changed_pr: change)).call(RUN_ID)
      end
      assert_match(/changed during evidence collection/, error.message)
    end
  end

  def test_rejects_unshaped_or_unallowlisted_automation_branch
    github = FakeRest.new
    github.define_singleton_method(:get) do |endpoint, query: {}|
      result = super(endpoint, query: query)
      if endpoint == "repos/jimeh/homebrew-tap/pulls/42"
        result["head"]["ref"] = "automation/airplan-1.2.3"
      end
      result
    end

    error = assert_raises(HomebrewTap::Automation::Error) do
      collector(github: github).call(RUN_ID)
    end
    assert_match(/allowlisted formula/, error.message)
  end

  private

  def collector(github: FakeRest.new)
    HomebrewTap::Automation::PublishEvidenceCollector.new(
      repository: "jimeh/homebrew-tap",
      github: github,
      archive: FakeArchive.new,
    )
  end
end
