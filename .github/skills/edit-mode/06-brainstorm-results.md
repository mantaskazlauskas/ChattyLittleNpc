# Edit Mode Integration — Brainstorm Results

> **Mode**: Plus Ultra (9 agents across 3 model families)
> **Models**: Claude Opus 4.6, GPT 5.3 Codex, Gemini 3 Pro, Claude Sonnet 4.6, GPT 5.1
> **Raw ideas**: 34 → 11 clusters → 19 scored → 8 recommended

---

## TL;DR

The addon already has 70% Edit Mode coverage. The highest-impact next steps are **not**
deeper Blizzard API integration (high taint risk) but rather **UX polish**: preview staging,
curated presets, guided onboarding, and resolution safety. The wild card worth pursuing is
zone-based auto-switch (pivoted from spec-based).

---

## Knowledge Grounding

- **Domain**: Strong — full Blizzard FrameXML source analyzed (200+ functions)
- **Recency**: Current — Midnight 12.0 beta API documentation reviewed
- **Research**: 5 addon codebases analyzed (EditModeExpanded, LibEditMode, Bartender4, ElvUI, muleyoUI)
- **Critical correction**: Claude Sonnet caught that arrow-key nudging **already exists** in the codebase (lines 456-475 of EditModeIntegration.lua). Gemini caught that spatial audio panning is **technically infeasible** (no Lua API for stereo control).

---

## Ensemble Metadata

| Family | Ideas Generated | Cross-Pollination Hybrids | Critique Model |
|--------|:-:|:-:|----------------|
| **Claude** (Opus 4.6) | 12 | — | Sonnet 4.6 |
| **GPT** (5.3 Codex) | 12 | — | 5.1 |
| **Gemini** (3 Pro) | 10 | — | 3 Pro |
| **Cross-pollinator** | — | 5 | Sonnet 4.6 |

---

## Top Ideas (Ranked by Multi-Family Consensus)

### 🥇 1. Preview Staging — "You can't size what you can't see"

**Score**: Feasibility 8.0 | Impact 9.0 | Novelty 6.7 | **Total: 23.7**
**Consensus**: 🟢 All 3 families rated Impact 9. Unanimous #1.

When Edit Mode opens and the queue is empty, auto-inject a test NPC (model + sample text +
waveform preview) so users can position and resize the frame with realistic content visible.
Clear the dummy on Edit Mode exit.

**Why it wins**: The addon's unique value is voiceover + 3D models. Editing an empty rectangle
defeats the purpose. This already partially exists (dummy queue injection in EditPanel.lua
lines 687-705) — extend it to trigger automatically on Edit Mode enter.

**Implementation path**: Hook `EditModeManagerFrame:EnterEditMode`. If queue empty, call
existing `InjectSampleData()`. On `ExitEditMode`, clear sample. ~50 lines of code.

---

### 🥈 2. Curated Presets + Share Codes — "One-click 'wow' moment"

**Score**: Feasibility 8.3 | Impact 8.0 | Novelty 6.7 | **Total: 23.0**
**Consensus**: 🟢 Full agreement.

Ship 3-4 curated layout presets:
- **Cinematic** — large model, bottom-center, subtitle-style
- **Compact** — small, corner-tucked, minimal chrome
- **Immersive** — translucent, wide, cinematic letterbox feel
- **Streamer** — positioned to avoid face-cam overlay area

Plus: extend existing bundle import/export into shareable "DNA codes" with resolution-
normalized positions and version compatibility flags.

**Why it ranks high**: Solves "blank canvas paralysis." Social sharing via Wago.io/Discord
creates viral growth. Requires #4 (resolution safety) as dependency.

**Implementation path**: Create preset data files + one-click apply in EditPanel. Extend
existing bundle system with percentage-based positions. ~200 lines.

---

### 🥉 3. Guided Edit Mode Onboarding — "Features don't exist if nobody finds them"

**Score**: Feasibility 9.0 | Impact 8.3 | Novelty 5.3 | **Total: 22.7**
**Consensus**: 🟢 Full agreement. All families missed this in initial ideation — the
cross-pollinator identified it as the biggest gap.

First-time overlay when user enters Edit Mode with Chatty installed: pulsing hotspots on
drag handles, 4-step walkthrough (move → resize → snap → per-layout save), and a "Reset to
Recommended" escape hatch. Guard with `ChattyLittleNpcDB.hasSeenEditModeGuide`.

**Why it ranks high**: The addon has 15+ Edit Mode features users don't know exist. Lowest
implementation cost, highest discoverability ROI. Reduces Discord "how do I move this?" questions.

**Implementation path**: Create a simple overlay frame with animated highlights and text
prompts, triggered once. ~150 lines + guard flag.

---

### 4. Resolution-Normalized Storage — "The invisible backbone"

**Score**: Feasibility 8.0 | Impact 7.3 | Novelty 5.0 | **Total: 20.3**
**Consensus**: 🟢 All 3 families converged independently. Gemini called it "most underrated."

Store positions as both pixel offsets AND viewport percentages. On `DISPLAY_SIZE_CHANGED`,
recalculate pixels from percentages. Include anchor context and safe-bounds clamping to
prevent off-screen frames after monitor/resolution changes.

**Why it matters**: Prerequisite for presets (#2) and share codes to work across resolutions.
Prevents the #1 support issue ("my frame disappeared"). Pure Lua math, zero taint risk.

**Implementation path**: Extend `SaveFramePosition()` to compute and store `x_pct`/`y_pct`.
Add `DISPLAY_SIZE_CHANGED` listener. ~80 lines.

---

### 5. Sub-Element Layout Editing — "Resize the model without resizing the text"

**Score**: Feasibility 7.0 | Impact 7.0 | Novelty 5.3 | **Total: 19.3**
**Consensus**: 🟡 GPT and Gemini both rated Impact 8; Claude rated 5 (noting model height
slider already exists). The gap is about the **interaction modality** — drag-to-resize beats
a slider for spatial reasoning.

In Edit Mode, show secondary resize handles for the internal divider between the 3D model
area and the text/queue area. Users drag to allocate space visually instead of using a numeric
slider they can't mentally map to pixels.

**Why it's valuable**: The addon's frame is unique — it's not a uniform rectangle but a
composite of model + text. Power users want to prioritize one over the other per-layout.

**Implementation path**: Add a draggable divider bar between model and content regions
during Edit Mode. Map drag position to `npcModelFrameHeight`. ~120 lines.

---

### 6. Undo/Redo History — "Experiment without fear"

**Score**: Feasibility 6.7 | Impact 6.7 | Novelty 6.3 | **Total: 19.7**
**Consensus**: 🟡 Claude/GPT agree Impact 8, Gemini rates 4 ("over-engineering").

Extend existing `_orig` snapshot into a circular buffer (8-10 states). Push snapshot on each
drag-stop. Ctrl+Z pops (scoped to when Edit Mode overlay has focus). Add "Revert to Session
Start" button as panic button.

**Implementation path**: The `_orig` pattern is already step 1. Convert to table array with
pointer. ~100 lines.

---

### 7. Zone-Based Auto-Switch — "Context-aware layouts without manual switching"

**Score**: Feasibility 8.0 | Impact 6.3 | Novelty 4.3 | **Total: 18.7**
**Consensus**: 🟡 Pivoted by Claude Sonnet. Original "spec-change" idea is low-value for a
voiceover addon. **Zone-based** auto-switch (city=cinematic, raid=compact, dungeon=minimal)
is meaningfully different and uses `GetInstanceInfo()`.

Listen for zone changes. Map zone types to layout names. Auto-apply mapped layout.
Optional user confirmation toast on first switch.

**Implementation path**: Listen to `ZONE_CHANGED_NEW_AREA` + `GetInstanceInfo()`. Map to
layout names. ~100 lines.

---

## Wild Cards (High Novelty, Worth Preserving)

### 🃏 Phantom Multi-Layout Preview

**Score**: Feasibility 5.7 | Impact 6.0 | Novelty 8.3

Show translucent ghost outlines of where the frame lives in OTHER layouts while editing
the current one. Unique Figma-like concept no addon has attempted. High visual clutter risk
but compelling for content creators who manage multiple layouts.

### 🃏 Cinematic World Anchoring

**Score**: Feasibility 3.7 | Impact 8.0 | Novelty 9.0 | **🔴 SPLIT: GPT 9, Gemini 10, Claude 5**

Float the frame above the NPC's nameplate using WorldFrame projection. The "holy grail" of
immersive dialog UI (Cyberpunk 2077 style). Technically near-impossible due to jitter, nameplate
despawn, and camera angle issues — but the *instinct* is right. Worth prototyping as an
opt-in experimental mode.

---

## Parked Ideas (Not killed, just deferred)

| Idea | Reason to Park |
|------|---------------|
| System-Grade Registration | High taint risk (Gemini F:2). Revisit if Blizzard adds official addon system registration API |
| Cross-Addon Protocol | Zero-adoption problem. Revisit if ChattyLittleNpc spawns multiple positionable frames |
| Spatial Audio Viz | Technically infeasible (no Lua stereo panning API). Cool concept, wrong platform |
| Edit Mode Citizenship Protocol | Depends on System Registration. Park both together |
| Snap-Magnetism | Medium priority. Existing grid snap covers 80% of the need. Revisit after Top 7 shipped |

---

## Critical Corrections & Blind Spots

### Already Implemented (Don't Re-build)
- ✅ Arrow-key nudging (1px/5px/20px) — exists at EditModeIntegration.lua lines 456-475
- ✅ Grid snapping — exists using `accountSettings.gridSpacing`
- ✅ Sample data injection — exists in EditPanel.lua lines 687-705 (but not auto-triggered)
- ✅ Model height slider — exists (sub-element editing adds drag modality, not new capability)

### Blind Spots Identified by Critics
1. **Classic version degradation** (Claude Sonnet) — All ideas assume Edit Mode exists. Classic
   Era/Wrath/TBC have NO Edit Mode API. Need a **fallback positioning interface** for 50%+ of
   supported game versions.
2. **State explainability** (GPT) — With auto-switch, magnetism, and history, users need a
   "why is my frame here?" inspector to trust the system.
3. **Edit Mode taint** (Gemini) — Safest path is to **mimic** Edit Mode behavior rather than
   hook deeply into Blizzard's secure system. The addon already does this well.

---

## Recommended Implementation Order

```
Phase 1 (Quick Wins — ≤100 lines each):
  ├─ Preview Staging auto-trigger (extend existing code)
  ├─ Resolution-Normalized Storage (pure Lua math)
  └─ Guided Onboarding overlay (one-time walkthrough)

Phase 2 (Medium — ≤200 lines each):
  ├─ Curated Presets (depends on Phase 1 resolution storage)
  ├─ Sub-Element Drag Divider
  └─ Undo History (extend existing _orig snapshot)

Phase 3 (Ambitious):
  ├─ Zone-Based Auto-Switch
  ├─ Share Codes (extend existing bundle system)
  └─ Phantom Multi-Layout Preview (experimental)

Phase 4 (Research/Prototype):
  └─ Cinematic World Anchoring (opt-in experimental mode)
```

---

## Model Disagreements (User Should Weigh In)

| Idea | Claude | GPT | Gemini | Your Call? |
|------|--------|-----|--------|-----------|
| **Cinematic World Anchoring** | "Wrong execution layer" (Impact 5) | "Genuine cinematic vibes" (Impact 9) | "Holy grail if stable" (Impact 10) | Prototype or park? |
| **System-Grade Registration** | "Taint risk manageable" (Impact 8) | "Future-proofs" (Impact 9) | "Taint minefield" (Impact 5) | Risk worth taking? |
| **Precision Positioning** | "Already exists!" (Impact 3) | "Makes addon feel system-grade" (Impact 9) | "Redundant" (Impact 6) | Just add coordinate HUD? |
| **Undo/Redo** | "80% done, extend _orig" (Impact 8) | "Psychological safety" (Impact 8) | "Over-engineering" (Impact 4) | Full stack or just panic button? |
