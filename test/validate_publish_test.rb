# typed: strict
# frozen_string_literal: true

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

  def test_rejects_untrusted_pull_request_metadata
    cases = {
      "author"          => ["someone-else", /author/],
      "number"          => [nil, /pull request number/],
      "head_repository" => ["fork/homebrew-tap", /fork/],
      "base_ref"        => ["not-main", /base/],
      "head_ref"        => ["feature/not-automation", /branch/],
      "labels"          => [[], /label/],
      "state"           => ["closed", /not open/],
      "changed_files"   => [
        ["Formula/airplan.rb", ".github/workflows/publish.yml"],
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

  private

  def valid_evidence
    {
      "request"       => {
        "formula" => "airplan",
        "version" => "1.1.0",
        "tag"     => "v1.1.0",
        "commit"  => COMMIT,
      },
      "source_sha256" => SOURCE_SHA256,
      "pr"            => {
        "number"          => 42,
        "state"           => "open",
        "author"          => BOT,
        "head_repository" => "jimeh/homebrew-tap",
        "base_ref"        => "main",
        "head_ref"        => "automation/airplan-1.1.0",
        "head_sha"        => HEAD_SHA,
        "labels"          => ["automated-formula-update"],
        "changed_files"   => ["Formula/airplan.rb"],
      },
      "workflow"      => {
        "path"          => ".github/workflows/tests.yml",
        "event"         => "pull_request",
        "repository"    => "jimeh/homebrew-tap",
        "pull_requests" => [42],
        "head_sha"      => HEAD_SHA,
        "conclusion"    => "success",
        "checks"        => HomebrewTap::Automation::PublishValidator::REQUIRED_CHECKS.map do |name|
          { "name" => name, "conclusion" => "success" }
        end,
      },
      "upstream"      => {
        "repository"    => "jimeh/airplan",
        "tag"           => "v1.1.0",
        "commit"        => COMMIT,
        "source_sha256" => SOURCE_SHA256,
        "draft"         => false,
        "prerelease"    => false,
        "published_at"  => "2026-07-14T00:00:00Z",
      },
      "diff"          => {
        "before" => fixture("formulae/airplan-1.0.0.txt"),
        "after"  => fixture("formulae/airplan-1.1.0.txt"),
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
