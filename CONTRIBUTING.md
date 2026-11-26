# Contributing to Grove

Thanks for helping. Grove is a small, independent macOS app, so a short issue before a large change saves everyone time.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report security problems privately as described in the [Security policy](SECURITY.md), never in a public issue.

## Ground rules

These are project decisions, not open questions. Changes that conflict with them will not be merged.

- **No telemetry, analytics, accounts or license activation.** New code and dependencies must fit the [privacy policy](docs/PRIVACY.md).
- **Independent implementation.** Do not copy Supacode (or any other app's) code, artwork or assets.
- **MIT licensing.** Your contribution is released under the [MIT License](LICENSE). Keep dependency notices in `Notices/` and add one for any new dependency.
- **Accepted release policy.** Builds are ad-hoc-signed and not notarized, on purpose. Do not add Apple signing, notarization or credentials, and describe artifacts truthfully. See [Release policy](docs/RELEASING.md).
- **Tagged releases only.** No automatic version bumps or scheduled releases.

## Development setup

You need macOS 14 or later, Xcode with Swift 6.2+, Python 3.9+, system Git and tmux:

```sh
brew install tmux
make build          # builds dist/Grove.app for your Mac's architecture
open dist/Grove.app
```

More detail: [Development and operations](docs/DEVELOPMENT.md) and [Architecture](docs/ARCHITECTURE.md).

## Checks

Run the full suite before opening a pull request:

```sh
make check   # unit/regression tests, Git/state/script checks, packaging and an isolated GUI relaunch
make lint    # validates GitHub workflow files
git diff --check
```

`make check` needs a logged-in graphical session. Checks use temporary repositories and their own tmux sessions; they do not touch your real workspaces. CI runs the same checks on an Apple Silicon runner for every pull request. Intel builds are compiled for releases but not run in CI, so mention it if you can test on an Intel Mac.

Add or update a test in `Tests/GroveTests` or `Checks/` for any behavior change you can exercise outside the UI. See [Testing](docs/TESTING.md) for acceptance scenarios.

## Pull requests

1. Branch from `main` and keep each pull request to one topic.
2. Use the commit style already in the history: `fix: …`, `feat: …`, `perf: …`, `docs: …`, `build: …`.
3. Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.
4. Update the docs your change affects (user guide, feature matrix, privacy or architecture).
5. Say what you verified and how. If you only built it, say so. "Passes `make check`" does not mean "checked visually", and [Validation](docs/VALIDATION.md) records only checks that actually ran.
6. For UI changes, add a screenshot and note keyboard and VoiceOver behavior. Icon-only controls need an accessibility label and a tooltip.

## Reporting bugs and requesting features

Use the issue forms. For bugs, include the Grove version, macOS version, Mac architecture, whether tmux persistence is on, and exact steps. Check [Troubleshooting](docs/DEVELOPMENT.md#troubleshooting) first. Many terminal and Git problems come from shell configuration or the repository itself.
