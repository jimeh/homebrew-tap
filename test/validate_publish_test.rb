# typed: strict
# frozen_string_literal: true

require "yaml"
require_relative "test_helper"

# Exercises every trust boundary required before automatic publication.
class ValidatePublishTest < Minitest::Test
  include AutomationTestHelpers

  BOT = "release-bot[bot]"
  HEAD_SHA = "c" * 40

  def test_accepts_complete_trusted_evidence
    assert HomebrewTap::Automation::PublishValidator.new(
      valid_evidence,
      expected_bot: BOT,
    ).validate!
  end

  def test_required_checks_match_test_workflow_jobs
    workflow_path = File.join(
      __dir__,
      "..",
      HomebrewTap::Automation::PublishValidator::TEST_WORKFLOW,
    )
    jobs = YAML.safe_load_file(workflow_path).fetch("jobs")

    expected_jobs = %w[automation-tests test-bot-macos]
    assert_equal expected_jobs, jobs.keys

    expected = expected_jobs.map do |job|
      jobs.fetch(job).fetch("name")
    end
    assert_equal(
      expected,
      HomebrewTap::Automation::PublishValidator::REQUIRED_CHECKS,
    )

    macos_steps = jobs.fetch("test-bot-macos").fetch("steps")
    tap_syntax = macos_steps.find do |step|
      step["run"]&.start_with?("brew test-bot --only-tap-syntax")
    end
    assert_equal "brew test-bot --only-tap-syntax --stable",
                 tap_syntax.fetch("run")

    detect_formulae = macos_steps.find do |step|
      step["name"] == "Detect changed formulae"
    end
    assert_equal "github.event_name == 'pull_request'",
                 detect_formulae.fetch("if")
    assert_equal "brew test-bot --only-formulae-detect",
                 detect_formulae.fetch("run")

    build_formulae = macos_steps.find do |step|
      step["name"] == "Build formulae"
    end
    assert_operator macos_steps.index(tap_syntax), :<,
                    macos_steps.index(build_formulae)
    assert_equal "github.event_name == 'pull_request'",
                 build_formulae.fetch("if")
    assert_equal(
      {
        "ADDED_FORMULAE"   => "${{ steps.formulae.outputs.added_formulae }}",
        "DELETED_FORMULAE" => "${{ steps.formulae.outputs.deleted_formulae }}",
        "TESTING_FORMULAE" => "${{ steps.formulae.outputs.testing_formulae }}",
      },
      build_formulae.fetch("env"),
    )
    formula_run = build_formulae.fetch("run")
    assert_includes formula_run, "brew test-bot --only-formulae"
    assert_includes formula_run, '"--testing-formulae=$TESTING_FORMULAE"'
    assert_includes formula_run, '"--added-formulae=$ADDED_FORMULAE"'
    assert_includes formula_run, '"--deleted-formulae=$DELETED_FORMULAE"'
  end

  def test_rejects_untrusted_pull_request_metadata
    cases = {
      "author"          => ["someone-else", /author/],
      "number"          => [nil, /pull request number/],
      "head_repository" => ["fork/homebrew-tap", /fork/],
      "base_repository" => ["someone/homebrew-tap", /targets/],
      "base_ref"        => ["not-main", /base/],
      "head_ref"        => ["feature/not-automation", /branch/],
      "labels"          => [[], /label/],
      "state"           => ["closed", /not open/],
      "changed_files"   => [
        [
          "Formula/macos-battery-exporter.rb",
          ".github/workflows/publish.yml",
        ],
        /unexpected files/,
      ],
    }

    cases.each do |key, (value, error_pattern)|
      evidence = deep_copy(valid_evidence)
      evidence["pr"][key] = value
      assert_rejected(evidence, error_pattern)
    end
  end

  def test_rejects_stale_sha_and_failed_workflow
    stale = deep_copy(valid_evidence)
    stale["workflow"]["head_sha"] = "d" * 40
    assert_rejected(stale, /tested SHA/)

    failed = deep_copy(valid_evidence)
    failed["workflow"]["checks"][0]["conclusion"] = "failure"
    assert_rejected(failed, /did not succeed/)

    missing = deep_copy(valid_evidence)
    missing["workflow"]["checks"] = []
    assert_rejected(missing, /missing or ambiguous/)

    duplicate = deep_copy(valid_evidence)
    duplicate["workflow"]["checks"] << duplicate["workflow"]["checks"].first
    assert_rejected(duplicate, /missing or ambiguous/)

    failed_workflow = deep_copy(valid_evidence)
    failed_workflow["workflow"]["conclusion"] = "failure"
    assert_rejected(failed_workflow, /workflow did not succeed/)
  end

  def test_rejects_unrelated_or_ambiguous_workflow_run
    {
      "path"          => ".github/workflows/other.yml",
      "event"         => "push",
      "repository"    => "fork/homebrew-tap",
      "pull_requests" => [41, 42],
    }.each do |key, value|
      evidence = deep_copy(valid_evidence)
      evidence["workflow"][key] = value
      assert_rejected(evidence, /expected pull request run/)
    end
  end

  def test_rejects_invalid_artifact_identity
    cases = [
      ["expired", true],
      ["workflow_run_id", 9999],
      ["head_sha", "d" * 40],
      ["name", "other-bottles"],
      ["id", 0],
      ["id", "9876"],
    ]

    cases.each do |key, value|
      evidence = deep_copy(valid_evidence)
      evidence["workflow"]["artifact"][key] = value
      assert_rejected(evidence, /expected pull request run/)
    end
  end

  def test_rejects_mismatched_upstream_state
    %w[repository tag commit].each do |key|
      evidence = deep_copy(valid_evidence)
      evidence["upstream"][key] = "wrong"
      assert_rejected(evidence, /upstream release evidence/)
    end

    evidence = deep_copy(valid_evidence)
    evidence["upstream"]["draft"] = true
    assert_rejected(evidence, /upstream release evidence/)

    evidence = deep_copy(valid_evidence)
    evidence["upstream"]["source_sha256"] = "f" * 64
    assert_rejected(evidence, /upstream release evidence/)
  end

  def test_rejects_unpermitted_formula_diff
    evidence = deep_copy(valid_evidence)
    evidence["diff"]["after"] += "# injected\n"
    assert_rejected(evidence, /formula diff is not permitted/)

    evidence = deep_copy(valid_evidence)
    evidence["diff"]["before"] = evidence["diff"]["before"].sub(
      /^  bottle do.*?^  end\n\n/m,
      "",
    )
    assert_rejected(evidence, /bottle block/)
  end

  def test_rejects_same_version_formula_replay
    evidence = deep_copy(valid_evidence)
    current_sha256 = "a6477d67cd7e4253b548fccd9bbd9214" \
                     "c473c21a45bb6894a8265e5709124a3e"
    evidence["request"]["version"] = "0.0.6"
    evidence["request"]["tag"] = "v0.0.6"
    evidence["source_sha256"] = current_sha256
    evidence["pr"]["head_ref"] = "automation/macos-battery-exporter-0.0.6"
    evidence["workflow"]["head_branch"] = evidence["pr"]["head_ref"]
    evidence["upstream"]["tag"] = "v0.0.6"
    evidence["upstream"]["source_sha256"] = current_sha256
    evidence["diff"]["after"] = evidence["diff"]["before"]

    assert_rejected(evidence, /formula diff is not permitted/)
  end

  private

  def valid_evidence
    {
      "request"       => {
        "formula" => "macos-battery-exporter",
        "version" => "0.0.7",
        "tag"     => "v0.0.7",
        "commit"  => COMMIT,
      },
      "source_sha256" => SOURCE_SHA256,
      "pr"            => {
        "number"          => 42,
        "state"           => "open",
        "author"          => BOT,
        "head_repository" => "jimeh/homebrew-tap",
        "base_repository" => "jimeh/homebrew-tap",
        "base_ref"        => "main",
        "head_ref"        => "automation/macos-battery-exporter-0.0.7",
        "head_sha"        => HEAD_SHA,
        "labels"          => ["automated-formula-update"],
        "changed_files"   => ["Formula/macos-battery-exporter.rb"],
      },
      "workflow"      => {
        "id"            => 1234,
        "status"        => "completed",
        "path"          => ".github/workflows/tests.yml",
        "event"         => "pull_request",
        "repository"    => "jimeh/homebrew-tap",
        "head_branch"   => "automation/macos-battery-exporter-0.0.7",
        "pull_requests" => [42],
        "head_sha"      => HEAD_SHA,
        "conclusion"    => "success",
        "checks"        => HomebrewTap::Automation::PublishValidator::REQUIRED_CHECKS.map do |name|
          { "name" => name, "conclusion" => "success" }
        end,
        "artifact"      => {
          "id"              => 9876,
          "name"            => "bottles_macos-15-arm64",
          "expired"         => false,
          "workflow_run_id" => 1234,
          "head_sha"        => HEAD_SHA,
        },
      },
      "upstream"      => {
        "repository"    => "jimeh/macos-battery-exporter",
        "tag"           => "v0.0.7",
        "commit"        => COMMIT,
        "source_sha256" => SOURCE_SHA256,
        "draft"         => false,
        "prerelease"    => false,
        "published_at"  => "2026-07-14T00:00:00Z",
      },
      "diff"          => {
        "before" => fixture("formulae/macos-battery-exporter-0.0.6.txt"),
        "after"  => fixture("formulae/macos-battery-exporter-0.0.7.txt"),
      },
    }
  end

  def deep_copy(value)
    JSON.parse(JSON.generate(value))
  end

  def assert_rejected(evidence, error_pattern)
    error = assert_raises(HomebrewTap::Automation::Error) do
      HomebrewTap::Automation::PublishValidator.new(
        evidence,
        expected_bot: BOT,
      ).validate!
    end
    assert_match(error_pattern, error.message)
  end
end
