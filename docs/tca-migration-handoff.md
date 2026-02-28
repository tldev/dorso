# TCA Migration Handoff

## Snapshot

- Repo: `/Users/tjohnell/projects/dorso`
- Branch: `main`
- Working tree: uncommitted docs only (`docs/`)
- Existing baseline tests on `main`: `swift test` passes `230` tests, `0` failures.

## User Intent

- Migrate Dorso to TCA before implementing preferred/fallback mode.
- Design now with preferred mode in mind, but do not enable preferred/fallback runtime behavior during migration.
- Avoid writing characterization tests before contract alignment. Contract is now aligned.

## Source of Truth Contract

- Contract file: `/Users/tjohnell/projects/dorso/docs/tracking-behavior-contract.md`
- Use this as the authority for characterization tests and migration parity checks.

## Agreed Keep/Change Outcomes

- Keep:
- Manual mode only during migration.
- Source switching remains explicit user action.
- Missing calibration maps to `paused(noProfile)`.
- AirPods disconnect/reconnect behavior remains pause/resume.
- Camera hot-plug remains profile/display-key driven.
- `pauseOnTheGo` precedence unchanged.
- Calibration denial behavior unchanged.
- Camera selection restart behavior unchanged.
- No user-visible preferred/fallback behavior during migration.
- Preferred mode later should be additive in reducer logic.

- Change:
- Detector unavailability must be source-specific for both camera and AirPods.
- Screen-lock behavior simplified:
- Lock: if detector work is active, transition to `paused(screenLocked)`, stop active tracking work, and capture pre-lock state.
- Unlock: restore pre-lock state and resume detector work required by that restored state.

## Files the Next Agent Should Read First

- `/Users/tjohnell/projects/dorso/docs/tracking-behavior-contract.md`
- `/Users/tjohnell/projects/dorso/Sources/AppDelegate.swift`
- `/Users/tjohnell/projects/dorso/Sources/AppState.swift`
- `/Users/tjohnell/projects/dorso/Sources/PostureEngine.swift`
- `/Users/tjohnell/projects/dorso/Sources/PostureUIState.swift`
- `/Users/tjohnell/projects/dorso/Sources/AppDelegate+Persistence.swift`
- `/Users/tjohnell/projects/dorso/Sources/SettingsWindow.swift`
- `/Users/tjohnell/projects/dorso/Tests`

## Immediate Work Order

### 1) Add Characterization Test Harness (No Behavior Changes Yet)

- Goal: deterministic timeline tests for tracking orchestration behavior from contract.
- Suggest creating:
- `Tests/TrackingCharacterizationTests.swift`
- `Tests/TrackingScenarioHarness.swift`

- Harness should provide:
- Event type for external inputs (toggle, lock/unlock, camera connect/disconnect, AirPods connect/disconnect, permission result, calibration result, display change, settings changes).
- Observable outputs timeline for state transitions and side effects.
- Deterministic dependencies (clock and fake detector/permission/device clients).

- First scenarios to encode:
- Lock while monitoring resumes monitoring on unlock.
- Lock while calibrating restores calibrating flow on unlock.
- Lock while paused(non-screenLocked) restores the prior paused reason on unlock.
- Source-specific unavailability mapping for enable/calibration (`cameraDisconnected` for camera, `airPodsRemoved` for AirPods).
- AirPods disconnect during monitoring pauses; reconnect resumes.
- Camera selected disconnect with fallback camera and profile/no-profile split.
- Enable from disabled with no calibration.
- Calibration denied path.

### 2) Introduce TCA Skeleton in Parallel

- Add TCA package dependency and minimal tracking feature module boundary.
- Do not wire UI behavior changes yet.
- Proposed domain surface:
- `TrackingFeature.State`
- `TrackingFeature.Action`
- `TrackingFeature.Reducer`
- `TrackingFeature.Dependency` clients (detectors, permissions, display, lock, persistence, clock).

- State should already include preferred-mode-ready fields:
- `trackingMode`, `manualSource`, `preferredSource`, `autoReturnEnabled`
- But runtime must behave as manual-only for migration phase.

### 3) Parity Phase

- Run characterization scenarios against legacy orchestration and TCA domain logic.
- Keep behavior equivalent to contract + approved deviations.
- Use timeline assertions, not final-state-only assertions.

### 4) Cutover Phase

- Make `AppDelegate` an adapter that dispatches events to TCA store and executes effects.
- Keep settings/menu outputs derived from reducer state.
- Remove ad-hoc branching where TCA now owns transition logic.

## Acceptance Criteria for Migration PRs

- `swift test` remains green.
- Characterization tests are green.
- No user-visible preferred/fallback behavior introduced.
- Behavior changes only where contract says `Approved Deviations`.

## Migration End-State (Definition of Done)

TCA migration is complete only when all items below are true:

1. Unified reducer transition boundary (original goal):
   - `TrackingFeature` is the single transition authority for tracking behavior, matching the contract requirement to use one tracking reducer as the only transition boundary.
   - All tracking behavior decisions (state transitions and emitted effect intents) originate from reducer actions.
   - No direct tracking-state transitions (`appDelegate.state = ...` or equivalent) are allowed outside reducer-dispatch adapter commit paths.
2. `AppDelegate` adapter-only role:
   - `AppDelegate` only gathers event context, dispatches reducer actions, executes emitted intents, and commits state via adapter commit rules.
3. Contract parity proven:
   - `TrackingParityReplayTests`, `TrackingCharacterizationTests`, `TrackingFeatureTests`, and `AppDelegateTrackingIntegrationTests` are green.
4. Startup paths reducer-aligned:
   - `initialSetupFlow` and startup readiness/profile decisions are reducer-driven or isolated behind adapter seams with integration coverage.
5. Migration guardrails preserved:
   - Manual-mode behavior remains unchanged and there is no user-visible preferred/fallback runtime behavior.

### Iteration Gate (Required)

- Before starting a new chunk, evaluate all 5 end-state items.
- If all 5 are true:
  - stop iteration,
  - set `Recommended Next Steps` to `None`,
  - and treat migration as complete.
- If any item is false:
  - continue only on work that directly closes the unmet item(s).
- Do not execute discretionary cleanup or unrelated refactors.

## Guardrails

- Do not resurrect work from the previous `preferred-mode` branch.
- Do not redesign product behavior while building characterization harness.
- If behavior seems odd but marked `keep`, preserve it until explicit contract change.
- If uncertainty appears, update contract first, then tests, then implementation.

## Handoff Update Rule (Required)

- Every completed chunk must update two sections before handoff:
  - add a new `Completed Chunk N` entry under `Iteration Notes` with concrete code/test changes and exact validation commands/results.
  - rewrite `Recommended Next Steps` so it reflects only the remaining highest-priority work.
- Never leave completed work listed as a recommended next step.
- Keep recommended steps short, ordered, and executable by the next agent without re-discovery.
- If no steps remain, set `Recommended Next Steps` to `None` explicitly.

## Iteration Notes

### 2026-02-28 - In Progress (Codex)

- Started chunk: characterization harness + production transition alignment for approved deviations.
- Focus of this chunk:
  - Source-specific detector unavailability mapping (`cameraDisconnected` for camera, `airPodsRemoved` for AirPods).
  - Screen lock/unlock state restore semantics based on captured pre-lock state.
  - New deterministic timeline tests to exercise these transitions.

### 2026-02-28 - Completed Chunk 1 (Codex)

- Implemented pure transition helpers in `Sources/PostureEngine.swift`:
  - `unavailabilityPauseReason(for:)` and `unavailableState(for:)`.
  - `stateWhenEnabling(isCalibrated:detectorAvailable:trackingSource:)`.
  - `stateWhenScreenLocks(currentState:trackingSource:stateBeforeLock:)`.
  - `stateWhenScreenUnlocks(currentState:stateBeforeLock:)`.
- Wired `AppDelegate` to use these helpers so runtime behavior matches the new contract deviations:
  - Enable toggle now maps unavailability by source.
  - Detector start failures (state sync + calibration start) now map unavailability by source.
  - Screen lock now only transitions when detector work is active; unlock restores captured pre-lock state.
- Added characterization test harness and first timeline scenarios:
  - `Tests/TrackingScenarioHarness.swift`
  - `Tests/TrackingCharacterizationTests.swift`
- Extended transition unit coverage:
  - Updated `Tests/PostureEngineTransitionTests.swift` for source-specific enabling and lock/unlock transitions.
  - Updated `Tests/PostureEngineTests.swift` for new enabling signature.
- Validation:
  - `swift test --filter TrackingCharacterizationTests` passed (6 tests).
  - `swift test --filter PostureEngineTransitionTests` passed (47 tests).
  - Full suite `swift test` passed (244 tests, 0 failures).

### 2026-02-28 - In Progress (Chunk 2, Codex)

- Added pure transition modeling for:
  - AirPods connection-change handling (disconnect pause / reconnect resume intent).
  - Camera connect/disconnect hot-plug outcomes (UI-only sync, fallback switch, monitor/no-profile/disconnected state outcomes).
- Extending scenario harness timeline outputs to include side-effect intents:
  - start-monitoring requests,
  - fallback-camera-switch requests,
  - UI-sync-only requests.

### 2026-02-28 - Completed Chunk 2 (Codex)

- Implemented additional pure transition helpers in `Sources/PostureEngine.swift`:
  - `stateWhenAirPodsConnectionChanges(currentState:trackingSource:isConnected:)`
  - `stateWhenCameraConnects(currentState:trackingSource:hasMatchingProfileForConnectedCamera:)`
  - `stateWhenCameraDisconnects(currentState:trackingSource:disconnectedCameraIsSelected:hasFallbackCamera:fallbackMatchesProfile:)`
- Added explicit result types for hot-plug/connection outcomes (`AirPodsConnectionTransitionResult`, `CameraConnectedTransitionResult`, `CameraDisconnectedTransitionResult`).
- Rewired `AppDelegate` handlers to use these helpers:
  - `handleConnectionStateChange(_:)`
  - `handleCameraConnected(_:)`
  - `handleCameraDisconnected(_:)`
- Expanded deterministic harness semantics in `Tests/TrackingScenarioHarness.swift`:
  - New events for AirPods connection changes and camera connect/disconnect.
  - Timeline now captures side-effect intents (`startMonitoringRequested`, `fallbackSwitchRequested`, `uiSyncRequested`).
- Added characterization timelines in `Tests/TrackingCharacterizationTests.swift`:
  - AirPods disconnect -> pause(`airPodsRemoved`) -> reconnect resume.
  - Camera selected-disconnect fallback split:
    - fallback+profile => monitoring + switch/restart intents.
    - fallback+no-profile => `paused(noProfile)` + switch intent.
    - no fallback => `paused(cameraDisconnected)`.
    - non-selected disconnect => no state change + UI-sync intent.
- Extended unit coverage in `Tests/PostureEngineTransitionTests.swift` for all new helper transitions.
- Validation:
  - `swift test --filter PostureEngineTransitionTests` passed (56 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (11 tests).
  - Full suite `swift test` passed (258 tests, 0 failures).

### 2026-02-28 - Completed Chunk 3 (Codex)

- Added TCA dependency to package manifest:
  - `Package.swift` now includes `swift-composable-architecture`.
  - `DorsoCore` and `DorsoTests` targets now depend on `ComposableArchitecture`.
- Introduced minimal tracking reducer boundary in `Sources/TrackingFeature.swift`:
  - `TrackingFeature.State` with policy-ready fields:
    - `trackingMode`
    - `manualSource`
    - `preferredSource`
    - `autoReturnEnabled`
  - Runtime fields:
    - `appState`
    - per-source readiness (`permission`, `connection`, `calibration`, `availability`)
    - `stateBeforeLock`
  - `TrackingFeature.Action` event surface for:
    - toggle enable
    - lock/unlock
    - AirPods connection changes
    - camera connect/disconnect
    - calibration start failure
    - settings/policy field mutations
  - Reducer currently remains manual-mode runtime and reuses `PostureEngine` pure transition helpers (no UI wiring/cutover yet).
- Added dependency-client scaffolding (unimplemented defaults) in `Sources/TrackingFeature.swift`:
  - detectors, permissions, display, screen lock, persistence, clock.
- Added reducer-level tests in `Tests/TrackingFeatureTests.swift`:
  - enable toggle source-specific unavailable mapping for AirPods.
  - lock/unlock state restoration for monitoring.
  - camera disconnect fallback-no-profile path.
  - AirPods reconnect resume path.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (4 tests).
  - Full suite `swift test` passed (262 tests, 0 failures).

### 2026-02-28 - Completed Chunk 4 (Codex, Final Before Handoff)

- Started AppDelegate adapter cutover by dispatching key runtime events to `TrackingFeature` store.
- Added `TrackingFeature.Action.syncRuntimeContext` to keep reducer state aligned with legacy runtime context:
  - `appState`
  - `manualSource`
  - `stateBeforeLock`
  - camera/AirPods readiness snapshots
- Added AppDelegate store adapter helpers:
  - readiness snapshot builder per source
  - runtime-context sync helper
  - `sendTrackingAction(_:)` bridge to dispatch actions and apply resulting state back to legacy runtime
  - restart-monitoring gate for actions that must re-enter monitoring via `startMonitoring()`
- Routed these AppDelegate paths through reducer dispatch:
  - enable/disable toggle (`toggleEnabled`)
  - AirPods connection changes (`handleConnectionStateChange`)
  - calibration detector start failure (`startDetectorAndShowCalibration` failure path)
  - screen lock/unlock (`handleScreenLocked` / `handleScreenUnlocked`)
- Kept camera hot-plug side-effect orchestration in AppDelegate for now (still using pure transition helpers), so this is a partial adapter stage, not full cutover.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (4 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (11 tests).
  - Full suite `swift test` passed (262 tests, 0 failures).

### 2026-02-28 - Completed Chunk 5 (Codex)

- Completed AppDelegate adapter cutover for camera hot-plug by routing handlers through reducer actions:
  - `handleCameraConnected(_:)` now dispatches `TrackingFeature.Action.cameraConnected`.
  - `handleCameraDisconnected(_:)` now dispatches `TrackingFeature.Action.cameraDisconnected`.
- Kept side effects in `AppDelegate` per migration plan:
  - camera switch to fallback,
  - calibration hydration from matching profile,
  - restart via `startMonitoring()`,
  - UI sync for non-selected disconnects.
- Added `applyStateTransition` control to `sendTrackingAction(_:)` so hot-plug handlers can dispatch into reducer first, then apply side effects before committing runtime state where needed.
- Expanded reducer-level coverage in `Tests/TrackingFeatureTests.swift`:
  - camera connect with matching profile from `paused(cameraDisconnected)` -> `monitoring`,
  - camera disconnect of non-selected camera leaves state unchanged.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (6 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (11 tests).
  - Full suite `swift test` passed (264 tests, 0 failures).

### 2026-02-28 - Completed Chunk 6 (Codex)

- Moved calibration permission-denied transition authority into reducer:
  - Added `TrackingFeature.Action.calibrationAuthorizationDenied`.
  - `TrackingFeature` now resolves denied outcome from active-source readiness:
    - calibrated -> `.monitoring`
    - not calibrated -> `.paused(.noProfile)`
  - `AppDelegate.startCalibration()` denied path now dispatches reducer action via `sendTrackingAction`.
- Added pure helper in `PostureEngine`:
  - `stateWhenCalibrationAuthorizationDenied(isCalibrated:)`
- Expanded characterization harness/events:
  - Added `.calibrationAuthorizationDenied` event in `TrackingScenarioHarness`.
- Expanded high-risk scenario coverage requested in handoff:
  - camera connect from `.paused(.cameraDisconnected)` without matching profile -> `.paused(.noProfile)`.
  - unlock from `.paused(.screenLocked)` with no captured `stateBeforeLock` remains screen-locked.
  - calibration authorization denied timeline (calibrated vs uncalibrated outcomes).
- Added reducer and transition tests:
  - `TrackingFeatureTests`: calibration authorization denied outcomes for calibrated and uncalibrated sources.
  - `PostureEngineTransitionTests`: calibration authorization denied helper behavior.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (8 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (14 tests).
  - `swift test --filter PostureEngineTransitionTests` passed (58 tests).
  - Full suite `swift test` passed (271 tests, 0 failures).

### 2026-02-28 - Completed Chunk 7 (Codex)

- Added first reducer-effect intent bridge for camera hot-plug flows:
  - Introduced `TrackingFeature.EffectIntent` with:
    - `.startMonitoring`
    - `.switchCamera(.matchingProfile | .fallback)`
    - `.syncUI`
  - Reducer now emits intents for camera actions:
    - `cameraConnected`: emits switch+start when matching profile reconnect should recover monitoring; emits syncUI when no state transition occurs.
    - `cameraDisconnected`: emits syncUI/switch/start based on disconnect result action.
- Updated AppDelegate adapter bridge:
  - `sendTrackingAction` now returns reducer-emitted `effectIntents` alongside state snapshots.
  - Added thin intent executor in `AppDelegate` to map intents to existing imperative calls:
    - `startMonitoring()`
    - `cameraDetector.switchCamera(...)`
    - `syncUIToState()`
  - Kept profile-derived calibration hydration in AppDelegate context while applying switch intents.
- Camera hot-plug handlers now execute reducer intents rather than re-deriving side-effect decisions from local branching.
- Extended reducer tests to assert effect-intent emission:
  - fallback disconnect emits `switchCamera(.fallback)`
  - matching-profile reconnect emits `switchCamera(.matchingProfile)` + `startMonitoring`
  - non-selected disconnect emits `syncUI`
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (8 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (14 tests).
  - Full suite `swift test` passed (271 tests, 0 failures).

### 2026-02-28 - Completed Chunk 8 (Codex)

- Expanded reducer-effect intent usage to existing restart-monitoring paths:
  - `toggleEnabled` now emits `.startMonitoring` when enabling resolves to `.monitoring`.
  - `airPodsConnectionChanged` emits `.startMonitoring` when reconnect requires monitoring restart.
  - `screenUnlocked` emits `.startMonitoring` when restoring prior `.monitoring`.
- Removed AppDelegate restart gate branching:
  - Deleted `shouldRestartMonitoring(...)`.
  - `sendTrackingAction(...)` now executes reducer-emitted intents for standard dispatched paths (`applyStateTransition: true`) and only applies direct state assignment when no start-monitoring intent was requested.
  - This preserves legacy fallback behavior where `startMonitoring()` can still produce a different runtime state than the reducer’s optimistic `.monitoring` target.
- Kept camera hot-plug intent execution in specialized adapter path (`applyStateTransition: false`) so switch-camera intents continue to use event-local context (matching/fallback camera/profile).
- Expanded reducer tests:
  - Added `toggleEnabled` calibrated+available path asserting `.startMonitoring` intent.
  - Updated screen unlock + AirPods reconnect tests to assert emitted `.startMonitoring` intents.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (9 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (14 tests).
  - Full suite `swift test` passed (272 tests, 0 failures).

### 2026-02-28 - Completed Chunk 9 (Codex)

- Moved display-configuration transition authority into reducer:
  - Added `TrackingFeature.Action.displayConfigurationChanged(...)` with explicit readiness/context inputs.
  - Added pure `PostureEngine.stateWhenDisplayConfigurationChanges(...)` returning:
    - `newState`
    - `shouldSwitchToProfileCamera`
    - `shouldStartMonitoring`
  - Reducer now emits intents for display path:
    - `.switchCamera(.matchingProfile)` when profile camera should be selected,
    - `.startMonitoring` when display/profile conditions require monitor restart.
- Moved settings camera-selection restart semantics into reducer:
  - Added `TrackingFeature.Action.cameraSelectionChanged`.
  - Added pure `PostureEngine.stateWhenCameraSelectionChanges(...)`.
  - Reducer emits `.switchCamera(.selectedCamera)` and transitions to `.paused(.noProfile)` for camera source.
- Extended AppDelegate adapter execution for new intents/actions:
  - Added `.selectedCamera` handling in `executeTrackingEffectIntents`.
  - `restartCamera()` now dispatches `.cameraSelectionChanged` and executes reducer intents instead of direct state mutation.
  - `handleDisplayConfigurationChange()` now dispatches `.displayConfigurationChanged(...)` and executes reducer intents using display-profile context.
- Expanded deterministic scenario coverage:
  - Display change with matching profile requests switch + monitoring restart.
  - Camera selection change pauses `noProfile` + requests selected-camera switch.
- Expanded reducer/engine tests:
  - `TrackingFeatureTests` now cover display and camera-selection actions/intents.
  - `PostureEngineTransitionTests` now cover display and camera-selection pure transitions.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (13 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (16 tests).
  - `swift test --filter PostureEngineTransitionTests` passed (63 tests).
  - Full suite `swift test` passed (283 tests, 0 failures).

### 2026-02-28 - Completed Chunk 10 (Codex)

- Moved manual source-switch transition authority into reducer boundary:
  - Added pure transition helper in `Sources/PostureEngine.swift`:
    - `stateWhenSwitchingTrackingSource(currentState:currentSource:newSource:isNewSourceCalibrated:)`
    - `SourceSwitchTransitionResult`
  - Added reducer action in `Sources/TrackingFeature.swift`:
    - `TrackingFeature.Action.switchTrackingSource(TrackingSource)`
  - Added reducer effect intents for source-switch side effects:
    - `.stopDetector(TrackingSource)`
    - `.setTrackingSource(TrackingSource)`
    - `.persistTrackingSource`
    - existing `.startMonitoring` when calibrated.
- Updated `AppDelegate` adapter to execute new intents:
  - `switchTrackingSource(to:)` now dispatches `sendTrackingAction(.switchTrackingSource(source))`.
  - `executeTrackingEffectIntents(...)` now handles stop-detector, source assignment, and persistence intents.
- Expanded characterization/reducer/transition coverage:
  - `Tests/TrackingScenarioHarness.swift`:
    - new `.switchTrackingSource(...)` event.
    - timeline outputs now include `trackingSource`, `stopDetectorRequested`, `persistSourceRequested`.
  - `Tests/TrackingCharacterizationTests.swift`:
    - source switch to uncalibrated source -> `paused(noProfile)` + stop/persist intents.
    - source switch to calibrated source -> `monitoring` + stop/persist/start intents.
  - `Tests/TrackingFeatureTests.swift`:
    - calibrated / uncalibrated / same-source reducer action coverage for source switch.
  - `Tests/PostureEngineTransitionTests.swift`:
    - pure transition coverage for all source-switch branches.
- Validation:
  - `swift test --filter PostureEngineTransitionTests` passed (66 tests).
  - `swift test --filter TrackingFeatureTests` passed (16 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (18 tests).
  - Full suite `swift test` passed (291 tests, 0 failures).

### 2026-02-28 - Completed Chunk 11 (Codex)

- Moved calibration lifecycle transitions into reducer action/intents:
  - Added `TrackingFeature.Action` cases:
    - `calibrationAuthorizationGranted`
    - `calibrationCancelled`
    - `calibrationCompleted`
  - Added `TrackingFeature.EffectIntent.resetMonitoringState`.
  - Reducer behavior:
    - authorization granted -> `calibrating`
    - cancel -> `monitoring` + `startMonitoring` intent when calibrated, else `paused(noProfile)`
    - completion -> `monitoring` + `resetMonitoringState` + `startMonitoring` intents
- Added pure transition helpers in `Sources/PostureEngine.swift`:
  - `stateWhenCalibrationAuthorizationGranted()`
  - `stateWhenCalibrationCancels(isCalibrated:)`
  - `stateWhenCalibrationCompletes()`
- Updated `AppDelegate` calibration flow to use reducer-dispatched transitions:
  - `startCalibration()` authorized path now dispatches `.calibrationAuthorizationGranted` before detector/window flow.
  - `cancelCalibration()` now dispatches `.calibrationCancelled`.
  - `finishCalibration(...)` now dispatches `.calibrationCompleted`.
  - `executeTrackingEffectIntents(...)` now handles `.resetMonitoringState`.
- Expanded timeline and reducer coverage for calibration lifecycle:
  - `Tests/TrackingScenarioHarness.swift`:
    - new events for authorization granted, cancel, completion
    - new timeline flag `resetMonitoringRequested`
  - `Tests/TrackingCharacterizationTests.swift`:
    - calibration authorization-granted timeline
    - calibration cancel (calibrated vs uncalibrated)
    - calibration completion reset/restart timeline
  - `Tests/TrackingFeatureTests.swift`:
    - reducer tests for all three calibration lifecycle actions/intents
  - `Tests/PostureEngineTransitionTests.swift`:
    - pure transition tests for calibration grant/cancel/complete helpers
- Validation:
  - `swift test --filter PostureEngineTransitionTests` passed (70 tests).
  - `swift test --filter TrackingFeatureTests` passed (20 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (22 tests).
  - Full suite `swift test` passed (303 tests, 0 failures).

### 2026-02-28 - Completed Chunk 12 (Codex)

- Moved `startMonitoring()` state resolution into reducer action/intents:
  - Added `TrackingFeature.Action.startMonitoringRequested(isMarketingMode:)`.
  - Added `TrackingFeature.EffectIntent.beginMonitoringSession`.
  - Reducer now derives monitoring-attempt outcome from readiness facts:
    - marketing mode -> `monitoring` (no begin-session intent)
    - missing calibration -> `paused(noProfile)`
    - AirPods disconnected -> `paused(airPodsRemoved)` + begin-session intent
    - normal path -> `monitoring` + begin-session intent
- Added pure helper in `Sources/PostureEngine.swift`:
  - `stateWhenMonitoringStarts(isMarketingMode:trackingSource:isCalibrated:isConnected:)`
  - `MonitoringStartTransitionResult`
- Updated `AppDelegate.startMonitoring()` to use reducer dispatch:
  - now sends `.startMonitoringRequested(...)` with `applyStateTransition: false`,
  - executes reducer intents,
  - commits resulting state from reducer output.
- Kept detector `beginMonitoring(...)` imperative in `AppDelegate` as planned:
  - intent executor now handles `.beginMonitoringSession`,
  - preserves AirPods disconnected logging behavior.
- Expanded tests for monitoring-attempt outcomes:
  - `Tests/PostureEngineTransitionTests.swift`: pure transition coverage for all monitoring-start branches.
  - `Tests/TrackingFeatureTests.swift`: reducer action/intents coverage for monitoring-start outcomes.
  - `Tests/TrackingScenarioHarness.swift`: new `startMonitoringRequested` event and `beginMonitoringRequested` timeline flag.
  - `Tests/TrackingCharacterizationTests.swift`: timeline scenarios for no-calibration, AirPods-disconnected, normal, and marketing-mode monitoring starts.
- Validation:
  - `swift test --filter PostureEngineTransitionTests` passed (74 tests).
  - `swift test --filter TrackingFeatureTests` passed (24 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (26 tests).
  - Full suite `swift test` passed (315 tests, 0 failures).

### 2026-02-28 - Completed Chunk 13 (Codex)

- Moved runtime detector start-failure transition authority into reducer dispatch:
  - Added `TrackingFeature.Action.runtimeDetectorStartFailed`.
  - Reducer now maps this action to source-specific unavailability via `PostureEngine.unavailableState(for:)`.
  - `AppDelegate.syncDetectorToState()` start-failure callback now dispatches `.runtimeDetectorStartFailed` instead of direct `state` assignment.
- Consolidated deferred adapter state commits for `applyStateTransition: false` paths:
  - Added `AppDelegate.applyTrackingTransition(...)` to centralize intent execution + state commit logic.
  - Applied this helper to:
    - `startMonitoring()`
    - `restartCamera()`
    - `handleCameraConnected(_:)`
    - `handleCameraDisconnected(_:)`
    - `handleDisplayConfigurationChange()`
  - Helper now mirrors the reducer-dispatch path guard: when `.startMonitoring` intent is emitted, do not force-assign optimistic reducer state over runtime `startMonitoring()` outcomes.
- Expanded parity coverage for runtime detector start failures outside calibration:
  - `Tests/TrackingFeatureTests.swift`:
    - camera runtime start failure -> `paused(cameraDisconnected)`
    - AirPods runtime start failure -> `paused(airPodsRemoved)`
  - `Tests/TrackingScenarioHarness.swift`:
    - new `.runtimeDetectorStartFailed` event.
  - `Tests/TrackingCharacterizationTests.swift`:
    - timeline scenario for source-specific runtime start-failure mapping (camera vs AirPods).
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (26 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (27 tests).
  - Full suite `swift test` passed (318 tests, 0 failures).

### 2026-02-28 - Completed Chunk 14 (Codex)

- Added explicit adapter-level transition-commit rules as pure logic:
  - New file `Sources/TrackingAdapterTransition.swift`.
  - Introduced:
    - `TrackingAdapterTransition.shouldCommitReducerState(effectIntents:)`
    - `TrackingAdapterTransition.committedAppState(currentStateAfterEffects:reducerState:effectIntents:)`
  - Rule is now explicit and testable:
    - if `.startMonitoring` intent is present, preserve runtime post-effect state,
    - otherwise commit reducer state.
- Wired `AppDelegate` deferred transition path to use shared adapter rule:
  - `applyTrackingTransition(...)` now delegates commit decision to `TrackingAdapterTransition`.
  - Preserves existing effect ordering (execute intents first, then commit state).
- Added adapter-focused tests to protect deferred ordering behavior:
  - New file `Tests/TrackingAdapterTransitionTests.swift` covering:
    - camera reconnect flow with `.startMonitoring` intent preserves runtime fallback state,
    - display flow with `.startMonitoring` intent preserves runtime fallback state,
    - non-start-monitoring intents commit reducer state.
- Validation:
  - `swift test --filter TrackingAdapterTransitionTests` passed (3 tests).
  - `swift test --filter TrackingFeatureTests` passed (26 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (27 tests).
  - Full suite `swift test` passed (321 tests, 0 failures).

### 2026-02-28 - Completed Chunk 15 (Codex)

- Continued calibration-side reducer cutover for permission/remediation intents (no behavior change):
  - Added reducer effect intents in `Sources/TrackingFeature.swift`:
    - `.showCalibrationPermissionDeniedAlert`
    - `.openPrivacySettings`
    - `.showCameraCalibrationRetryAlert(message:)`
  - Added reducer action:
    - `.calibrationOpenSettingsRequested`
  - Updated reducer transitions:
    - `.calibrationAuthorizationDenied` now emits permission alert intent.
    - `.calibrationOpenSettingsRequested` emits open-settings intent.
    - `.calibrationStartFailed(errorMessage:)` emits camera retry alert intent only for camera source, while preserving source-specific unavailable pause state.
- Moved remaining imperative alert branching out of calibration flow entry points in `Sources/AppDelegate.swift`:
  - `startCalibration()` denied path now only dispatches reducer action.
  - `startDetectorAndShowCalibration()` failure path now only dispatches reducer action with optional error message.
  - Intent execution now owns:
    - permission denied alert presentation,
    - open privacy settings action dispatch/execution,
    - camera retry alert + retry action.
- Expanded reducer tests in `Tests/TrackingFeatureTests.swift`:
  - calibration authorization denied emits permission alert intent (calibrated and uncalibrated outcomes),
  - open-settings request emits open-settings intent,
  - calibration start failure emits retry alert for camera only, with source-specific unavailable state for both sources.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (29 tests).
  - Full suite `swift test` passed (324 tests, 0 failures).

### 2026-02-28 - Completed Chunk 16 (Codex)

- Added explicit legacy-vs-reducer parity replay harness and matrix tests:
  - New reducer-side deterministic harness: `Tests/TrackingReducerScenarioHarness.swift`.
  - Harness dispatches reducer actions with runtime-context sync semantics and records timeline snapshots aligned to legacy harness fields:
    - state, trackingSource, stateBeforeLock,
    - detector-run expectation,
    - side-effect intent flags (`startMonitoring`, `beginMonitoring`, `stopDetector`, `persist`, `reset`, camera switch intents, UI sync).
- Added contract-oriented replay matrix in `Tests/TrackingParityReplayTests.swift`:
  - Replays identical event timelines through both:
    - `TrackingScenarioHarness` (legacy transition modeling),
    - `TrackingReducerScenarioHarness` (reducer transition modeling).
  - Asserts full snapshot timeline equality (not just final state) for core contract scenarios across:
    - enable/disable,
    - calibration grant/deny/cancel/complete,
    - runtime/calibration detector failures,
    - lock/unlock restore semantics,
    - AirPods reconnect/disconnect,
    - camera hot-plug branches,
    - display-change profile recovery,
    - camera selection change,
    - manual source-switch branches.
- Validation:
  - `swift test --filter TrackingParityReplayTests` passed (1 test).
  - `swift test --filter TrackingFeatureTests` passed (29 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (27 tests).
  - Full suite `swift test` passed (325 tests, 0 failures).

### 2026-02-28 - Completed Chunk 17 (Codex)

- Completed remaining calibration retry remediation modeling through reducer action/intents:
  - Added `TrackingFeature.Action.calibrationRetryRequested`.
  - Added `TrackingFeature.EffectIntent.retryCalibration`.
  - Reducer now emits retry intent instead of relying on direct callback wiring.
- Updated AppDelegate calibration retry path:
  - `showCameraCalibrationRetryAlert(...)` now dispatches `.calibrationRetryRequested` when user taps retry.
  - Intent executor now handles `.retryCalibration` by invoking `startCalibration()`.
  - Preserves existing user-visible behavior while keeping transition authority in reducer boundary.
- Expanded reducer tests:
  - `TrackingFeatureTests` now includes `testCalibrationRetryRequestedEmitsRetryCalibrationIntent`.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (30 tests).
  - `swift test --filter TrackingParityReplayTests` passed (1 test).
  - `swift test --filter TrackingCharacterizationTests` passed (27 tests).
  - Full suite `swift test` passed (326 tests, 0 failures).

### 2026-02-28 - Completed Chunk 18 (Codex)

- Added AppDelegate adapter integration seams for deterministic end-to-end dispatch testing:
  - `Sources/AppDelegate.swift` now records intent execution via `trackingEffectIntentObserver`.
  - Extracted reusable transition dispatch helpers:
    - `applyCameraConnectedTransition(...)`
    - `applyDisplayConfigurationTransition(...)`
  - Production handlers (`handleCameraConnected`, `handleDisplayConfigurationChange`) now call those helpers to keep behavior identical while enabling test reuse.
  - Added test entry points:
    - `dispatchCameraConnectedTransitionForTesting(...)`
    - `dispatchDisplayConfigurationTransitionForTesting(...)`
- Added AppDelegate-level integration coverage in `Tests/AppDelegateTrackingIntegrationTests.swift`:
  - Camera hot-plug flow test verifies reducer-intent execution ordering (`switchCamera(.matchingProfile)` before `startMonitoring`) and final committed runtime state.
  - Display-change flow test verifies the same ordering/commit behavior under reducer dispatch.
  - Both tests exercise real `sendTrackingAction` + `applyTrackingTransition` paths and assert runtime fallback commit behavior (`.paused(.noProfile)`), not just pure helper output.
- Validation:
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (2 tests).
  - `swift test --filter TrackingFeatureTests` passed (30 tests).
  - `swift test --filter TrackingParityReplayTests` passed (1 test).
  - Full suite `swift test` passed (328 tests, 0 failures).

### 2026-02-28 - Completed Chunk 19 (Codex)

- Added local migration acceptance script:
  - `scripts/ci-tracking-migration-acceptance.sh`
  - Runs both required tracking migration signals in sequence for local/pre-push validation.
- Deferred repository CI wiring for these checks until later in TCA transition (per migration sequencing preference).
- Validation:
  - `./scripts/ci-tracking-migration-acceptance.sh` passed.
  - `swift test` passed (328 tests, 0 failures).

### 2026-02-28 - Completed Chunk 20 (Codex)

- Expanded AppDelegate adapter path extraction for camera disconnect transitions:
  - Added `applyCameraDisconnectedTransition(...)` in `Sources/AppDelegate.swift`.
  - `handleCameraDisconnected(_:)` now routes through that helper, matching the existing connected/display helper structure.
  - Added test dispatch entry point:
    - `dispatchCameraDisconnectedTransitionForTesting(...)`
- Broadened AppDelegate-level integration coverage in `Tests/AppDelegateTrackingIntegrationTests.swift`:
  - camera disconnect selected + fallback with matching profile intent path:
    - asserts effect order `.switchCamera(.fallback)` then `.startMonitoring`
    - asserts runtime fallback commit behavior remains `.paused(.noProfile)`.
  - camera disconnect selected + fallback without matching profile:
    - asserts `.switchCamera(.fallback)` intent without restart.
  - camera disconnect selected + no fallback:
    - asserts `.paused(.cameraDisconnected)` with no emitted/executed intents.
  - display-change `pauseOnTheGo` precedence:
    - asserts `.paused(.onTheGo)` and suppresses camera recovery intents.
- Validation:
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (6 tests).
  - `swift test --filter TrackingParityReplayTests` passed (1 test).
  - Full suite `swift test` passed (332 tests, 0 failures).

### 2026-02-28 - Completed Chunk 21 (Codex)

- Removed migration acceptance script per request to avoid premature CI scaffolding:
  - deleted `scripts/ci-tracking-migration-acceptance.sh`.
- Continued AppDelegate thinning for event-local context assembly:
  - Added `makeCameraDisconnectContext(for:)` and `CameraDisconnectContext`.
  - Added `makeDisplayConfigurationContext()` and `DisplayConfigurationContext`.
  - `handleCameraDisconnected(_:)` and `handleDisplayConfigurationChange()` now consume these helpers, keeping reducer dispatch behavior unchanged.
- Broadened AppDelegate integration coverage for remaining high-risk branches in `Tests/AppDelegateTrackingIntegrationTests.swift`:
  - non-selected camera disconnect emits `.syncUI` and preserves state.
  - display-change no-camera branch -> `.paused(.cameraDisconnected)` with no recovery intents.
  - display-change no-profile branch -> `.paused(.noProfile)` with no recovery intents.
- Validation:
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (9 tests).
  - `swift test --filter TrackingParityReplayTests` passed (1 test).
  - Full suite `swift test` passed (335 tests, 0 failures).

### 2026-02-28 - Completed Chunk 22 (Codex)

- Added AppDelegate screen-lock test dispatch seams:
  - `dispatchScreenLockedTransitionForTesting()`
  - `dispatchScreenUnlockedTransitionForTesting()`
- Broadened AppDelegate integration coverage in `Tests/AppDelegateTrackingIntegrationTests.swift`:
  - camera connect from `.paused(.cameraDisconnected)` without matching profile:
    - asserts no recovery intents and transition to `.paused(.noProfile)`.
  - screen lock/unlock monitoring restore path:
    - asserts unlock emits `.startMonitoring`,
    - asserts runtime exits `.paused(.screenLocked)` after unlock effect execution.
- Validation:
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (11 tests).
  - `swift test --filter TrackingParityReplayTests` passed (1 test).
  - Full suite `swift test` passed (337 tests, 0 failures).

### 2026-02-28 - Completed Chunk 23 (Codex)

- Continued AppDelegate thinning for remaining handler assembly paths:
  - Added `CameraConnectedContext` + `makeCameraConnectedContext(for:)` and moved camera-connected profile lookup/decision prep out of handler body.
  - Added `applyCameraSelectionTransition()` and updated `restartCamera()` to call this helper.
  - Added test dispatch helpers:
    - `dispatchCameraSelectionTransitionForTesting()`
    - `dispatchSwitchTrackingSourceTransitionForTesting(_:)`
- Expanded AppDelegate integration coverage for camera-selection and manual source-switch paths:
  - camera selection change emits `.switchCamera(.selectedCamera)` and commits `.paused(.noProfile)`.
  - manual source switch to uncalibrated source emits/executes:
    - `.stopDetector(previousSource)`, `.setTrackingSource(newSource)`, `.persistTrackingSource` (no restart).
  - manual source switch to calibrated source emits/executes same prefix plus `.startMonitoring`, with runtime ending in monitoring for camera path.
- Validation:
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (14 tests).
  - `swift test --filter TrackingParityReplayTests` passed (1 test).
  - Full suite `swift test` passed (340 tests, 0 failures).

### 2026-02-28 - Completed Chunk 24 (Codex)

- Extended AppDelegate helper/adapter seams:
  - Added testing dispatch entry points for calibration/source/camera-selection paths:
    - `dispatchCameraSelectionTransitionForTesting()`
    - `dispatchSwitchTrackingSourceTransitionForTesting(_:)`
  - (Alongside previously-added screen lock helpers) this enables direct AppDelegate dispatch assertions for high-risk transition paths.
- Expanded AppDelegate integration coverage for calibration lifecycle entry points in `Tests/AppDelegateTrackingIntegrationTests.swift`:
  - `cancelCalibration()` calibrated branch:
    - asserts restart intent and final monitoring state.
  - `cancelCalibration()` uncalibrated branch:
    - asserts no restart intent and final `.paused(.noProfile)`.
  - `finishCalibration(values:)` completion path:
    - asserts effect ordering prefix `.resetMonitoringState`, `.startMonitoring`,
    - asserts final monitoring state.
- Validation:
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (17 tests).
  - `swift test --filter TrackingParityReplayTests` passed (1 test).
  - Full suite `swift test` passed (343 tests, 0 failures).

### 2026-02-28 - Completed Chunk 25 (Codex)

- Added explicit AppDelegate remediation seams for alert/open-settings/retry execution so alert-driven branches are adapter-testable without modal UI:
  - `calibrationPermissionDeniedAlertDecision`
  - `cameraCalibrationRetryAlertDecision`
  - `openPrivacySettingsHandler`
  - `retryCalibrationHandler`
- Added deterministic detector-sync seam for integration tests that need to avoid hardware starts while validating reducer/adapter behavior:
  - `syncDetectorToStateOverride`
- Added AppDelegate dispatch test entry points for remediation transitions:
  - `dispatchCalibrationAuthorizationDeniedTransitionForTesting()`
  - `dispatchCalibrationStartFailedTransitionForTesting(errorMessage:)`
- Expanded `Tests/AppDelegateTrackingIntegrationTests.swift` with high-risk remediation coverage:
  - calibration authorization denied with user choosing Open Settings:
    - asserts intent ordering `.showCalibrationPermissionDeniedAlert`, then `.openPrivacySettings`
    - asserts open-settings handler execution.
  - calibration authorization denied with cancel:
    - asserts no open-settings intent/handler.
  - camera calibration start-failed with retry:
    - asserts `.showCameraCalibrationRetryAlert(...)`, then `.retryCalibration`
    - asserts retry handler execution.
  - camera calibration start-failed with cancel:
    - asserts retry intent is not emitted/executed.
  - AirPods calibration start-failed:
    - asserts no camera-retry alert intent path.
- Validation:
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (22 tests).
  - `swift test --filter TrackingFeatureTests` passed (30 tests).
  - `swift test --filter TrackingParityReplayTests` passed (1 test).
  - Full suite `swift test` passed (348 tests, 0 failures).

### 2026-02-28 - Completed Chunk 26 (Codex)

- Formalized explicit migration completion criteria as the official end-state in this handoff:
  - Added `Migration End-State (Definition of Done)` with the five required completion conditions.
  - Added a strict `Iteration Gate (Required)` rule:
    - stop iterating and set `Recommended Next Steps` to `None` when all conditions are true,
    - continue only on unmet conditions when any are false.
- Aligned planning rules with user preference to avoid superfluous work by constraining future chunks to unmet end-state criteria only.
- Current end-state assessment at this checkpoint:
  - Item 1 (`Single transition authority`): `not yet complete` (startup transition paths still outside reducer boundary).
  - Item 2 (`AppDelegate adapter-only role`): `not yet complete` (startup/readiness/profile decision logic still mixed in adapter).
  - Item 3 (`Contract parity proven`): `true` (latest parity/integration suites are green).
  - Item 4 (`Startup paths reducer-aligned`): `not yet complete`.
  - Item 5 (`Migration guardrails preserved`): `true` (manual-only behavior preserved, no preferred/fallback runtime rollout).
- Validation:
  - Not run (docs-only criteria/governance update).

### 2026-02-28 - Completed Chunk 27 (Codex)

- Closed startup migration gaps by moving initial-setup decision authority into reducer logic:
  - Added pure startup decision helper in `Sources/PostureEngine.swift`:
    - `InitialSetupTransitionResult`
    - `stateWhenInitialSetupRuns(...)`
  - Added reducer startup action/intents in `Sources/TrackingFeature.swift`:
    - `Action.initialSetupEvaluated(...)`
    - `EffectIntent.applyStartupCameraProfile`
    - `EffectIntent.showOnboarding`
  - Reducer now decides startup branches for:
    - marketing mode startup monitor request,
    - camera profile-present+available startup recovery,
    - AirPods calibrated startup,
    - onboarding fallback.
- Updated `AppDelegate` startup path to adapter-only dispatch/execution:
  - `initialSetupFlow()` now:
    - builds startup context,
    - dispatches `.initialSetupEvaluated(...)`,
    - executes reducer-emitted intents and commits via adapter transition rules.
  - Added `InitialSetupContext` + `makeInitialSetupContext()` for event-local startup context assembly.
  - Added startup/testing seams in `Sources/AppDelegate.swift`:
    - `marketingModeOverride`
    - `initialSetupContextOverride`
    - `showOnboardingHandler`
    - `beginMonitoringSessionHandler`
- Expanded coverage for startup branches:
  - `Tests/PostureEngineTransitionTests.swift`:
    - startup pure transition cases (marketing/camera/airPods/onboarding).
  - `Tests/TrackingFeatureTests.swift`:
    - reducer startup action intent emission tests.
  - `Tests/AppDelegateTrackingIntegrationTests.swift`:
    - `initialSetupFlow` marketing-mode branch.
    - `initialSetupFlow` camera profile present+available branch.
    - `initialSetupFlow` AirPods calibrated branch.
    - `initialSetupFlow` onboarding fallback branch.
- End-state reassessment after this chunk:
  - Item 1 (`Single transition authority`): `true`
  - Item 2 (`AppDelegate adapter-only role`): `true`
  - Item 3 (`Contract parity proven`): `true`
  - Item 4 (`Startup paths reducer-aligned`): `true`
  - Item 5 (`Migration guardrails preserved`): `true`
- Validation:
  - `swift test --filter PostureEngineTransitionTests` passed (78 tests).
  - `swift test --filter TrackingFeatureTests` passed (33 tests).
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (26 tests).
  - Full suite `swift test` passed (359 tests, 0 failures).

### 2026-02-28 - Completed Chunk 28 (Codex)

- Aligned implementation with the original “single unified reducer boundary” goal by removing remaining non-reducer tracking-state transition paths:
  - Replaced settings-path direct state mutation (`pauseOnTheGo` toggle resume) with reducer dispatch:
    - Added `PostureEngine.stateWhenPauseOnTheGoSettingChanges(...)`.
    - Added `TrackingFeature.Action.pauseOnTheGoSettingChanged(isEnabled:)`.
    - Added `AppDelegate.setPauseOnTheGoEnabled(_:)` and routed `SettingsWindow` toggle handler to it.
  - Removed onboarding direct source assignment:
    - `showOnboarding` completion now calls `switchTrackingSource(to:)` (reducer-dispatched) instead of setting `trackingSource` directly.
- Expanded coverage for the new reducer-owned settings/onboarding-adjacent transition path:
  - `Tests/PostureEngineTransitionTests.swift`:
    - pause-on-the-go disable from `.paused(.onTheGo)` -> `.monitoring`.
    - pause-on-the-go enable keeps `.paused(.onTheGo)`.
  - `Tests/TrackingFeatureTests.swift`:
    - reducer action tests for `pauseOnTheGoSettingChanged`.
  - `Tests/AppDelegateTrackingIntegrationTests.swift`:
    - `setPauseOnTheGoEnabled(false)` resumes monitoring through reducer.
    - `setPauseOnTheGoEnabled(true)` keeps on-the-go pause.
- Updated end-state definition text to explicitly enforce no direct tracking-state mutations outside reducer-dispatch adapter paths.
- End-state reassessment after this chunk:
  - Item 1 (`Single transition authority`): `true`
  - Item 2 (`AppDelegate adapter-only role`): `true`
  - Item 3 (`Contract parity proven`): `true`
  - Item 4 (`Startup paths reducer-aligned`): `true`
  - Item 5 (`Migration guardrails preserved`): `true`
- Validation:
  - `swift test --filter PostureEngineTransitionTests` passed (80 tests).
  - `swift test --filter TrackingFeatureTests` passed (35 tests).
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (28 tests).
  - Full suite `swift test` passed (365 tests, 0 failures).

### 2026-02-28 - Completed Chunk 29 (Codex)

- Updated end-state wording to mirror the original contract goal explicitly:
  - Item 1 now requires `TrackingFeature` to be the single transition boundary for tracking behavior, consistent with `tracking-behavior-contract.md`.
  - Clarified that both transition decisions and effect intents must originate from reducer actions.
  - Kept the explicit prohibition on direct tracking-state mutations outside reducer-dispatch adapter commit paths.
- Re-ran the required iteration gate and implementation verification:
  - Item 1 (`Unified reducer transition boundary`): `true`.
  - Item 2 (`AppDelegate adapter-only role`): `true`.
  - Item 3 (`Contract parity proven`): `true`.
  - Item 4 (`Startup paths reducer-aligned`): `true`.
  - Item 5 (`Migration guardrails preserved`): `true`.
- Validation:
  - `rg -n "appDelegate\\.state\\s*=|self\\.state\\s*=|\\bstate\\s*=\\s*\\.(disabled|calibrating|monitoring|paused)" Sources/AppDelegate.swift Sources/SettingsWindow.swift` returned no matches.
  - Full suite `swift test` passed (365 tests, 0 failures).

### 2026-02-28 - Completed Chunk 30 (Codex)

- Continued TCA-effects migration hardening in reducer/runtime test surfaces:
  - Refactored `TrackingFeature` to construct effect-intent arrays locally per action and emit through reducer-returned effects (`.run`) via `emit(...)`, avoiding append-as-you-go queue mutation patterns in reducer branches.
  - Kept `State.effectIntents` as an explicit temporary parity/test surface only, populated from emitted intents by `emit(...)` and reset at reducer entry.
- Upgraded reducer parity replay harness to execute real reducer effects through a store-backed dispatch path:
  - `Tests/TrackingReducerScenarioHarness.swift` now dispatches actions asynchronously against `StoreOf<TrackingFeature>`,
  - captures emitted intents via dependency-injected `trackingEffectExecutor`,
  - and derives timeline flags from captured effects instead of direct state queue reads.
- Updated parity replay test orchestration for async reducer harness dispatch:
  - `Tests/TrackingParityReplayTests.swift` now runs scenario replay/compare with async `await` sequencing.
- End-state reassessment after this chunk:
  - Item 1 (`Unified reducer transition boundary`): `true`.
  - Item 2 (`AppDelegate adapter-only role`): `true`.
  - Item 3 (`Contract parity proven`): `true`.
  - Item 4 (`Startup paths reducer-aligned`): `true`.
  - Item 5 (`Migration guardrails preserved`): `true`.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (35 tests).
  - `swift test --filter TrackingCharacterizationTests` passed (27 tests).
  - `swift test --filter TrackingParityReplayTests` passed (1 test).
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (28 tests).
  - Full suite `swift test` passed (365 tests, 0 failures).
  - `./build.sh` passed and produced `/Users/tjohnell/projects/dorso/build/Dorso.app` (universal binary).

### 2026-02-28 - Completed Chunk 31 (Codex)

- Continued post-migration TCA purity hardening by removing the temporary reducer-state effect mirror:
  - Removed `TrackingFeature.State.effectIntents` from `Sources/TrackingFeature.swift`.
  - Simplified `emit(...)` in `TrackingFeature` to emit reducer effects directly without writing effect traces into state.
- Migrated reducer tests fully off state-level effect assertions:
  - Updated `Tests/TrackingFeatureTests.swift` to capture emitted intents through `trackingEffectExecutor` dependency injection.
  - Added reusable effect recorder/test helpers and converted all prior `state.effectIntents` assertions to emitted-intent assertions.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (35 tests).
  - Full suite `swift test` passed (365 tests, 0 failures).

### 2026-02-28 - Completed Chunk 32 (Codex)

- Removed remaining adapter return-value effect trace plumbing from AppDelegate transition dispatch seams:
  - `sendTrackingAction(...)` now returns only reducer state transition snapshots (`oldState`, `newState`) and no longer returns emitted intent arrays.
  - Deleted now-obsolete adapter intent stack/state capture in `AppDelegate`.
  - Updated camera/display/disconnect and all `dispatch*ForTesting(...)` helper signatures to async `Void` dispatch.
- Migrated AppDelegate integration tests fully to observer-captured effect assertions:
  - Updated `Tests/AppDelegateTrackingIntegrationTests.swift` to assert only against `trackingEffectIntentObserver`-captured intents and state outcomes.
  - Updated screen lock/unlock coverage to assert per-step emitted intents using step-local snapshots (lock emits none, unlock emits `.startMonitoring`).
- Minor cleanup:
  - Removed unnecessary `@discardableResult` on `applyCameraConnectedTransition(...)` after its signature became `Void`.
- Validation:
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (28 tests).
  - Full suite `swift test` passed (365 tests, 0 failures).

### 2026-02-28 - Completed Chunk 33 (Codex)

- Removed reducer/runtime pre-dispatch adapter state sync seam (previously `syncAdapterState`) to avoid hidden mirror-updates before every dispatched action:
  - Deleted `TrackingFeature.Action.syncAdapterState(...)` and reducer handling.
  - Deleted `AppDelegate.syncTrackingStoreAdapterState(...)`.
  - Simplified `AppDelegate.sendTrackingAction(...)` to dispatch reducer actions directly without pre-sync hydration.
- Added explicit out-of-band app-state sync action for legacy direct assignments:
  - Added `TrackingFeature.Action.setAppState(AppState)`.
  - `AppDelegate.state` setter now dispatches `.setAppState(...)` when changed outside a reducer dispatch (`trackingActionDispatchDepth == 0`), keeping reducer/runtime aligned without per-action hydration.
- Result:
  - The previous bridge-style “sync first, dispatch second” path is removed.
  - Reducer transitions remain the dispatch authority for tracking behavior; adapter performs execution/commit only.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (35 tests).
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (28 tests).
  - Full suite `swift test` passed (365 tests, 0 failures).

### 2026-02-28 - Completed Chunk 34 (Codex)

- Removed remaining command-intent interpreter execution path and replaced it with direct TCA runtime dependencies:
  - In `Sources/TrackingFeature.swift`:
    - Replaced `trackingEffectExecutor.execute(intent)` emission with direct dependency-driven effects via `trackingRuntime` client methods.
    - Reducer now performs direct `.run` calls for runtime work (monitor start/session begin, camera switching, UI sync, persistence, remediation flows).
  - In `Sources/AppDelegate.swift`:
    - Removed `executeTrackingEffectIntent(...)` switch interpreter.
    - Wired `trackingStore` dependencies with explicit `trackingRuntime.*` closures to runtime adapter methods.
    - Kept `trackingEffectIntentObserver` as test/diagnostic instrumentation only.
- Collapsed duplicate tracking ownership in `AppDelegate`:
  - Removed adapter-owned mirrored `stateBeforeLock`.
  - `state` and `trackingSource` now read from reducer state (`trackingStore.withState`) and write through reducer actions.
  - Added `applyTrackingStoreTransition(...)` to apply detector/UI runtime side effects based on reducer old/new snapshots.
- Removed obsolete adapter-transition migration artifact:
  - Deleted `Sources/TrackingAdapterTransition.swift`.
  - Deleted `Tests/TrackingAdapterTransitionTests.swift`.
- Updated reducer/integration/parity harnesses to new runtime dependency surface:
  - `Tests/TrackingFeatureTests.swift` now injects `trackingRuntime` recorder client.
  - `Tests/TrackingReducerScenarioHarness.swift` now records effects through `trackingRuntime`.
  - Updated integration and reducer expectations for source switch path (no `.setTrackingSource(...)` intent event).
- End-state reassessment after this chunk:
  - Item 1 (`Unified reducer transition boundary`): `true`.
  - Item 2 (`AppDelegate adapter-only role`): `true`.
  - Item 3 (`Contract parity proven`): `true`.
  - Item 4 (`Startup paths reducer-aligned`): `true`.
  - Item 5 (`Migration guardrails preserved`): `true`.
- Validation:
  - `swift test --filter TrackingFeatureTests` passed (35 tests).
  - `swift test --filter AppDelegateTrackingIntegrationTests` passed (28 tests).
  - `swift test` passed (362 tests, 0 failures).

## Recommended Next Steps (For Next Agent)

None

## Post-Migration TCA Purity Follow-Up

The migration end-state above is complete. Optional hardening status:

1. Completed:
   - Removed temporary reducer-state effect mirror (`TrackingFeature.State.effectIntents`).
2. Completed:
   - Moved reducer tests off state-level effect assertions to dependency-captured effect assertions.
3. Completed:
   - Re-ran full suite verification after the cleanup chunk.
4. Completed:
   - Removed adapter-facing effect trace return plumbing from `AppDelegate.sendTrackingAction(...)` and migrated integration tests to observer-only effect assertions.
5. Completed:
   - Replaced effect-intent interpreter execution with direct `trackingRuntime` dependency methods and removed obsolete adapter-transition scaffolding.

No remaining optional follow-up items are tracked in this handoff.
