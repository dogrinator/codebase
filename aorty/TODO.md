# Aorty MATLAB review notes

Prioritized review work. Unchecked items remain proposals and should be planned
and verified separately before implementation.

## Useful next

### Enforce configured velocity limits

- [ ] Apply each axis's configured `fMaxVelocity` to manual-motion and
  test-speed inputs while retaining the existing positive minimum.

### Centralize hardware and shutdown lifecycle

- [ ] Remove UI controls and alerts from `Camera` and `Plc`; let them return
  results or throw errors while `View` owns presentation.
- [ ] Let `Control` coordinate camera and PLC connection workflows, including
  applying the selected hardware configuration.
- [ ] Let `Control` stop its timers, abort active work, and release camera and
  PLC resources before `View` removes the UI.
- [ ] Run each shutdown cleanup independently and warn when one fails so it
  cannot prevent the remaining cleanup attempts.

### Clarify acquisition-buffer ownership

- [ ] Make `AcquisitionBuffer` return or drain batches without writing directly
  to `Model`.
- [ ] Let `Control` decide whether drained data is displayed, recorded,
  discarded, or cleared after a disconnect.

## Useful later or blocked

### Encapsulate test and recording sessions

- [ ] Replace direct recording-state mutation with explicit prepare, start,
  finish, and abort operations.
- [ ] Evaluate a `TestSession` for operation state, transitions, integrity
  counters, and optional recording coordination.
- [ ] Rename or replace the generic `Model` only as part of that responsibility
  change; introduce a separate `RecordingSession` only if the recording
  responsibility remains large.
- [ ] Keep file persistence in `RecordingStore`.

### Display safe position limits after commissioning

- [ ] Commission authoritative safe X/Y travel limits and make them available
  to MATLAB before implementing plot overlays.
- [ ] Once available, expose those limits through the machine configuration or
  status contract and show them on displacement plots.

Do not infer position limits from the current asymmetric TwinCAT defaults.

## Completed

### Readability and navigation

- [x] Relax forced line wrapping where it made simple expressions harder to
  read while retaining sensible wrapping for genuinely complex statements.
- [x] Group facade methods, event handlers, controller-facing updates, and
  private helpers into clearly named MATLAB `%%` sections.
- [x] Add concise comments for intent, state transitions, safety rules, and
  unusual decisions without repeating the code.

### Architecture documentation

- [x] Provide a root `README.md` and a concise architecture document with
  Mermaid component and execution-flow diagrams.
- [x] Keep subsystem documentation only where the subsystem needs it.

### Shared focus restoration

- [x] Keep `restoreFigureFocus` as shared UI support while multiple components
  need it.
