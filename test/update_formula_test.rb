# typed: strict
# frozen_string_literal: true

require_relative "test_helper"

# Exercises allowlisting, release verification, and formula mutation.
class UpdateFormulaTest < Minitest::Test
  include AutomationTestHelpers

  def test_request_accepts_only_allowlisted_stable_release
    source_run = "https://github.com/jimeh/macos-battery-exporter/actions/runs/123"
    built = request(source_run: source_run)

    assert_equal "jimeh/macos-battery-exporter", built.formula.repository
    assert_equal "Formula/macos-battery-exporter.rb", built.formula.path
    assert_equal source_run, built.source_run
  end

  def test_request_rejects_hostile_or_mismatched_inputs
    invalid = [
      { formula: "airplan" },
      { formula: "../macos-battery-exporter" },
      { version: "0.0.7-rc.1", tag: "v0.0.7-rc.1" },
      { tag: "v9.9.9" },
      { commit: "A" * 40 },
      { commit: "a" * 39 },
      { source_run: "https://example.test/run/1" },
    ]

    invalid.each do |overrides|
      assert_raises(HomebrewTap::Automation::Error) do
        request(**overrides)
      end
    end
  end

  def test_updater_changes_only_source_fields_and_removes_bottle
    github = FakeGitHub.new
    before = fixture("formulae/macos-battery-exporter-0.0.6.txt")
    after = fixture("formulae/macos-battery-exporter-0.0.7.txt")
    with_formula("macos-battery-exporter.rb", before) do |root, path|
      result = HomebrewTap::Automation::Updater.new(
        repo_root: root,
        github:    github,
      ).call(request)

      assert_equal :updated, result.status
      assert_equal SOURCE_SHA256, result.source_sha256
      assert_equal after, File.read(path)
      assert_equal 2, github.verify_calls
      assert_equal 1, github.archive_calls
    end
  end

  def test_updater_replay_is_noop
    github = FakeGitHub.new
    fixture_name = "formulae/macos-battery-exporter-0.0.7.txt"
    with_formula("macos-battery-exporter.rb", fixture(fixture_name)) do |root, path|
      before = File.read(path)
      result = HomebrewTap::Automation::Updater.new(
        repo_root: root,
        github:    github,
      ).call(request)

      assert_equal :noop, result.status
      assert_equal before, File.read(path)
      assert_equal 0, github.verify_calls
      assert_equal 0, github.archive_calls
    end
  end

  def test_updater_rejects_downgrade_before_writing
    fixture_name = "formulae/macos-battery-exporter-0.0.7.txt"
    with_formula("macos-battery-exporter.rb", fixture(fixture_name)) do |root, path|
      before = File.read(path)
      assert_raises(HomebrewTap::Automation::Error) do
        HomebrewTap::Automation::Updater.new(
          repo_root: root,
          github:    FakeGitHub.new,
        ).call(request(version: "0.0.6", tag: "v0.0.6"))
      end
      assert_equal before, File.read(path)
    end
  end

  def test_updater_stops_on_failed_release_verification
    github = FakeGitHub.new
    github.release_error = HomebrewTap::Automation::Error.new("draft release")
    fixture_name = "formulae/macos-battery-exporter-0.0.6.txt"
    with_formula("macos-battery-exporter.rb", fixture(fixture_name)) do |root, path|
      before = File.read(path)
      assert_raises(HomebrewTap::Automation::Error) do
        HomebrewTap::Automation::Updater.new(
          repo_root: root,
          github:    github,
        ).call(request)
      end
      assert_equal before, File.read(path)
    end
  end

  def test_updater_rechecks_release_after_archive_download
    github = FakeGitHub.new
    github.release_error = HomebrewTap::Automation::Error.new("tag moved")
    github.release_error_on_call = 2
    fixture_name = "formulae/macos-battery-exporter-0.0.6.txt"
    with_formula("macos-battery-exporter.rb", fixture(fixture_name)) do |root, path|
      before = File.read(path)
      assert_raises(HomebrewTap::Automation::Error) do
        HomebrewTap::Automation::Updater.new(
          repo_root: root,
          github:    github,
        ).call(request)
      end

      assert_equal 2, github.verify_calls
      assert_equal 1, github.archive_calls
      assert_equal before, File.read(path)
    end
  end

  def test_github_client_requires_published_stable_release
    valid_release = {
      "tag_name"     => "v0.0.7",
      "draft"        => false,
      "prerelease"   => false,
      "published_at" => "2026-07-14T00:00:00Z",
    }

    [
      valid_release.merge("draft" => true),
      valid_release.merge("prerelease" => true),
      valid_release.merge("published_at" => nil),
      valid_release.merge("tag_name" => "v9.9.9"),
    ].each do |release|
      assert_raises(HomebrewTap::Automation::Error) do
        stub_github_client(release: release).verify_release!(request)
      end
    end
  end

  def test_github_client_requires_resolved_tag_commit
    assert_raises(HomebrewTap::Automation::Error) do
      stub_github_client(commit: "f" * 40).verify_release!(request)
    end
  end

  def test_editor_rejects_wrong_repository_and_ambiguous_source_sha
    before = fixture("formulae/macos-battery-exporter-0.0.6.txt")
    wrong_repo = before.sub(
      "jimeh/macos-battery-exporter/archive",
      "attacker/macos-battery-exporter/archive",
    )
    assert_raises(HomebrewTap::Automation::Error) do
      HomebrewTap::Automation::FormulaEditor.transform(
        wrong_repo,
        request,
        SOURCE_SHA256,
      )
    end

    ambiguous = before.sub(
      "  license \"MIT\"",
      %Q(  sha256 "#{"f" * 64}"\n  license "MIT"),
    )
    assert_raises(HomebrewTap::Automation::Error) do
      HomebrewTap::Automation::FormulaEditor.transform(
        ambiguous,
        request,
        SOURCE_SHA256,
      )
    end
  end

  def test_editor_rejects_repository_name_containing_allowlisted_name
    disguised_repo = fixture("formulae/macos-battery-exporter-0.0.6.txt").sub(
      "url \"https://github.com/jimeh/macos-battery-exporter",
      "url \"https://github.com/eviljimeh/macos-battery-exporter",
    )

    assert_raises(HomebrewTap::Automation::Error) do
      HomebrewTap::Automation::FormulaEditor.transform(
        disguised_repo,
        request,
        SOURCE_SHA256,
      )
    end
  end

  def test_checked_in_formulae_match_updater_contract
    HomebrewTap::Automation::FORMULAE.each_value do |formula|
      built = request(
        formula: formula.name,
        version: "1.0.0",
        tag:     "v1.0.0",
      )
      path = File.expand_path("../#{built.formula.path}", __dir__)
      editor = HomebrewTap::Automation::FormulaEditor.new(path)

      assert_match HomebrewTap::Automation::VERSION_PATTERN,
                   editor.current_version(built)
    end
  end

  private

  def with_formula(name, content)
    Dir.mktmpdir do |root|
      formula_dir = File.join(root, "Formula")
      FileUtils.mkdir_p(formula_dir)
      path = File.join(formula_dir, name)
      File.write(path, content)
      yield root, path
    end
  end

  def stub_github_client(release: nil, commit: COMMIT)
    release ||= {
      "tag_name"     => "v0.0.7",
      "draft"        => false,
      "prerelease"   => false,
      "published_at" => "2026-07-14T00:00:00Z",
    }
    client = HomebrewTap::Automation::GitHubClient.new
    client.define_singleton_method(:gh_json) do |endpoint|
      if endpoint.include?("/releases/")
        release
      else
        { "sha" => commit }
      end
    end
    client
  end
end
