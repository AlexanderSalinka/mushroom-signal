# Mushroom Signal

macOS widget + companion app: mushroom-foraging forecasts for Slovakia.

## Build & Test
- Core logic lives in `MushroomSignalCore/` (Swift Package) — builds/tests standalone, no Xcode needed: `swift test --package-path MushroomSignalCore`
- App + widget live in `MushroomSignal.xcodeproj`, generated from `project.yml` via XcodeGen — both the yml AND the generated `.xcodeproj` are tracked in git; edit `project.yml`, then re-run `xcodegen generate`, never hand-edit the `.xcodeproj`
- XcodeGen does NOT auto-detect new/changed `.swift` files — after adding a file, re-run `xcodegen generate` or the build silently links a stub missing the new code
- Unsigned/headless builds: add `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` to `xcodebuild` to skip the signing preflight check
- **Never combine the unsigned/headless flags above with the pinned `-derivedDataPath DerivedData`** — confirmed this overwrites the signed app/widget build product in place, wiping entitlements (App Sandbox, App Group) back to `adhoc`/`TeamIdentifier=not set` and breaking widget-gallery visibility, exactly as if it had never been signed. Headless builds (e.g. compile-check for the widget extension, no test target) should either omit `-derivedDataPath` (falls back to a throwaway per-project hash folder) or use a separate path like `-derivedDataPath DerivedData-Headless`. If a signed run build is needed after a headless one touched `DerivedData/`, rebuild with `DEVELOPMENT_TEAM=UMPK75W8X6 CODE_SIGN_IDENTITY="Apple Development"` (no signing-bypass flags) before relying on `DerivedData/Build/Products/Debug/MushroomSignal.app` again
- **Always pass `-derivedDataPath DerivedData`** (repo-relative, already gitignored) to every `xcodebuild` invocation. Without it, each `xcodegen generate` that changes the project's internal identity gets its own hash-named folder under `~/Library/Developer/Xcode/DerivedData/`, and old ones don't get cleaned up automatically — confirmed this produced two separate `MushroomSignal.app` registrations that both showed in Spotlight/Launchpad. A pinned path keeps exactly one build output, one Launch Services registration, ever.
- Never run `xcodebuild -runFirstLaunch` — hangs on a GUI auth prompt for irrelevant iOS device-debugging components
- If `xcodebuild` fails on a missing `CoreSimulator.framework`, run `xcrun simctl list` once (headless-safe, triggers the needed component install)
- Check signing identity status with `security find-identity -v -p codesigning`
- Signing identity display name and the actual resolved Team ID can differ (confirmed: identity showed "874AQNKWTM", entitlements resolved to "UMPK75W8X6") — verify with the *built* entitlements (`codesign -d --entitlements :- <path>`), don't assume the identity string is the Team ID
- Headless-launch a signed build directly: `DerivedData/Build/Products/Debug/MushroomSignal.app` (repo-relative, now that builds use the pinned `-derivedDataPath` above)
- No git remote is configured — this repo is 100% local; don't assume `git push`/PR workflows work without setting one up first

## Testing Patterns
- Network code: inject a mocked `URLProtocol` via `URLSessionConfiguration` (see `OpenMeteoClientTests.swift`) — tests must never hit the live network
- `UserDefaults`-backed code: use a unique UUID-suffixed suite name per test + `removePersistentDomain` cleanup in `defer` (see `RegionStoreTests.swift`) — prevents cross-test pollution

## Project Conventions
- Widget supports `.systemSmall`, `.systemMedium`, `.systemLarge` (shipped from v2 spec §5) — `ShortlistWidgetView` branches on `@Environment(\.widgetFamily)`; large shows a 4-item shortlist with a hero row for #1 (hero + 3 rows), small/medium stay at 3 items — medium keeps `bodySize` names (not `titleSize`, which reopened a height overflow) but adds the latin name back *inline* on the same line as the common name (not a second line), using medium's extra width over small instead of vertical space it doesn't have (see `ShortlistProvider.getTimeline` in `MushroomSignalWidget.swift`). Sizing is verified qualitatively against each family's real on-screen frame plus a `.minimumScaleFactor(0.8)` fallback on the hero/row name and latin-subtitle text, rather than an exact computed pt budget — the final review (2026-08-06) found the widget frame sizes and WidgetKit's default content-margin behavior hadn't been independently confirmed, so no specific pt figure is asserted here
- When a task review's fix round changes committed code from what a plan doc originally specified, mirror the fix back into the plan `.md` via a `docs: correct plan to reflect...` commit — plan docs are meant to stay accurate, not frozen at first-draft
- Workflow for new features: brainstorm → design spec in `docs/superpowers/specs/` → implementation plan in `docs/superpowers/plans/` → build via subagent-driven-development (fresh implementer per task, independent reviewer that re-verifies build/test claims rather than trusting reports)
- **Known open issues from the v1 final review, not yet fixed** — see `docs/superpowers/KNOWN_ISSUES.md`

## Hard Constraints
- Species dataset (`species.json`) is original content — never scrape nahuby.sk or any other site into it (checked during design: no API, blocks bots, content is copyrighted)
- All new UI styling routes through `DesignSystem` (`MushroomSignalCore/.../DesignSystem/DesignSystem.swift`) — colors, spacing, golden-ratio scale — never hardcode ad hoc values
- macOS App Groups need the team-ID prefix (unlike iOS) — see `RegionStore.swift`'s `TeamIdentifier`/`resolvedAppGroupId` for the dynamic-resolution pattern; don't hardcode a bare `group.xxx` string anywhere
