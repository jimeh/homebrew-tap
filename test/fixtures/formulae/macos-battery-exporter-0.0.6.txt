class MacosBatteryExporter < Formula
  desc "Prometheus exporter for battery metrics"
  homepage "https://github.com/jimeh/macos-battery-exporter"
  url "https://github.com/jimeh/macos-battery-exporter/archive/refs/tags/v0.0.6.tar.gz"
  sha256 "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  license "MIT"

  bottle do
    root_url "https://github.com/jimeh/homebrew-tap/releases/download/macos-battery-exporter-0.0.6"
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  end

  depends_on :macos
  depends_on "go" => :build

  def install
    system "go", "build", *std_go_args
  end
end
