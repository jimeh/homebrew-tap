# typed: strict
# frozen_string_literal: true

require "yaml"
require_relative "test_helper"

# Locks the privileged workflow to the reviewed trust and artifact gates.
class PublishWorkflowTest < Minitest::Test
  WORKFLOW_PATH = File.expand_path(
    "../.github/workflows/publish.yml",
    __dir__,
  )

  def test_automatic_path_is_only_completed_test_workflow_runs
    workflow = YAML.safe_load_file(WORKFLOW_PATH)
    triggers = workflow.fetch(true)
    workflow_run = triggers.fetch("workflow_run")

    assert_equal ["brew test-bot"], workflow_run.fetch("workflows")
    assert_equal ["completed"], workflow_run.fetch("types")
    assert triggers.key?("workflow_dispatch"), "manual fallback is missing"

    validation = workflow.fetch("jobs").fetch("validate-automatic")
    condition = validation.fetch("if")
    assert_includes condition, "event == 'pull_request'"
    assert_includes condition, "conclusion == 'success'"
    assert_equal "read", validation.dig("permissions", "contents")
    refute_includes validation.fetch("permissions").values, "write"
  end

  def test_privileged_job_uses_trusted_code_and_validates_before_upload
    workflow = YAML.safe_load_file(WORKFLOW_PATH)
    job = workflow.fetch("jobs").fetch("publish-automatic")
    steps = job.fetch("steps")
    names = steps.filter_map { |step| step["name"] }

    checkout = steps.find { |step| step["name"] == "Check out trusted publisher" }
    assert_equal "${{ github.event.repository.default_branch }}",
                 checkout.dig("with", "ref")
    assert_equal false, checkout.dig("with", "persist-credentials")

    revalidate = names.index("Revalidate publication evidence")
    pull = names.index("Pull bottles without publishing")
    compare = names.index("Compare exact-run and selected bottles")
    final_validate = names.index("Revalidate immediately before publication")
    upload = names.index("Publish validated bottles")
    assert_operator revalidate, :<, pull
    assert_operator pull, :<, compare
    assert_operator compare, :<, final_validate
    assert_operator final_validate, :<, upload

    pull_step = steps.fetch(pull)
    assert_includes pull_step.fetch("run"), "--no-upload"
    assert_includes pull_step.fetch("run"), "--retain-bottle-dir"
    assert_includes pull_step.fetch("run"), "--head-sha"

    download = steps.find do |step|
      step["name"] == "Download exact-run bottle artifact"
    end
    assert_equal "${{ steps.evidence.outputs.artifact_id }}",
                 download.dig("with", "artifact-ids")
    assert_equal true, download.dig("with", "merge-multiple")
    assert_equal "${{ github.event.workflow_run.id }}",
                 download.dig("with", "run-id")
    assert_match(/compare-bottle-artifacts/, steps.fetch(compare).fetch("run"))
    assert_match(/brew pr-upload/, steps.fetch(upload).fetch("run"))
  end

  def test_manual_fallback_retains_exact_sha_guard
    workflow = YAML.safe_load_file(WORKFLOW_PATH)
    manual = workflow.fetch("jobs").fetch("manual-pr-pull")
    assert_includes manual.fetch("if"), "workflow_dispatch"

    pull = manual.fetch("steps").find { |step| step["name"] == "Pull bottles" }
    assert_includes pull.fetch("run"), "^[0-9a-f]{40}$"
    assert_includes pull.fetch("run"), '--head-sha="$HEAD_SHA"'
    assert_includes pull.fetch("run"), '"$PULL_REQUEST"'
  end

  def test_all_publication_paths_share_serial_concurrency
    workflow = YAML.safe_load_file(WORKFLOW_PATH)
    assert_equal "brew-pr-pull", workflow.dig("concurrency", "group")
    assert_equal false, workflow.dig("concurrency", "cancel-in-progress")
  end
end
