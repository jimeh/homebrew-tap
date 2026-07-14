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

- [`airplan`](https://github.com/jimeh/airplan) — turns a local document into a
  readable, shareable link on macOS and Linux.
- [`macos-battery-exporter`](https://github.com/jimeh/macos-battery-exporter) —
  exports detailed macOS battery metrics for Prometheus.

Install a formula directly, without tapping the repository first:

```sh
brew install jimeh/tap/airplan
brew install jimeh/tap/macos-battery-exporter
```

Once bottles are published, ordinary installs use the compatible bottle for
the current platform. To build a tagged release from source instead, pass
`--build-from-source`:

```sh
brew install --build-from-source jimeh/tap/airplan
brew install --build-from-source jimeh/tap/macos-battery-exporter
```

Both formulae also support building the latest upstream development version:

```sh
brew install --HEAD jimeh/tap/airplan
brew install --HEAD jimeh/tap/macos-battery-exporter
```

### Migrating an existing Airplan cask install

Airplan was previously distributed as a cask. Existing cask installations do
not automatically become formula installations, so migrate them once with:

```sh
brew uninstall --cask airplan
brew install --formula jimeh/tap/airplan
```

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
opening a same-repository update pull request. The required repository settings
are configured:

- Variable: `RELEASE_BOT_CLIENT_ID`
- Secret: `RELEASE_BOT_PRIVATE_KEY`
- Label: `automated-formula-update`

The update workflow has not yet been exercised end to end. Initial formula
migration and the first generated updates remain manually gated. Trusted
automatic publication will be enabled separately after this workflow has been
exercised.

See [the implementation plan](HOMEBREW_FORMULAE_AND_BOTTLES_PLAN.md) for the
rollout sequence, security boundaries, and progress.

## License

[CC0](https://github.com/jimeh/homebrew-tap/blob/main/LICENSE)
