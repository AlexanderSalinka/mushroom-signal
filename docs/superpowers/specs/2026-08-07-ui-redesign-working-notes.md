> **Superseded 2026-08-08** by `2026-08-08-ui-visual-redesign-design.md`, written after the
> map reference image arrived and the color-mixing issue was diagnosed. These notes are kept
> for history; the new doc is complete and current.

# Mushroom Signal — UI Redesign Working Notes

**Status: IN PROGRESS, not a finished spec.** Captures what's been discussed in this
brainstorming session so far. The map-overlay section is explicitly blocked pending
reference images from Alexander — do not plan or implement that part until those
arrive and get discussed. The Zoznam/card/photo section below is further along but
still mid-brainstorm, not yet presented as a full design or approved.

## 1. Zoznam tab redesign — grid, shared card, photos

**Goal:** replace Zoznam's current vertical list (name/score-dots/reason rows) with a
photo-forward grid, visually unified with the Mapa tab's species library, and with a
single shared navigation pattern (tap a species anywhere → same detail view).

**Card:**
- Target size ~400×250pt, "YouTube thumbnail" style — big photo, gradient-scrim
  overlay carrying name/score/warning, not the current small ~70pt-tall thumbnail
  chips the library grid uses today.
- One shared `SpeciesCardView`-style component, used by both Zoznam and Mapa's
  library grid — same visual identity everywhere, not two separate card designs.
- Tap behavior differs by context, same visual card: Zoznam's primary tap opens
  `SpeciesDetailView` (existing, reused) directly. Mapa's library grid keeps its
  current toggle-active-on-map-layer behavior on tap, with the small "i" info button
  still opening detail — not yet confirmed with Alexander, this is the working
  default from the brainstorm, flag if wrong once we get back to this thread.

**Grid mechanics:**
- Replace the current manual column-count stepper (`SpeciesLibraryView`'s
  `columnCount` state, 2-4 range) with a real adaptive grid — `GridItem(.adaptive(
  minimum: 400, ...))` or equivalent — that reflows column count automatically as
  the app window is resized, targeting ~400×250 per card. Confirmed with Alexander:
  the drag/resize target is the app window itself (standard macOS resize), not a
  custom panel or drag-to-reorder gesture.
- Open question not yet resolved: does the manual stepper get removed entirely, or
  kept as an optional override on top of the adaptive default? Leaning toward
  removed (simpler, matches "way more beautiful"), not confirmed.

**Photos — two-part dependency, confirmed with Alexander:**
- `species-photos.json` currently has **zero entries** — the v2 spec's photo system
  was built (model, attribution fields, `AsyncImage` wiring) but the actual photo
  curation/sourcing work was never done. This needs a real research pass, similar in
  shape to the recent species-data enrichment: source real photo URLs for all 27
  species from Wikimedia Commons (CC-licensed, matches the existing `SpeciesPhoto`
  model's `photographer`/`license`/`sourceURL` fields — no new legal ground, same
  sourcing constraint already established for text data: no scraping non-licensed
  sites).
- New `PhotoCache` component: download-once-cache-locally, confirmed with Alexander
  over live-fetch-every-time or bundle-at-build-time. Given `SpeciesPhoto.imageURL`,
  check local disk first; download and persist on first use; load instantly after.
  Static content (a species' representative photo doesn't change), so no cache
  expiry needed. Replaces plain `AsyncImage` calls with a caching equivalent.

## 2. Map heat-overlay redesign — BLOCKED, pending reference images

Alexander does not like the current per-region heat overlay on the Mapa tab — his
words: "those big ass ready [circles] versus against all map... I do not want them to
be so big. I want them to be localized for each region." He's sending reference
images to clarify the intended visual before this gets designed further.

**What's known:**
- Current implementation: `InteractiveMapView` renders `MapCircle` per grid point
  (~39 points tiling Slovakia, ~18km radius each, per `gridPointRadiusMeters` in
  that file), colored by dominant active species, opacity 0.75 — this is what
  Alexander is calling "too big."
- He wants something smaller/more localized per region instead — exact shape,
  size, or visual treatment not yet specified. Do not guess at a redesign here;
  wait for the images.

**Do not start designing or implementing this until the images arrive and get
discussed.**

## 3. Backlog note, not in scope for either section above

Alexander mentioned a future idea for the Mapa tab: some kind of "battle map" /
route planner / route discoverer. No details given, purely a heads-up he dropped in
passing. Not part of this brainstorm — revisit when he brings it up with actual
intent to design it.
