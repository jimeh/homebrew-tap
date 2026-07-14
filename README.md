<h1 align="center">
  jimeh's Homebrew Tap
</h1>

<p align="center">
  <strong>
    Homebrew tap for various projects by <a href="https://github.com/jimeh">@jimeh</a>.
  </strong>
</p>

<p align="center">
  <a href="https://github.com/jimeh/homebrew-tap/issues"><img src="https://img.shields.io/github/issues-raw/jimeh/homebrew-tap.svg?style=flat&logo=github&logoColor=white" alt="GitHub issues"></a>
  <a href="https://github.com/jimeh/homebrew-tap/pulls"><img src="https://img.shields.io/github/issues-pr-raw/jimeh/homebrew-tap.svg?style=flat&logo=github&logoColor=white" alt="GitHub pull requests"></a>
  <a href="https://github.com/jimeh/homebrew-tap/blob/main/LICENSE"><img src="https://img.shields.io/github/license/jimeh/homebrew-tap.svg?style=flat" alt="License Status"></a>
</p>

## Install Tap

```
brew tap jimeh/tap
```

## Packages

This tap provides:

- [`airplan`](https://github.com/jimeh/airplan) — turns a local document into a
  readable, shareable link on macOS and Linux. Its GoReleaser-managed Cask
  installs upstream release binaries.
- [`macos-battery-exporter`](https://github.com/jimeh/macos-battery-exporter) —
  exports detailed macOS battery metrics for Prometheus. Its tap-owned Formula
  builds from source and supports Homebrew bottles.

Install either package directly, without tapping the repository first:

```sh
brew install jimeh/tap/airplan
brew install jimeh/tap/macos-battery-exporter
```

Airplan's Cask is generated and updated by GoReleaser in its upstream
repository.

The exporter pours an `arm64_sequoia` bottle on Apple Silicon macOS 15 or
newer. Apple Silicon macOS 14 and all Intel Macs build it from source. Older
macOS releases are unsupported in line with Homebrew's support policy.

To explicitly build a tagged exporter release from source, pass
`--build-from-source`:

```sh
brew install --build-from-source jimeh/tap/macos-battery-exporter
```

The exporter Formula can also build the latest upstream development version:

```sh
brew install --HEAD jimeh/tap/macos-battery-exporter
```

## Maintaining the Tap

Pull requests run the automation test suite on Ubuntu and Homebrew's
`brew test-bot` on a pinned Apple Silicon macOS 15 runner. Exporter Formula
pull requests upload one `arm64_sequoia` bottle artifact for review but never
publish it automatically. Cask-only changes produce no bottle.

After a formula pull request is reviewed and all checks pass, run the
`brew pr-pull` workflow with its pull request number and exact tested head SHA.
The workflow publishes bottles as assets on a formula-specific release in this
repository, adds the resulting `bottle do` block, and updates `main`.

The `Update formula` workflow accepts manual or `formula-release` repository
dispatch events for `macos-battery-exporter`. It independently verifies the
published upstream release, resolved tag commit, and source checksum before
opening a same-repository update pull request. Airplan remains wholly managed
by its upstream GoReleaser configuration. The required repository settings are
configured:

- Variable: `RELEASE_BOT_CLIENT_ID`
- Secret: `RELEASE_BOT_PRIVATE_KEY`
- Label: `automated-formula-update`

The update workflow has not yet been exercised end to end. The exporter's first
bottle and generated updates remain manually gated. Trusted automatic
publication will be enabled separately after this workflow has been exercised.

See [the implementation plan](HOMEBREW_FORMULAE_AND_BOTTLES_PLAN.md) for the
rollout sequence, security boundaries, and progress.

## License

[CC0](https://github.com/jimeh/homebrew-tap/blob/main/LICENSE)
