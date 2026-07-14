class MacosBatteryExporter < Formula
  desc "Prometheus exporter for detailed battery metrics on macOS"
  homepage "https://github.com/jimeh/macos-battery-exporter"
  url "https://github.com/jimeh/macos-battery-exporter/archive/refs/tags/v0.0.6.tar.gz"
  sha256 "a6477d67cd7e4253b548fccd9bbd9214c473c21a45bb6894a8265e5709124a3e"
  license "MIT"
  head "https://github.com/jimeh/macos-battery-exporter.git", branch: "main"

  depends_on "go" => :build
  depends_on :macos

  def install
    ENV["CGO_ENABLED"] = "0"
    ldflags = "-s -w -X main.version=#{version}"
    system "go", "build", "-buildvcs=false", *std_go_args(ldflags:)
  end

  service do
    run [opt_bin/"macos-battery-exporter", "-s"]
    keep_alive true
    process_type :background
  end

  test do
    assert_match version.to_s,
                 shell_output("#{bin}/macos-battery-exporter -v")
  end
end
