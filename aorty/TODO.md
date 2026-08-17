# Aorty MATLAB review notes

Brainstorming candidates, not approved changes.

## Project-wide

### Review class and folder organization

- Group classes by clear responsibility and ownership where navigation is
  confusing; account for MATLAB path and package behavior before moving files.
- Preserve the high-level MVC separation, but replace the generic `Model` name
  if its responsibility remains specifically recording state and coordination.

### Review forced line wrapping

- Relax the strict line-length limit where wrapping makes simple conditions or
  expressions harder to read.
- Keep sensible wrapping for long function arguments, structs, and genuinely
  complex statements.

### Improve comments and class navigation

- Group facade methods, event handlers, controller-facing updates, and private
  helpers into clearly named MATLAB `%%` sections.
- Add concise comments for intent, state transitions, safety rules, and unusual
  decisions; avoid comments that only repeat the code.

### Add an architecture overview

- Create a root `README.md` and a concise architecture document with Mermaid
  component and execution-flow diagrams.
- Add folder-specific READMEs only for complex subsystems that need them.

### Review repeated class helpers

- Find repeated stateless methods and extract shared functions only where this
  improves ownership and removes real duplication.

### Review test-only production seams

- Move test-only defaults and branches into test fixtures where practical;
  retain useful dependency injection and genuine optional arguments.

### Strengthen MVC boundaries

- Keep UI controls and alerts out of `Camera` and `Plc`; return results or
  errors through `Control` for presentation by `View`.

## View

### Add meaningful operating limits

- Set logical minimum and maximum values for numeric UI inputs such as speed.
- Show the hardware-safe minimum and maximum positions on displacement plots.

### Extract manual post-processing UI

- Consider a `PostProcessingView` that owns folder/options dialogs, progress,
  results, and focus restoration while `Control` keeps processing orchestration.
- Keep `restoreFigureFocus` shared while multiple UI components need it.

### Consider extracting the main toolbar

- Consider a `MainToolbar`/`AppToolbar` component with a small interface that
  owns toolbar controls and presentation; keep workflows in `View`.

### Simplify best-effort shutdown cleanup

- Replace repeated silent `try/catch` blocks with a helper that warns and lets
  each timer or hardware cleanup run independently.

## Controller

### Consider extracting test execution

- Evaluate a `TestSession` that owns test state, transitions, and its optional
  recording lifecycle while `Control` coordinates the UI and hardware.
- Split out an internal `RecordingSession` later only if that responsibility
  remains large; keep file writing in `RecordingStore`.

### Review acquisition-buffer ownership

- Avoid `AcquisitionBuffer` depending directly on `Model`; let its owner drain
  batches and decide whether to display, record, or discard them.
- Move disconnect-time buffer clearing out of `View` and into `Control`.

### Clarify lifecycle ownership

- Let `Control` shut down the timers and hardware resources it owns; `View`
  should request shutdown and then remove its UI.
- Keep recording state privately writable behind explicit prepare, start,
  finish, and abort operations.
