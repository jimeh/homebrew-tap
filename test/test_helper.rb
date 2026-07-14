# typed: strict
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/homebrew_tap/automation"

# Shared fixtures and fakes for the tap automation tests.
module AutomationTestHelpers
  COMMIT = "a" * 40
  SOURCE_SHA256 = "b" * 64

  # Records updater calls without accessing GitHub or downloading archives.
  class FakeGitHub
    attr_accessor :release_error, :release_error_on_call, :sha256
    attr_reader :archive_calls, :verify_calls

    def initialize(sha256: SOURCE_SHA256)
      @sha256 = sha256
      @archive_calls = 0
      @verify_calls = 0
    end

    def verify_release!(_request)
      @verify_calls += 1
      should_raise = release_error &&
                     (!release_error_on_call || @verify_calls >= release_error_on_call)
      raise release_error if should_raise
    end

    def archive_sha256(_request)
      @archive_calls += 1
      sha256
    end
  end

  def fixture(path)
    File.read(File.join(__dir__, "fixtures", path))
  end

  def request(
    formula: "airplan",
    version: "1.1.0",
    tag: "v1.1.0",
    commit: COMMIT,
    source_run: nil
  )
    HomebrewTap::Automation::Request.build(
      formula:    formula,
      version:    version,
      tag:        tag,
      commit:     commit,
      source_run: source_run,
    )
  end
end
