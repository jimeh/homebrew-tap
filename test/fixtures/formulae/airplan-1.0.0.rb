class Airplan < Formula
  desc "Upload plans"
  homepage "https://github.com/jimeh/airplan"
  url "https://github.com/jimeh/airplan/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  license "MIT"

  bottle do
    root_url "https://github.com/jimeh/homebrew-tap/releases/download/airplan-1.0.0"
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  end

  depends_on "go" => :build

  def install
    system "go", "build", *std_go_args
  end
end
