# Lifecycle status: Grove 0.3.0 (native macOS, no backend)
Updated: 2026-11-26   Environment tested: source at `main` 5cfb94c (static review; no Mac, no live run)

| Area | Skill | Last run | Blockers | Should-fix | Open / UNVERIFIED | Report |
|------|-------|----------|----------|------------|-------------------|--------|
| Positioning | pre-launch-icp-research | — | n/a | — | Skipped (see decisions) | — |
| Ship check (10) | vibe-app-security-check | 2026-11-26 | 0 | 0 open; S-1, S-3, S-4 fixed | #10 covered by Dependabot + OSV-Scanner going forward; S-2 owner decision | [ship-check.md](../security/ship-check.md) |
| Transport, identity, device storage | secure-app-server-comm | 2026-11-26 | 0 | 0 | — | [secure-comm-report.md](../security/secure-comm-report.md) |
| DAST + authz matrix + CI | security-self-test | 2026-11-26 | n/a | 0 (phase 3 CI applied) | No server: phases 0-2 n/a | `.github/workflows/security.yml` |
| Data, vendors, rights, evidence | launch-data-protection-audit | 2026-11-26 | 0 | 0 open; P-1, P-2, P-3 fixed | P-4 owner decision | [data-protection-report.md](../privacy/data-protection-report.md) |
| UI states | ui-states-audit | 2026-11-26 | 0 | 0 open; U-1 to U-6 fixed | Not checked visually | [ui-states.md](../ux/ui-states.md) |
| Native launch | optimistic-app-launch | 2026-11-26 | 0 | 0 | Timing not measured | [launch-audit.md](../performance/launch-audit.md) |
| Web / API performance | web-perf-pass | — | n/a | — | Not a web app | — |

## Launch decision
**Ready under the accepted release policy, with Should-fix items.** No Blockers. vibe #1-4 are settled (n/a or PASS). The authz matrix and interception test are n/a because there is no server. The ad-hoc/non-notarized distribution is accepted policy (`AGENTS.md`) and is not counted.

## Recommended fix order
1. ~~**S-1** confirm `grove://` actions~~ fixed 2026-11-26
2. ~~**S-3** confirm before opening code from the file browser~~ fixed 2026-11-26
3. **S-2** owner decision on repository-configured programs in background Git polls
4. ~~**P-1** Reset deletes~~ and ~~**P-3** "Remove from Grove…"~~ fixed 2026-11-26
5. ~~**S-4** Dependabot + security workflow~~ fixed 2026-11-26
6. ~~**U-1** clone progress and Cancel~~ fixed 2026-11-26 (fetch-before-create is still not cancellable)
7. ~~**P-2** privacy doc list; **U-2 to U-6** small UI states~~ fixed 2026-11-26

## CI security (self-test phase 3, applied 2026-11-26)
Applied with OSV-Scanner instead of dependency review (which needs the repository dependency graph enabled) and without CodeQL: one `.github/dependabot.yml` (ecosystems `github-actions` and `swift`, weekly) and one `security.yml` workflow running `actions/dependency-review-action` on pull requests and a secret scan (gitleaks) on push, with every action pinned by SHA like the existing workflows. CodeQL for Swift needs a macOS build and adds minutes, so it is optional.

## Next scheduled checks
- Each pull request: existing Quality checks (`scripts/check.sh` on macos-26, Apple Silicon)
- When adding a URL action, Git invocation, file-opening path or new stored field: re-run the matching rows (Workflow C)
- Before each tagged release: re-run this gate
