# typed: strict
# frozen_string_literal: true

require_relative "test_helper"

# Ensures only the exact bottle files from the triggering run are uploaded.
class CompareBottleArtifactsTest < Minitest::Test
  def test_accepts_identical_complete_file_sets
    with_artifacts do |expected, actual|
      write_bottle_set(expected)
      write_bottle_set(actual)

      manifest = HomebrewTap::Automation::BottleArtifactComparator.compare!(
        expected,
        actual,
      )
      assert_equal 2, manifest.length
    end
  end

  def test_rejects_changed_or_extra_files
    with_artifacts do |expected, actual|
      write_bottle_set(expected)
      write_bottle_set(actual)
      File.write(File.join(actual, "exporter.bottle.tar.gz"), "changed")
      assert_comparison_fails(expected, actual)
    end

    with_artifacts do |expected, actual|
      write_bottle_set(expected)
      write_bottle_set(actual)
      File.write(File.join(actual, "extra.bottle.json"), "{}")
      assert_comparison_fails(expected, actual, /complete bottle file set/)
    end
  end

  def test_rejects_non_bottle_or_incomplete_artifacts
    with_artifacts do |expected, actual|
      write_bottle_set(expected)
      write_bottle_set(actual)
      File.write(File.join(expected, "unexpected.txt"), "nope")
      assert_comparison_fails(expected, actual, /complete bottle file set/)
    end

    with_artifacts do |expected, actual|
      File.write(File.join(expected, "exporter.bottle.json"), "{}")
      File.write(File.join(actual, "exporter.bottle.json"), "{}")
      assert_comparison_fails(expected, actual, /complete bottle file set/)
    end
  end

  private

  def with_artifacts
    Dir.mktmpdir do |root|
      expected = File.join(root, "expected")
      actual = File.join(root, "actual")
      FileUtils.mkdir_p([expected, actual])
      yield expected, actual
    end
  end

  def write_bottle_set(directory)
    File.write(File.join(directory, "exporter.bottle.json"), "{}")
    File.write(File.join(directory, "exporter.bottle.tar.gz"), "archive")
  end

  def assert_comparison_fails(expected, actual, pattern = /differ/)
    error = assert_raises(HomebrewTap::Automation::Error) do
      HomebrewTap::Automation::BottleArtifactComparator.compare!(
        expected,
        actual,
      )
    end
    assert_match pattern, error.message
  end
end
