# Security policy

## Supported versions

Grove is released only from `vMAJOR.MINOR.PATCH` tags. Security fixes target the `main` branch and the most recent tagged release. Older releases do not receive backported fixes; upgrade to the latest release.

| Version | Supported |
|---|---|
| Latest tagged release | Yes |
| `main` | Yes |
| Older releases | No |

## Reporting a vulnerability

**Do not open a public issue, discussion or pull request for a security problem.**

Report it privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. This creates a private advisory visible only to you and the maintainers.

Please include:

- the Grove version or commit (`release.json`, or **About Grove**), macOS version and Mac architecture;
- what an attacker can do, and what they need first (local access, a crafted repository, a malicious remote, and so on);
- steps or a minimal repository that reproduce it;
- any workaround you know of.

You should get an acknowledgement within 7 days. We will keep you updated while we investigate, agree a disclosure date with you, and credit you in the advisory and changelog unless you ask us not to.

## Scope

In scope: code in this repository and the packaged `Grove.app` built from it. That includes Git worktree creation and removal, workspace metadata storage and recovery, tmux/screen session handling, script import and execution, the `scripts/grove` CLI, and the build, packaging and release tooling.

Out of scope, unless Grove makes the problem worse:

- **Commands you run.** Shell commands, saved scripts, coding agents, Git hooks and shell startup files run with your own user permissions, as they would in Terminal. Grove does not sandbox them. See [Privacy](docs/PRIVACY.md).
- **Third-party software.** SwiftTerm, tmux, Git, `gh` and coding agents have their own security processes. Report their bugs upstream; tell us too if Grove is affected.
- **The accepted distribution policy.** Release builds are ad-hoc-signed and not notarized by Apple, by design (see [Release policy](docs/RELEASING.md)). Gatekeeper prompts on a downloaded build are expected and are not a vulnerability. A broken signature, a checksum mismatch, or a tampered archive that still passes Grove's own verification *is* in scope.

## Verifying a download

Each release publishes a `SHA256SUMS` file and `release-manifest.json` next to the archive. Check the archive before opening it:

```sh
shasum -a 256 -c SHA256SUMS
codesign --verify --deep --strict Grove.app
```

Grove has no telemetry, account or automatic updater, so it never downloads or installs updates on its own.
