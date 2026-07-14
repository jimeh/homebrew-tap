class Airplan < Formula
  desc "Turn a local document into a readable, shareable link"
  homepage "https://github.com/jimeh/airplan"
  url "https://github.com/jimeh/airplan/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "6ef89558c9340f73f1bbbec23d4e089f58cc34e2443303964dba4137f52eb27f"
  license "MIT"
  head "https://github.com/jimeh/airplan.git", branch: "main"

  depends_on "go" => :build

  def install
    ENV["CGO_ENABLED"] = "0"
    ldflags = "-s -w -X github.com/jimeh/airplan/cli.version=#{version}"
    system "go", "build", "-buildvcs=false", *std_go_args(ldflags:)
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/airplan --version")
  end
end
