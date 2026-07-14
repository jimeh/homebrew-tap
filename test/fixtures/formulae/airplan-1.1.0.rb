class Airplan < Formula
  desc "Upload plans"
  homepage "https://github.com/jimeh/airplan"
  url "https://github.com/jimeh/airplan/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  license "MIT"

  depends_on "go" => :build

  def install
    system "go", "build", *std_go_args
  end
end
