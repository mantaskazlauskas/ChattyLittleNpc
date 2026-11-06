# Performance, Maintainability & Extensibility Roadmap

Work items from the codebase review on 2026-11-06 (v3.5.5). Each item stands on its own and can be picked up in a separate session. Tick the box when it is merged **and** has been tested in-game.

**Before starting any item:**
- Read the "Context" notes. Line numbers were correct on 2026-11-06 and may have drifted since, so search for the named function or pattern.
- Run the unit tests before and after: `python ChattyLittleNpc/tests/run_tests.py` (needs `pip install lupa`).
- Nothing counts as done until it has been tested in-game (`/reload`, then exercise the feature). See `.github/copilot-instructions.md`.

**Legend:** 🟢 small (≤1 session) · 🟡 medium (1–2 sessions) · 🔴 large (several sessions) · ⛓ depends on another item

---

## Phase 1 — Quick wins

### [ ] 1.1 Run unit tests in CI 🟢
- **Why:** `ChattyLittleNpc/tests/run_tests.py` runs 208 tests, but no workflow runs them, so a release can ship with failing tests.
- **Current state (2026-11-06):** the suite already fails: `FAILED (failures=8, errors=3, skipped=16)`.
- **Files:** `.github/workflows/release.yml` (or a new `.github/workflows/test.yml`), `ChattyLittleNpc/tests/run_tests.py`
- **Steps:**
  - [ ] Look at the 11 failing tests. For each, decide whether the test is stale or the code has a real bug, then fix the test or the code (or mark it skipped with a reason)
  - [ ] Add a job: set up Python 3.x, `pip install lupa`, `python ChattyLittleNpc/tests/run_tests.py`
  - [ ] Run it on push and pull requests; make the release job depend on it
- **Done when:** a deliberately broken test fails the workflow.

### [ ] 1.2 Add luacheck 🟢
- **Why:** it catches accidental globals, unused variables and shadowing, which are common sources of taint and bugs in WoW addons.
- **Steps:**
  - [ ] Add `.luacheckrc`: `std = "lua51"`, exclude `Libs/`, and list WoW globals as `read_globals` (or use a community WoW globals list)
  - [ ] Write accidental globals as `globals`: `ChattyLittleNpc`, the SavedVariables from the `.toc`, binding globals
  - [ ] Fix or explicitly allow the initial warnings
  - [ ] Add a luacheck step to CI (after 1.1)
- **Done when:** CI runs luacheck with zero warnings.

### [ ] 1.3 Remove leftover TEMP DIAGNOSTIC code 🟢
- **Why:** temporary diagnostics from the frame-position bug fixed in 3.5.3 (commit `6d20651`) still run on every login.
- **Files:** `ChattyLittleNpc/Init.lua` (ADDON_LOADED / PLAYER_LOGIN handler and `CLN:FlushSavedVarsDiag`), `ChattyLittleNpc/Core/Print.lua` (`ChattyLittleNpcSVDiag`)
- **Steps:**
  - [ ] `grep -rn "TEMP DIAG" ChattyLittleNpc` and remove each block (there were 4)
  - [ ] Remove `ChattyLittleNpcSVDiag` and `CLN:FlushSavedVarsDiag` if nothing else uses them
- **Verify in-game:** log in, move the conversation window, `/reload`, log out and back in. The position persists and no Lua errors appear.

### [x] 1.4 Stop building debug strings when debug mode is off: not needed
- **Checked 2026-11-06:** 28 of the 35 string-building `Logger:debug` calls in VoiceoverPlayer and EventHandler already sit inside `if CLN.db.profile.debugMode then`. The remaining 7 run once per item read or pause/resume, not per frame, and the 0.5s watcher's calls are already guarded. A `debugf` helper would save next to nothing, so the original plan below is kept only for reference.

<details><summary>Original plan</summary>

- **Already in place:** `Logger:debug` (`Utils/Logger.lua`) and `CLN.Utils:LogDebug` (`Utils/Utils.lua`) both return early unless `debugMode` is on, so DEBUG lines are never formatted or buffered when debug is off.
- **Remaining cost:** about 70 of the roughly 120 `Logger:debug(...)` calls build their message with `..` before the call, so the string is built even when it gets thrown away.
- **Steps:**
  - [ ] Add `Logger:debugf(fmt, ...)`, which checks `debugMode` first and only then calls `string.format`
  - [ ] Change the call sites on frequently run code paths (VoiceoverPlayer, EventHandler, ModelSceneHost) to use `debugf`, or wrap them in `if CLN.db.profile.debugMode then`
- **Verify in-game:** with debug on, DEBUG lines still show up in the Logs window and read the same as before.

</details>

### [ ] 1.5 Remove the duplicate repo config inside the addon folder 🟢
- **Why:**
  - `ChattyLittleNpc/.github/`, `ChattyLittleNpc/.vscode/` and `ChattyLittleNpc/.gitignore` duplicate the root copies.
  - The two `release.yml` files are identical apart from line endings (CRLF vs LF), so the nested copy can simply be removed.
- **Steps:**
  - [ ] `git rm` the nested copies (use a tracked removal, per repo rules)
  - [ ] Check that `pkgmeta.yaml` and `release.py` / `deploy.py` don't reference the nested paths

---

## Phase 2 — Playback event bus (core refactor)

The highest-value change. Playback logic currently calls the UI directly: `CLN.ReplayFrame` appears 47 times in `VoiceoverPlayer.lua`, and ReplayFrame or PlayButton 23 times in `EventHandler.lua`. The UI then polls for state on top of that. The message bus in `Core/Events.lua` (`SendMessage` / `RegisterMessage`) already exists but only about 9 places use it.

### [ ] 2.1 Define the playback messages 🟢
- **Steps:**
  - [ ] Document the message names and payloads in one place (for example the top of `VoiceoverPlayer.lua` or `types.lua`). Suggested set:
    - `CLN_PLAYBACK_STARTED (record)`
    - `CLN_PLAYBACK_STOPPED (record, reason)` where reason is `"finished" | "skipped" | "stopped" | "replaced"`
    - `CLN_PLAYBACK_PAUSED (record, kind)` where kind is `"user" | "nativeVO" | "suspended"`
    - `CLN_PLAYBACK_RESUMED (record)`
    - `CLN_QUEUE_CHANGED ()`
  - [ ] Send them from the matching `VoiceoverPlayer` state transitions (`SetPlaybackState`, `AdvanceQueue`, `ForceStopCurrentSound`, `NotifyQueueDirty`, `NotifyDisplayDirty`, …)
  - [ ] Add unit tests asserting the messages fire in the right order for play → pause → resume → finish
- **Done when:** the messages fire. Nothing listens to them yet.

### [ ] 2.2 Move the UI onto messages instead of direct calls 🔴 ⛓ 2.1
- **Steps** (one module per commit):
  - [ ] ReplayFrame (`src/ReplayFrame/init.lua`, `UI.lua`, `QueueList.lua`)
  - [ ] CompactBadge
  - [ ] PlayButton (quest-detail play/stop state)
  - [ ] QuestInfoPanel
  - [ ] Then remove the matching `CLN.ReplayFrame:*` / `CLN.PlayButton:*` calls from `VoiceoverPlayer.lua` and `EventHandler.lua`
- **Watch out:** some direct calls pass data back, such as `ShowRemainingSubtitles(..., callback)` in `StartTextContinuation`. Keep these as explicit calls or callbacks; not everything has to become a message.
- **Verify in-game:** quest accept, progress and complete; gossip; queueing several lines; pause and resume; skip; native-VO pause; compact mode; combat auto-collapse.

### [ ] 2.3 Remove polling loops made redundant by 2.2 ⛓ 2.2
- [ ] Quest-detail play/stop button: remove the 0.5s OnUpdate in `src/PlayButton.lua` (search `refreshElapsed`) and update on messages instead
- [ ] Playback watcher (`EventHandler:StartWatcher`, a 0.5s repeating timer): start it on `CLN_PLAYBACK_STARTED` and cancel it once nothing is playing or queued, instead of running all session
- [ ] Idle-fade tick (`src/ReplayFrame/UI.lua`, `HookScript("OnUpdate")` at 5 Hz): replace it with OnEnter/OnLeave plus one `C_Timer` that is restarted on playback or hover events
- **Verify in-game:** the idle fade still happens after `idleFadeDelay`, the countdown display still works, hovering wakes the frame, and the play/stop button reflects the state immediately.

### [ ] 2.4 Resolve queue entry file and duration once, at enqueue time 🟢
- **Why:** on every queue redraw, `src/ReplayFrame/init.lua` (around `GetDisplayEntries` processing) recomputes `GetHashes` → `GetPathToNonQuestFile` → `GetBestDuration` for each queued gossip line.
- **Steps:**
  - [ ] Store `resolvedPath` and `duration` / `hasPackDuration` on the queue entry when it is created
  - [ ] Have the display read the stored values, falling back to computing them if they're missing
- **Verify:** queued gossip entries still show correct durations.

---

## Phase 3 — Code structure

### [ ] 3.1 Cut down the defensive nil-guard chains 🟡
- **Why:**
  - There are about 270 `CLN.X and CLN.X.Y` chains. The `.toc` already fixes the load order, so most guarded modules always exist.
  - The guards turn real bugs into silent no-ops.
- **Steps:**
  - [ ] List the modules that are genuinely optional: client flavor (Classic vs Retail APIs), optional dependencies (DialogueUI, ElvUI, EditModeExpanded), anything loaded on demand
  - [ ] For the rest, replace `CLN.Foo and CLN.Foo.Bar and CLN.Foo:Bar()` with `CLN.Foo:Bar()`
  - [ ] Work file by file, one commit per file or group, so problems are easy to find with bisect
- **Watch out:** code that runs *during* file load (before `Init.lua`) really can see modules that haven't loaded yet. Only remove guards in code that runs at or after `OnInitialize`.

### [ ] 3.2 Merge the quest and non-quest playback pipelines 🔴 ⛓ 2.2 recommended first
- **Why:** `VoiceoverPlayer:PlayQuestSound` (~250 lines) and `PlayNonQuestSound` (~200 lines), plus `PlayLibraryFile`, likely duplicate the resolve → cooldown/dedupe → queue-or-override → play → UI-update flow.
- **Steps:**
  - [ ] Write down the shared steps and where each entry type differs
  - [ ] Create an entry-type handler table: `EntryTypes.quest`, `.gossip`, `.item`, `.library`, each providing `resolveFile`, `queuePolicy`, `title`, …
  - [ ] Build one `VoiceoverPlayer:Play(entry)` pipeline that uses the handlers; keep the old functions as thin wrappers
  - [ ] Add unit tests for each entry type's path through the pipeline
- **Unlocks:** new entry kinds (books, NPC emotes, …) become one handler each (see 5.2).

### [ ] 3.3 Split the largest files 🟡
Split along existing seams; don't change behavior. Candidates:
- [ ] `src/VoiceoverPlayer.lua` (1749): history, native-VO pause, text continuation and queue ops into separate files (after 3.2)
- [ ] `src/ReplayFrame/Renderers/ModelSceneHost.lua` (1635)
- [ ] `src/ReplayFrame/UI.lua` (1594)
- [ ] `src/Options.lua` (1356): one file per options section
- [ ] `src/ReplayFrame/LogsWindow.lua` (1249)
- Remember to update `ChattyLittleNpc.toc` load order for each new file.

### [ ] 3.4 Put saved-settings migrations in one place 🟡
- **Why:** `schemaVersion` is handled separately in `Main.lua` (`_MigrateSavedVars`, v1→v2) and in `src/ReplayFrame/EditMode/Persistence.lua`. The defaults also still carry legacy keys (for example `alwaysShowReplayFrame`).
- **Steps:**
  - [ ] Create `Core/Migrations.lua` with an ordered list `{ version = N, run = function(profile) ... end }`
  - [ ] Move the existing migrations into it, keeping each idempotent
  - [ ] Add migrations that delete clearly dead legacy keys
  - [ ] Unit-test every step, starting from a v0 profile fixture
- **Verify in-game:** start from an old SavedVariables backup and confirm nothing resets.

---

## Phase 4 — Load size

### [ ] 4.1 Move dev tooling into a load-on-demand companion addon 🟡
- **Why:** players load several thousand lines of tooling they never open.
- **Candidates (confirm each is really dev-only first):**
  - `src/ReplayFrame/DebugWindow.lua` (1478)
  - `src/PortraitTuner.lua`
  - `src/RaceModelManager.lua`
  - `src/ItemPropPicker.lua`
  - `src/ReplayFrame/Renderers/ModelScene/ProjectionVerifier.lua`
  - `src/ReplayFrame/Renderers/ModelScene/Diagnostics.lua`
- **Steps:**
  - [ ] Check which features these tools *write* data for, such as `itemPropOverrides`, `portraitShotTuning` and race assignments. The runtime readers of that data must stay in the main addon.
  - [ ] Create a `ChattyLittleNpc_Dev` folder with a `.toc` containing `## LoadOnDemand: 1` and `## Dependencies: ChattyLittleNpc`
  - [ ] Replace the entry points (slash commands, buttons) with `C_AddOns.LoadAddOn("ChattyLittleNpc_Dev")` followed by opening the tool
  - [ ] Decide how it ships: a separate CurseForge project, or bundled through `pkgmeta.yaml` `move-folders`
- **Verify in-game:** each tool still opens from its slash command or button; the addon memory figure drops (check with `/run UpdateAddOnMemoryUsage() print(GetAddOnMemoryUsage("ChattyLittleNpc"))` or an addon profiler).

---

## Phase 5 — Extensibility

### [ ] 5.1 Public API for other addons ⛓ 2.1
- **Steps:**
  - [ ] Create `ChattyLittleNpc.API` (new file `src/API.lua`) with a small, stable surface:
    - `IsPlaying()`
    - `GetCurrent()` (returns a read-only copy)
    - `PlayQuest(questId, phase)`
    - `Stop()`, `Pause()`, `Resume()`, `Skip()`
    - `RegisterCallback(event, fn)` / `UnregisterCallback`, wrapping the phase 2 messages
  - [ ] Version it with `API.version = 1`
  - [ ] Document it in `README.md`
  - [ ] Optional: move the built-in DialogueUI and ElvUI integration onto the API to prove it works

### [ ] 5.2 Make new entry types plug-in style ⛓ 3.2
- [ ] Document how to add a new entry type in the handler table: what to implement and how hash and file naming works

### [ ] 5.3 Document the model renderer interface 🟢
- **Why:** `ModelSceneHost` and `PlayerModelRenderer` are already two back ends, selected by `renderBackend` (`auto | scene | player`).
- **Steps:**
  - [ ] Write the shared interface (methods ReplayFrame calls, with expected arguments and return values) as `---@class ModelRenderer` in `types.lua`
  - [ ] Check that ReplayFrame and ModelHost only call methods in that interface; list and fix any calls that go around it

---

## Ideas parked (not yet evaluated)
- `src/ReplayFrame/LogsWindow.lua` replaces the global `print` while the Logs window is open and puts the saved original back on close. If another addon wraps `print` in the meantime, closing the window throws that wrapper away. `hooksecurefunc("print", ...)` would capture output without replacing the function.
- The release zip packs the whole `ChattyLittleNpc` folder, including `tests/`, `docs/` and `types.lua`. Exclude them in the `zip` step of `.github/workflows/release.yml`.
- Profile `/console scriptProfile 1` + `GetFunctionCPUUsage` sessions on a busy quest hub to find real hotspots before doing further perf work.
- Cap or prune growth of `NpcInfoDB`, `UnitInfoDB` and `VoicedNpcContributions` SavedVariables (`NpcMetadataCache` already prunes at 30 days; check the others).
