# frozen_string_literal: true

require_relative "test_helper"

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
      "author" => "someone-else",
      "head_repository" => "fork/homebrew-tap",
      "head_ref" => "feature/not-automation",
      "labels" => [],
      "state" => "closed",
      "changed_files" => ["Formula/airplan.rb", ".github/workflows/publish.yml"],
    }

    cases.each do |key, value|
      evidence = deep_copy(valid_evidence)
      evidence["pr"][key] = value
      assert_rejected(evidence, key)
    end
  end

  def test_rejects_stale_sha_and_failed_workflow
    stale = deep_copy(valid_evidence)
    stale["workflow"]["head_sha"] = "d" * 40
    assert_rejected(stale, "stale SHA")

    failed = deep_copy(valid_evidence)
    failed["workflow"]["checks"][0]["conclusion"] = "failure"
    assert_rejected(failed, "failed check")

    missing = deep_copy(valid_evidence)
    missing["workflow"]["checks"] = []
    assert_rejected(missing, "missing check")
  end

  def test_rejects_mismatched_upstream_state
    %w[repository tag commit].each do |key|
      evidence = deep_copy(valid_evidence)
      evidence["upstream"][key] = "wrong"
      assert_rejected(evidence, "upstream #{key}")
    end

    evidence = deep_copy(valid_evidence)
    evidence["upstream"]["draft"] = true
    assert_rejected(evidence, "draft upstream release")

    evidence = deep_copy(valid_evidence)
    evidence["upstream"]["source_sha256"] = "f" * 64
    assert_rejected(evidence, "upstream source checksum")
  end

  def test_rejects_unpermitted_formula_diff
    evidence = deep_copy(valid_evidence)
    evidence["diff"]["after"] += "# injected\n"
    assert_rejected(evidence, "extra formula change")

    evidence = deep_copy(valid_evidence)
    evidence["diff"]["before"] = evidence["diff"]["before"].sub(
      /^  bottle do.*?^  end\n\n/m,
      "",
    )
    assert_rejected(evidence, "missing old bottle")
  end

  private

  def valid_evidence
    {
      "request" => {
        "formula" => "airplan",
        "version" => "1.1.0",
        "tag" => "v1.1.0",
        "commit" => COMMIT,
      },
      "source_sha256" => SOURCE_SHA256,
      "pr" => {
        "state" => "open",
        "author" => BOT,
        "head_repository" => "jimeh/homebrew-tap",
        "head_ref" => "automation/airplan-1.1.0",
        "head_sha" => HEAD_SHA,
        "labels" => ["automated-formula-update"],
        "changed_files" => ["Formula/airplan.rb"],
      },
      "workflow" => {
        "head_sha" => HEAD_SHA,
        "conclusion" => "success",
        "checks" => HomebrewTap::Automation::PublishValidator::REQUIRED_CHECKS.map do |name|
          { "name" => name, "conclusion" => "success" }
        end,
      },
      "upstream" => {
        "repository" => "jimeh/airplan",
        "tag" => "v1.1.0",
        "commit" => COMMIT,
        "source_sha256" => SOURCE_SHA256,
        "draft" => false,
        "prerelease" => false,
        "published_at" => "2026-07-14T00:00:00Z",
      },
      "diff" => {
        "before" => fixture("formulae/airplan-1.0.0.rb"),
        "after" => fixture("formulae/airplan-1.1.0.rb"),
      },
    }
  end

  def deep_copy(value)
    JSON.parse(JSON.generate(value))
  end

  def assert_rejected(evidence, message)
    assert_raises(HomebrewTap::Automation::Error, message) do
      HomebrewTap::Automation::PublishValidator.new(
        evidence,
        expected_bot: BOT,
      ).validate!
    end
  end
end
