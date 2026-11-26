# Lifecycle decisions: Grove

Recorded 2026-11-26 for the first `app-lifecycle-orchestrator` run (Workflow B, existing project, audit only).

| Decision | Value | Source |
|---|---|---|
| App shape | Native macOS desktop app, **no backend**: no first-party server, accounts, database, API or telemetry | `docs/PRIVACY.md`, code recon |
| Release policy | Ad-hoc-signed, non-notarized, tagged-only releases. **Accepted policy, not a finding.** Signature, checksum and archive round-trip checks stay required | `AGENTS.md`, `docs/RELEASING.md` |
| Data sensitivity | Local developer data: repository paths, branch names, script commands, terminal scrollback. No personal data collected by Grove | Data inventory, `docs/privacy/data-protection-report.md` |
| Staging environment | None, and not needed: there is no server to stage | — |
| Pinning | n/a, no first-party host | `docs/security/secure-comm-report.md` |
| Optimistic launch | Already the behavior: saved state renders first, Git refresh follows | `docs/performance/launch-audit.md` |
| Spend caps | n/a, no paid services | — |
| CI architectures | Apple Silicon runner only (Intel runner removed 2026-11-26). Releases still build and verify both slices; Intel runtime is untested | User decision |

## Skills not run

| Skill | Reason |
|---|---|
| `pre-launch-icp-research` | Independent developer tool with established positioning (README). Skipped. |
| `security-self-test` phases 0-2 | No web app or API to attack (no ZAP, no authz matrix). Phase 3 (CI security) is proposed, not applied, in `status.md`. |
| `web-perf-pass` | Not a web app. |
| `secure-app-server-comm` §2-3, §7 | No first-party server, so no TLS config, pinning or interception test. |
| `vibe-app-security-check` #1-3, #5, #8, #9 | No database, storage, server auth, rate-limited endpoints, cloud backups or paid services. |

## Open owner decisions

- **S-2:** should background Git polls ignore repository-configured programs (`core.fsmonitor`, textconv), ask for repository trust, or accept and document? (`docs/security/ship-check.md`)
- **P-4:** keep workspace metadata in system backups, or exclude script commands? (`docs/privacy/data-protection-report.md`)
