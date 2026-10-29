# Grove documentation

Grove is a native macOS coding workspace being expanded toward Supacode-like workflows. The reference source is pinned to commit `1ffcc2e93c3f74fe3d52183176542fa8852ad2ba`; feature coverage and evidence must distinguish inspected source, packaged-app observations, implemented behavior and verified behavior.

| Document | Purpose |
|---|---|
| [Release policy](RELEASING.md) | Local builds, tag-only CI/CD, accepted ad-hoc policy and current validation boundaries. |
| [User guide](USER-GUIDE.md) | Use the current independent app and understand its limits. |
| [Feature coverage](FEATURE-PARITY.md) | Upstream behavior inventory, current Grove implementation and acceptance targets. |
| [Architecture](ARCHITECTURE.md) | Existing implementation and target design responsibilities. |
| [Testing](TESTING.md) | Reproducible checks and feature acceptance scenarios. |
| [Validation](VALIDATION.md) | Checks actually executed and their observed outcome. |
| [REA findings](REA-FINDINGS.md) | Retained packaged-app metadata/architecture Evidence and its limits. |
| [Supacode investigation](SUPACODE-EVIDENCE.md) | Pinned source evidence and the original investigation’s boundaries. |
| [Privacy](PRIVACY.md) | Local storage, no-telemetry policy, and user-initiated external calls. |
| [Development and operations](DEVELOPMENT.md) | Build, local packaging, storage, troubleshooting and release requirements. |
| [REA setup output](rea-setup.txt) | Recorded result of the approved Codex registration setup. |

The feature matrix describes current source capabilities and explicitly retains missing parity. Planned architecture and acceptance scenarios are not completion claims. The user requested an independent implementation without telemetry; Supacode code/assets are not adopted.

Raw REA and runtime evidence under docs/evidence is generated locally and excluded from Git because it can include local paths and packaged third-party configuration. Links to those files apply to the inspected workspace. CI runs regenerate their own check results; evidence is not included in delivery app archives.
