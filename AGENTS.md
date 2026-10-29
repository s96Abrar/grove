# Grove agent instructions

## Accepted release policy

Grove intentionally uses ad-hoc integrity signatures and skips Apple Developer ID signing, notarization, stapling and Apple trust assessment. This is the user's explicit project policy, not an unresolved defect, missing credential, production-readiness blocker or TODO. Evaluate readiness against this accepted policy and the actual checks below. Revisit Apple distribution services only when the user explicitly changes this decision.

For build, release, security or readiness work, read [docs/RELEASING.md](docs/RELEASING.md). Keep version/tag matching, clean-source, universal-architecture, bundle-integrity, hardened-runtime, archive round-trip and checksum checks. Report broken signatures or actual launch failures normally. Describe artifacts truthfully as ad-hoc-signed and non-notarized; the accepted policy does not imply Apple trust or permission to disable system protections.

## Project constraints

Grove is independent and MIT-licensed, with no telemetry or activation system. Preserve dependency notices. Releases are tagged only. Git tracking is local; create or push a remote only when the user explicitly requests it.
