# REA findings — installed Supacode

Target: `/Applications/supacode.app`, inspected 2026-10-28 using the REA 6.8.0 CLI. REA MCP registration exists, but this already-running agent session has not loaded its tools. The installed CLI was used directly. No Hopper or other native decompiler was installed or used.

## Observed facts

- `inspect_desktop_application` examined 919 entries, probed 9 files, and read 672 bytes of selected ranges. Its directory snapshot digest is `8587514198dbdc6b7d9c005a4210f134ddd1bd9e08679b6e3349ebf703686fc6`. This commits to retained metadata/read ranges, not every byte of every file. Parent Evidence: `ev_7b5a40efc90f33a3dcd52877636769d39e42e56a18f7ce4da1d1d95423b2ff5d`. [Complete retained bundle](evidence/supacode-desktop-bundle.json), [summary](evidence/supacode-desktop-summary.json).
- `inspect_plist` observed bundle ID `app.supabit.supacode`, version `0.11.6`, minimum macOS `26.0`, the `supacode` URL scheme, and PostHog configuration keys. Evidence: `ev_1e5d5c716a10d29da26573eb84115aa6afe8fd658417f9edfd8b1ff569f0e538`. [Complete Evidence](evidence/supacode-plist.json).
- `list_architectures` observed x86_64 and arm64 slices in the universal Mach-O. Executable SHA-256: `bbc5bad0a7106d4d9faf32037a9a66a30a6aac6972e92a75660e87d736a31485`. Evidence: `ev_fb30843abf987dcbbf5f729e68d4bf1ecda28766d518b0e8fa12ce392edc1044`. [Complete Evidence](evidence/supacode-architectures.json).

The native helper initially could not compile inside the workspace sandbox because Swift's compiler cache was unwritable. The two native inspection commands were rerun with explicit escalation and returned the retained successful Evidence above. The directory inventory did not require that helper.

## Inferences and limits

PostHog configuration is evidence of packaged configuration; no network capture was made, so it does not establish when or whether this installation sends events. The installed app version is not proven to correspond to the inspected upstream source commit. Source behavior and bundle facts are kept separate in the [source investigation](SUPACODE-EVIDENCE.md).

Grove does not reuse the Supacode executable, source implementation, activation code, analytics settings, assets or branding. Its terminal implementation uses MIT-licensed SwiftTerm and macOS's system screen utility. Grove's own code is MIT-licensed. No Supacode licensing checks were bypassed or patched.

## Grove runtime follow-up

REA targeted only Grove's verification window (PID 51694, window 8963). It returned `capability_unavailable` with `screen-recording-denied`; no screenshot/AX observation or broad fallback was obtained. [Diagnostic](evidence/grove-ui-observation.json). Independent functional checks of the packaged app did run, including [real shell restoration](evidence/grove-app-relaunch.json); those are ordinary harness evidence rather than REA UI Evidence.
