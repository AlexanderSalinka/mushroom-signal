# Mushroom Signal v4 — GPS Find-Pinning & Photo Identification

## Relationship to v1/v2/v3

v1 (merged) shipped the widget, companion app, region-based shortlist, and signal scoring.
v2 (spec written) adds the interactive map and species library. v3 (spec written) adds a
personal find log with **manual map-tap** location entry, proactive notifications, and
trend timelines. This spec has two parts:

1. **Amends v3's find log**: adds GPS as the primary way to pin a find, with manual
   map-tap kept as the fallback — not a replacement, a superset. Everything else in v3
   (the `Find` model shape, SwiftData storage, the "My Finds" map layer) stays as designed;
   only how a find's location gets set changes.
2. **Adds photo-based species identification** as a wholly new capability, and a connective
   flow tying it to the GPS find-pinning and v2's map.

**Priority, per your explicit direction:** GPS + pin-based find mapping is the main goal
of this spec. Photo ID is real and worth designing now, but is inherently a longer,
staged effort (see §3) — don't let its complexity block shipping the GPS/pin work first.

## Goals

1. Add GPS location services so a find can be pinned at your actual current location
   with one tap, instead of manually finding yourself on the map.
2. Photo-based species identification: snap a photo, get candidate species matches,
   confirm which one it was, log it as a find — all as one flow.
3. Connect a confirmed find (via photo or manual entry) to v2's map: "see where else
   this species is likely right now," pre-filtered to that species.

## Out of Scope

- **Sharing/social features** (making your pins visible to other foragers, a community
  map) — explicitly your call to defer this. Everything in this spec is designed as if
  the app will only ever be local-only and single-user; sharing would be a genuinely
  separate spec later (new backend, privacy model, moderation questions — not a small
  add-on to bolt in afterward).
- **Continuous location tracking** — this is one-shot "where am I right now" capture for
  pinning a find, not a background tracking feature. No location history is recorded
  beyond what's attached to a logged find.
- **Trip/route recording** (breadcrumb trail of a whole forest walk, for retracing your
  steps and reviewing "best routes" later) — genuinely valuable idea, raised and
  deliberately parked 2026-08-05: this needs a phone in your pocket while walking, not a
  Mac, so it's really a future iOS-companion-app feature, not something to design against
  this macOS app. Keep in mind for whenever an iOS build becomes real; not a task now.
- **Guaranteeing photo-ID accuracy** — see §3's safety framing. This spec designs the
  *mechanism*, not a promise of reliable identification, especially for dangerous
  lookalikes.
- **Any change to the signal-scoring algorithm, the species dataset schema, or v1/v2's
  existing screens** beyond the map-jump connective flow in §4.

## 1. GPS Location Services

**This reverses v1's deliberate "no CoreLocation" decision.** That was the right call for
a couch-checked forecast widget; it's the wrong call for a feature meant to be used
standing in a forest. Worth being explicit about since it's a real scope expansion, not
a small addition.

**Entitlement:** macOS sandboxed apps need the Location capability enabled, which adds a
`com.apple.security.personal-information.location` entitlement (name given here for
planning purposes — **confirm the exact key by adding the "Location" capability via
Xcode's Signing & Capabilities UI once**, rather than hand-writing it into `project.yml`
from memory, then mirror whatever Xcode actually generates back into `project.yml` so
`xcodegen generate` stays the source of truth).

**Info.plist:** `NSLocationWhenInUseUsageDescription` — a user-facing string explaining
why (e.g. "Mushroom Signal uses your location to pin where you found something."). This
key is required or the app is rejected outright when it requests authorization.

**API:** `CLLocationManager.requestLocation()` — a single one-shot location fetch, not
continuous tracking (matches the "no background tracking" scope boundary above). macOS
has one real quirk worth planning for: its authorization status check differs slightly
from iOS (checks against `.authorized`, not iOS's `.authorizedWhenInUse`), and the
system-level Location Services toggle (System Settings → Privacy & Security) must also be
on independently of the app's own permission — the app should handle "denied" or
"system services off" gracefully, not just "permission not yet asked."

**Known real-world limitation, worth designing around rather than being surprised by
later:** GPS accuracy degrades under dense forest canopy — sometimes significantly. The
pin-placement UI should always let you drag/adjust the pin after GPS fills it in, never
lock it as non-editable. This also means manual map-tap isn't just a permission-denied
fallback — it's a genuinely useful correction tool even when GPS "worked."

## 2. Find Log — GPS-First Pinning (amends v3 §1)

v3's `Find` model gains a field recording how the location was set:

```swift
public enum LocationSource: String, Codable, Sendable {
    case gps
    case manual
}

public struct Find: Identifiable, Codable, Sendable {
    public let id: UUID
    public let speciesId: String
    public let date: Date
    public let latitude: Double
    public let longitude: Double
    public let locationSource: LocationSource
    public let photoData: Data?
    public let notes: String?
}
```

**Flow:** "Log a Find" now attempts a GPS fetch first (showing a brief loading/permission
state). On success, the pin pre-fills at the current location, adjustable by drag. If
location is denied, unavailable, or the user prefers it, they fall through to v3's
original manual map-tap — same UI, no dead end. Everything else in v3's find log (the
"My Finds" map layer, the chronological list, SwiftData storage) is unchanged.

## 3. Photo-Based Species Identification

**Read this section's framing before the mechanism — it matters more here than in any
other part of this app.** This dataset includes species where misidentification is
fatal, not just disappointing (*Amanita phalloides*, *Gyromitra esculenta*, and their
lookalike pairs already tracked in `species.json`). Academic benchmarks report
90-99%+ accuracy for fungi classifiers, but those numbers come from curated test photos
— not messy, variable-light, real-forest phone-camera shots of the exact confusable
pairs that matter most here. Treat that gap as real, not a rounding error.

**Non-negotiable product constraint, carried through every part of this feature:**
photo ID **suggests candidates for you to confirm — it never states a verdict**. The
UI never says "this is X." It shows ranked candidates with confidence and lets you
decide, informed by your own 20 years of judgment. Any candidate whose `edibility` is
`.poisonous` gets the same warning treatment (⚠️, `DesignSystem.Colors.danger`) already
used in the shortlist and widget — a photo match doesn't bypass the safety UI the rest
of the app already has.

### Phase A — Data (not code; your effort, not Claude's)

Organize your own foraging photo library into folders per species, named to match
`species.json`'s existing `id` values (e.g. `boletus-edulis/`, `gyromitra-esculenta/`)
so the training data lines up 1:1 with the app's existing species identities — no new
naming scheme to invent or reconcile later. This is a uniquely strong dataset for this
specific app: authentic Slovak specimens, expert-labeled by you, not a generic academic
set with unknown regional relevance.

**Recommendation, not a requirement:** start with a smaller subset of visually
distinctive species (where confident, correct classification is realistically
achievable) rather than attempting all 27 at once. Get one working, honestly-evaluated
loop before extending to the hardest lookalike pairs — those deserve the most scrutiny,
not the least, and are the worst place to discover the approach doesn't work well
enough.

### Phase B — Training

Apple's **Create ML** (built into Xcode, no separate ML tooling or expertise required)
trains an image classifier directly from Phase A's labeled folders and exports a
`.mlmodel` file. This runs entirely on your machine — no cloud training service, no
photos leave your control.

### Phase C — Integration

The exported model is bundled as an app resource and run on-device via the **Vision**
framework (`VNCoreMLRequest`) — inference happens locally, no network call, consistent
with the rest of the app's local-only architecture and the existing "no secrets/no
backend" constraint.

```swift
public struct SpeciesMatch: Identifiable, Sendable {
    public let id: String          // species id
    public let confidence: Double  // 0...1
}

public protocol SpeciesIdentifier: Sendable {
    func identify(image: Data) async throws -> [SpeciesMatch]  // top-N candidates, ranked
}
```

**UI flow:** camera capture or photo-picker → run inference → show the top 3 candidates
as cards (reusing the library's existing species-card presentation from v2, including
photos/edibility/lookalikes) → user taps the one that actually matches what they found
→ that confirmed species pre-fills a new Find Log entry (§2), continuing straight into
GPS pinning. One motion: photograph → candidates → confirm → pinned.

**Camera access**, if live capture (not just picking an existing photo) is wanted:
`com.apple.security.device.camera` entitlement (again, confirm the exact key via Xcode's
capability UI rather than hand-typing it) plus `NSCameraUsageDescription` in Info.plist.

## 4. Connective Flow — Confirmed Find → Map

After confirming a species (via photo ID or a manual Find Log entry), offer a "See
where else this is likely right now" action that jumps directly to v2's map with that
species already toggled on as the active heat layer — no new map subsystem, just wiring
an entry point into what v2 already designed. This is the "recommend other places to
visit" idea from brainstorming, delivered by connecting existing pieces rather than
building a new recommendation engine.

## Testing

- `LocationSource`/GPS-vs-manual pin logic: unit-testable at the model level (a `Find`
  correctly records which source set its coordinates); the actual `CLLocationManager`
  interaction is UI/system-level, verified manually (same category as v1/v2's SwiftUI
  view testing — build + manual check, not unit tests).
- `SpeciesIdentifier` protocol: designed with the same dependency-injection pattern as
  `WeatherClient` specifically so classification logic (ranking candidates, applying the
  poisonous-warning treatment to results) is unit-testable against a fake implementation
  returning fixed `SpeciesMatch` arrays — without needing a real trained model or camera
  in the test target.
- Actual model accuracy: **not unit-testable** — requires manual evaluation against a
  held-out set of your own photos before trusting any release of this feature. This is
  an ongoing evaluation process, not a one-time pass/fail check, and should be treated
  as such in whatever plan implements this phase.

## Open Questions for the Implementation Plan

- Exact entitlement key strings for Location and Camera — confirm via Xcode's capability
  UI at implementation time rather than trusting names recalled here.
- How many photos per species is "enough" to start — no fixed number here; Phase A is
  iterative, start with whatever you have and evaluate honestly before expanding.
- Whether to gate the photo-ID feature behind an explicit "this is experimental, verify
  everything yourself" acknowledgment on first use, on top of the existing app-wide
  disclaimer — leaning yes given the stakes, worth confirming before implementation.
- Order of implementation: GPS + pin-based find log (§1-2) is the stated priority and has
  no open feasibility questions. Photo ID (§3) is real but should probably be its own
  implementation cycle, started only once §1-2 is solid, given its data-collection
  dependency on your own time, not just engineering time.
