# Tracking Behavior Contract

## Purpose

This document defines the behavior contract for the tracking subsystem while migrating Dorso to TCA.

- `Current required behavior` must stay equivalent to `main`, except approved deviations listed below.
- `Future preferred-mode constraints` guide architecture now, but are not enabled behavior yet.

## Approved Deviations from `main`

- Unavailability semantics must be source-specific for both detector types (camera and AirPods), rather than camera-worded behavior for all cases.
- Screen lock behavior should be simpler than current implementation detail:
  - Lock: if detector work is active, transition to `paused(screenLocked)`, stop active tracking work, and capture the pre-lock state.
  - Unlock: restore the pre-lock state and resume detector work according to that restored state.

## Current Required Behavior (Must Match `main`)

### State Model

- App tracking states are `disabled`, `calibrating`, `monitoring`, `paused(reason)`.
- Pause reasons are exactly: `noProfile`, `onTheGo`, `cameraDisconnected`, `screenLocked`, `airPodsRemoved`.
- Exactly one active tracking source exists at a time: `camera` or `airpods`.

### Startup and Initial Setup

- On launch, persisted settings are loaded before setup flow.
- If marketing mode is on, app starts monitoring immediately.
- If tracking source is camera:
- Use current display config key to load camera profile.
- Start monitoring only if that profile exists and its camera is currently available.
- If tracking source is AirPods:
- Start monitoring only if persisted AirPods calibration exists and is valid.
- If no valid calibration path exists, onboarding is shown.

### Enable/Disable Toggle

- If currently `disabled`, enabling does:
- Pause with `noProfile` if active source is not calibrated.
- Pause with source-specific unavailability reason if active source detector is unavailable.
- Otherwise start monitoring.
- If currently not `disabled`, toggle sets state to `disabled`.

### Manual Source Switching

- Switching source is an explicit manual action from settings/onboarding.
- Switching source stops the currently active detector immediately.
- New source is persisted right away.
- If new source is calibrated, monitoring starts.
- If new source is not calibrated, state becomes `paused(noProfile)` and calibration is user-initiated.

### Calibration Flow

- Calibration is single-flight: if calibration window is already active, additional starts are ignored.
- Calibration always requests authorization for the current source first.
- If authorization is denied:
- Return to `monitoring` if currently calibrated, else `paused(noProfile)`.
- Show permission alert with open-settings action.
- If detector fails to start for calibration:
- State becomes source-specific unavailability pause:
  - camera source: `paused(cameraDisconnected)`
  - AirPods source: `paused(airPodsRemoved)`
- For camera source, show retry alert.
- On calibration completion:
- Require at least 4 samples.
- Build calibration using active detector type.
- Camera calibration is saved both as in-memory camera calibration and display-profile storage.
- AirPods calibration is saved in persisted AirPods calibration.
- Reset monitoring posture counters and start monitoring.
- On calibration cancel:
- If calibrated, restart monitoring.
- Else `paused(noProfile)`.

### Monitoring Flow

- Monitoring requires valid current-source calibration unless in marketing mode.
- If calibration missing, transition to `paused(noProfile)`.
- For AirPods source:
- Treat "connected to Mac" and "in-ear motion available" as distinct facts.
- If in-ear motion is unavailable, begin monitoring session but state is `paused(airPodsRemoved)`.
- When connected event arrives while paused for removal, monitoring resumes.
- While monitoring AirPods, disconnect event transitions to `paused(airPodsRemoved)`.
- In marketing mode, state is `monitoring` regardless of calibration.

### Non-Active State Reset Behavior

- Any transition from active tracking (`monitoring`/`calibrating`) to a non-active state (`paused`/`disabled`) resets posture warning runtime state.
- Reset behavior is reason-agnostic and source-agnostic (not specific to AirPods pause paths).

### Detector Runtime Rules

- Active detector should run in `calibrating` and `monitoring`.
- Active detector should stop in `disabled` and paused states, except:
- AirPods detector stays running in `paused(airPodsRemoved)` to detect reconnection.
- Non-active detector is always stopped.
- Detector start failures from state sync force a source-specific unavailability pause outcome.

### Camera Hot-Plug

- Camera connect handling only applies when active source is camera.
- If currently paused and matching profile camera connects:
- Select that camera, load profile calibration, switch camera, and start monitoring.
- Else if pause reason was `cameraDisconnected`, transition to `paused(noProfile)`.
- Camera disconnect handling only applies when active source is camera.
- If disconnected camera is not selected camera, only UI sync occurs.
- If selected camera disconnects and another camera exists:
- Switch to fallback camera.
- If fallback has matching profile calibration, start monitoring.
- Else `paused(noProfile)`.
- If no fallback camera exists, `paused(cameraDisconnected)`.

### Display Configuration Changes

- Overlay windows are rebuilt on display config changes.
- If app state is `disabled`, no tracking-state transition occurs.
- If `pauseOnTheGo` is enabled and laptop-only display config is detected, state becomes `paused(onTheGo)`.
- Camera-specific behavior on display changes:
- If no cameras available: `paused(cameraDisconnected)`.
- If profile exists for current display and its camera is available:
- Ensure selected camera matches profile camera.
- Load camera calibration from profile and start monitoring.
- Else `paused(noProfile)`.

### Screen Lock Behavior

- On screen lock:
- If detector work is active for the current state, transition to `paused(screenLocked)`, stop active detector work, and capture the pre-lock state.
- If detector work is already inactive, do not force a new monitoring-related transition.
- On screen unlock from `paused(screenLocked)`:
- Restore the captured pre-lock state.
- Resume detector work according to detector runtime rules for the restored state.

### Persistence and Migration

- Persisted keys include tracking source (`trackingSource`) and AirPods calibration.
- Camera calibration is persisted via display profile data, not in `airPodsCalibration` key.
- Legacy AirPods calibration key migrates once into `airPodsCalibration` if needed.

### Settings UI Contract

- Settings tracking controls are manual source only.
- AirPods option is disabled in source picker if AirPods detector reports unavailable.
- Recalibrate button starts calibration for current source.
- Changing selected camera restarts camera and transitions to `paused(noProfile)`.

## Future Preferred-Mode Constraints (Design Requirements, Not Enabled Behavior Yet)

### Domain Modeling Requirements

- TCA state must model preferences independently from runtime state.
- Include policy-ready preference fields from day one:
- `trackingMode` (`manual` now, `automatic` future)
- `manualSource`
- `preferredSource` (future use)
- `autoReturnEnabled` (future use)
- Runtime should carry source-specific readiness facts separately from decisions:
- permission
- connection
- calibration
- availability

### Architecture Requirements

- Use one tracking reducer as the only transition boundary for tracking behavior.
- Encode external stimuli as events/actions:
- permission result
- detector start/stop result
- camera connect/disconnect
- AirPods connection change
- display config change
- screen lock/unlock
- settings mutations
- Keep policy/readiness/decision logic pure and deterministic.
- Keep side effects in dependencies/clients only.

### Migration Safety Requirements

- During TCA migration, manual-mode runtime behavior must remain equivalent to `Current required behavior`.
- No preferred/fallback runtime behavior should be user-visible until explicitly enabled.
- Contract-breaking changes require explicit contract revision before implementation.

### Preferred-Mode Readiness Requirements

- Reducer design must be able to add automatic fallback and auto-return without changing event sources.
- Action/effect surface should support future remediation actions:
- request permission
- open privacy settings
- connect device guidance
- calibrate source
- Future automatic mode should be implemented as additive logic in reducer, not by re-introducing imperative branching in app wiring.

## Parity Acceptance Criteria for TCA Migration

- All existing tests pass.
- New contract tests (to be added) cover the state/event timelines above.
- Manual source user flows remain unchanged from `main`.
- No user-facing strings or pause semantics change during migration-only PRs.

## Alignment Checklist (Review Before Test Authoring)

Use this section to confirm intent before characterization/replay tests are written.

- Item 1: Manual mode only during migration phase. `keep`
- Item 2: Source switch remains explicit user action, not automatic. `keep`
- Item 3: Missing calibration maps to `paused(noProfile)`. `keep`
- Item 4: Detector unavailability maps to `paused(cameraDisconnected)` for both sources in current behavior. `change`
  - Resolution: model and surface unavailability for both detector types explicitly (camera: `paused(cameraDisconnected)`, AirPods: `paused(airPodsRemoved)`).
- Item 5: AirPods disconnect while monitoring maps to `paused(airPodsRemoved)` and resumes on reconnect. `keep`
- Item 6: Camera hot-plug fallback logic remains profile-driven by display config key. `keep`
- Item 7: Screen lock captures/restores `stateBeforeLock` semantics exactly. `change`.
  - Resolution: lock pauses active detector work and captures pre-lock state; unlock restores that pre-lock state.
- Item 8: `pauseOnTheGo` pause precedence on laptop-only display remains unchanged. `keep`
- Item 9: Calibration denial returns to `monitoring` if calibrated, else `paused(noProfile)`. `keep`
- Item 10: Camera selection change in settings restarts camera and transitions to `paused(noProfile)`. `keep`
- Item 11: During migration, no preferred/fallback runtime behavior is user-visible. `keep`
- Item 12: Future preferred mode should be additive in reducer logic, not app wiring branches. `keep`
