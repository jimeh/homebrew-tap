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

## Formulas

The following Homebrew Formulas are provided by this Homebrew Tap:

- [`macos-battery-exporter`](https://github.com/jimeh/macos-battery-exporter) —
  Prometheus exporter for detailed battery metrics on macOS.

## Maintaining the Tap

Pull requests are checked with Homebrew's `brew test-bot` on Apple Silicon and
Intel macOS, plus ARM64 and x86-64 Linux. Formula pull requests upload bottle
artifacts for review but never publish them automatically.

After a formula pull request is reviewed and all checks pass, run the
`brew pr-pull` workflow with its pull request number and exact tested head SHA.
The workflow publishes bottles as assets on a formula-specific release in this
repository, adds the resulting `bottle do` block, and updates `main`.

The `Update formula` workflow accepts manual or `formula-release` repository
dispatch events for an allowlisted project. It independently verifies the
published upstream release, resolved tag commit, and source checksum before
opening a same-repository update pull request. It becomes usable after the
source formula migration and requires these repository settings before it can
create pull requests:

- Variable: `RELEASE_BOT_CLIENT_ID`
- Secret: `RELEASE_BOT_PRIVATE_KEY`
- Label: `automated-formula-update`

Initial formula migration and the first generated updates remain manually
gated. Trusted automatic publication will be enabled separately after this
workflow has been exercised.

See [the implementation plan](HOMEBREW_FORMULAE_AND_BOTTLES_PLAN.md) for the
rollout sequence, security boundaries, and progress.

## License

[CC0](https://github.com/jimeh/homebrew-tap/blob/main/LICENSE)
