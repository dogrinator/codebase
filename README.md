# Aorty biaxial test system

This repository contains the MATLAB operator application and TwinCAT PLC
program for a two-axis biaxial test machine. The PLC owns all motion,
pre-conditioning, main-test, post-test, safety, and overforce behavior.
MATLAB validates each test, writes one complete command per selected axis,
records raw test and camera data, optionally creates TIFF output, and displays
machine state.

## Layout

```text
aorty/
  main.m                       MATLAB entry point
  controller/Control.m         PLC operation and recording coordination
  model/Plc.m                  PLC-facing validation and command facade
  model/plc/PlcAds.m           ADS interface version 6 transport
  model/PostProcessor.m        System-status-aware TIFF post-processing
  model/GeneralTestDefinition.m
  view/View.m
  view/TestPanel.m
  .config/appConfig/           UI presets
  .config/hwConfig/            PLC/camera settings
  examples/general_test_example.json
  tests/                       Offline MATLAB and ADS-contract tests
TwinCat/AortyPLC/
  aortyPLC.tsproj              Complete TwinCAT system, NC, and I/O project
  main program/
    DUTs/                      ADS command, status, and settings structures
    POUs/                      PLC motion, safety, and synchronization logic
    READMEPLC.md               Complete PLC contract and commissioning guide
```

## Requirements

- MATLAB with UI support and .NET interoperability.
- Beckhoff TwinCAT ADS assembly used by `aorty/model/plc/PlcAds.m`.
- TwinCAT project in `TwinCat/AortyPLC`, built and deployed with generated
  symbols.
- Camera and Image Acquisition Toolbox only when camera capture is required.
- Computer Vision Toolbox (the `insertText` function) only when annotated
  TIFF export is required.

The current ADS defaults are AMS Net ID `5.85.113.174.1.1`, port `851`, and
interface version `6`. Change the machine-specific values before deployment.
The MATLAB application version is `0.1.0`. PLC reads and machine-status
updates run every `0.25 s`.

## Start

Run `aorty/main.m`. The application resolves presets and hardware settings
from its own location, so MATLAB's current folder does not matter. It opens
offline; connect the PLC and camera with the UI switches.

At connection, MATLAB reads `nInterfaceVersion` from both axes. A mismatch
stops connection and explains that the matching PLC build must be deployed.

## Test tabs

- **Pre-test** runs PLC-owned force pre-conditioning. Initial preload is an
  optional one-time force target, while pre-cycle load force is the independent
  repeated load target. The two phases store independent per-axis force
  tolerances and hold times.
- **Single** supports a displacement or force endpoint plus an optional OR
  endpoint, with per-axis force tolerance and primary endpoint hold time.
- **Cyclic** supports independent displacement/force load and unload modes,
  constant values, 1-50 cycles, per-axis force tolerance, and load/unload
  endpoint hold time.
- **General** imports a complete versioned JSON test. See
  `aorty/examples/general_test_example.json`.
- **Post-test** selects stay, saved position, sequence start, pre-test final,
  or zero-force release. The PLC performs the action only after successful
  test completion.

Single and Cyclic displacement values are positions relative to the coordinate
captured at the synchronized start of the main test; this origin is `0 mm`.
The selector tooltips repeat this definition.

The compact System status indicator beside PLC connection displays the
version-6 PLC enum name and code: Idle, Error, Homing, Stopping, Taring,
BasicMove, ForceMode, Pretension, PreTestCyclic, SingleTest, CyclicTest, or
PostTest. An Idle peer is ignored during a single-axis operation. If two
non-idle X/Y statuses disagree, both axis codes and names are shown. A
disconnected PLC produces a neutral disconnected state.

The Live measurements panel keeps independent rolling Force and Displacement
histories, so switching signals never mixes newtons and millimetres. **Samples
shown** controls both the visible window and retained graph history from 50 to
50,000 samples; the session-only default is 500 samples (5 seconds at 100 Hz).
Disconnecting the PLC clears all histories, time axes, and endpoint overlays,
and discards unread samples so a reconnect starts with clean plots.

In Force mode, the selected Pre-test, Single, or Cyclic tab previews its
configured force endpoints for each active axis. Each unlabeled horizontal
target line includes a lightly shaded `target +/- tolerance` band. Hovering a
line highlights it and shows its axis, phase, endpoint name, target, tolerance,
and limits in the shared information box above both graphs. Equal
target/tolerance pairs are combined. Pre-test unload-to-start, displacement
endpoints, General tests, and Post-test do not produce overlays. Displacement
mode continues to show absolute NC axis positions.

Force-drop and arm-above-force controls are not part of interface version 6.
Their command fields and legacy preset/General Test keys are rejected.

## Configuration

Hardware settings use `fForceReliefDistance` and
`fForceReliefVelocity`, both defaulting to `1.0`.

UI presets in `aorty/.config/appConfig` contain per-axis pre-test, single,
cyclic, post-processing, and post-test values. Presets use the current schema;
legacy camera-period and removed force-drop fields are not converted. General
JSON is authoritative and has no UI overrides.

The Pre-test preset stores `record: true` by default. When checked, a
standalone pre-test prompts for an output folder and records raw data. When
unchecked, it starts without a folder prompt or files. Completion, abort, and
startup-failure handling are otherwise identical.

All new per-axis values are written to interface-version-6 commands:
`preTestForceTolerance`, `preloadHoldTime`, `preCycleHoldTime`,
`singleForceTolerance`, `singleForceHoldTime`, `cyclicForceTolerance`, and
`cyclicForceHoldTime`. Hold times apply to force and displacement endpoints.
The PLC has one pre-test tolerance per axis, so when preload and cyclic
pre-conditioning are both enabled on an active axis their two UI values must
match exactly. If only one phase is enabled, that phase's tolerance is used.
Inactive-axis mismatches are ignored.

Single force tolerance is editable when either endpoint uses Force and greyed
out when no force endpoint is selected. Cyclic force tolerance follows the
same rule for its load and unload modes. Hold times remain editable, and
disabled tolerance values remain saved.

## Biaxial synchronization

X-only and Y-only tests use the selected axis's individual `bExecute` command.
For Both, MATLAB writes and validates both complete commands without executing
either one, then pulses `MAIN.bStartBiaxialTest`. The PLC validates their phase
structure and starts both movement controllers in the same PLC scan.

The PLC holds both axes at shared barriers after pre-test, at each Cyclic load
and unload endpoint, after the main test, and after post-test. A force-controlled
axis continues regulating its target while it waits; a position-controlled axis
is held by the powered NC position loop. Test phases and final operation-counter
completion therefore remain synchronized. An error, protective stop, or
operator stop on either axis is propagated to its peer.

## Camera recording and post-processing

Raw camera frames are always recorded at the FPS configured in hardware
settings. TIFF sampling never reduces raw acquisition. Each recording
directory initially contains exactly two files:

```text
cam.bin
recording.h5
```

`cam.bin` is an unchanged, headerless sequence of fixed-size Mono8 frames.
Frame `n` begins at `(n-1) * width * height`. `recording.h5` schema version 1
contains camera index/timestamp/status rows, independent X and Y PLC sample
datasets, camera dimensions, recording status, and the runtime camera, PLC,
test-command, and post-processing settings. The PLC streams may have
different lengths; each axis stores elapsed time, force, untared force, and
position together.

Recordings also store the `0.25 s` status-resolution interval, per-axis
dropped-sample counts, and PLC-stream restart/loss flags. Any detected PLC
sample loss or counter restart aborts the active test so an incomplete
recording cannot be reported as completed.

Camera and PLC times are stored as seconds relative to the dated local
recording start. `SystemStatus` is the latest valid version-6
`nSystemStatus`, using the first active axis, X for Both, and Idle `0` when
no test axis is active. Post-processing accepts only this HDF5 schema;
legacy CSV recordings require an older application or a separate converter.

Completed and controlled-abort recordings store their final state and reason
inside `recording.h5`. If a readable interrupted recording has unmatched
final camera rows or binary bytes, post-processing warns and uses every
complete frame/timestamp pair.

If a recording contains no camera frames, post-processing reports that TIFF
generation was skipped and does not create an output directory.

On the Single and Cyclic tabs, checking **Sampling period [s]** enables
automatic TIFF post-processing. Leaving it unchecked still records all raw
camera data. **Include pre-test and post-test** selects statuses `10`, `11`,
`20`, `21`, and `30`; otherwise only main-test statuses `20` and `21` are
exported. A recorded standalone Pre-test does not start automatic TIFF
processing. Automatic output is written to `processed_frames`.

The **Post-process data** button processes a previously recorded test. The
user selects its directory, the minimum TIFF interval (`0.1 s` by default;
`0` exports every eligible frame), and whether to include pre/post statuses.
Manual output uses a unique
`processed_frames_manual_<timestamp>` directory. Phase eligibility is applied
before interval sampling. Sampling restarts whenever SystemStatus changes or
eligible rows are separated by an ineligible gap.

Both workflows preserve the integration-sensitive TIFF contract exactly:
`processed_frame_%04d.tiff`, the existing text overlay, the complete
`Description` keys/order/format/values, and the existing base-time and delta
calculations.

### Required TIFF file layout

The TIFF writer must produce the legacy Basler-compatible layout expected by
the downstream analysis software:

- Classic little-endian TIFF (`II`) with the IFD starting at byte `8`.
- Exactly `13` IFD entries and no next IFD.
- A `1024`-byte header; the uncompressed Mono8 pixel data starts at byte
  `1024`.
- The text overlay is stored in the metadata area beginning at byte `256` and
  must preserve the complete `Description` content and ordering.
- Pixel data is a single-channel `uint8` image, written row by row without
  compression.
- The image dimensions must fit in unsigned 16-bit TIFF width and height
  fields.
- The output filename remains `processed_frame_%04d.tiff`.

MATLAB's default `imwrite` TIFF output is not suitable for this contract,
because it may emit compressed or RGB data and place the IFD at a different
location. Any future implementation must preserve the byte offsets and
metadata contract above.

## General Test JSON

Schema version 1 supports `single` and `cyclic` tests for X, Y, or Both.
Cyclic load and unload arrays must have equal active-axis lengths from 1 to 50.
Removed keys and over-limit or fractional counts are rejected; no legacy-file
conversion is performed.

Every selected test now requires per-axis `forceTolerance` and `holdTime`
values. `preTest` requires `cyclicForceTolerance` and uses its existing
`holdTime` as the cyclic pre-conditioning hold. Its `preload` object also
requires independent `forceTolerance` and `holdTime` values. All tolerance and
hold-time values are finite and non-negative. Older schema-1 files without
these mandatory fields are rejected.

PLC interface version 6 exposes one `fPreTestForceTolerance` per axis. If both
preload and cyclic pre-conditioning are enabled on an active axis,
`preTest.preload.forceTolerance` must exactly equal
`preTest.cyclicForceTolerance`; otherwise the JSON is rejected before any PLC
write. When only one phase is enabled, its value is mapped. X and Y remain
independent.

The required `camera` object is:

```json
{
  "enabled": true,
  "samplingPeriod": 0.1,
  "includePrePost": true
}
```

`enabled` controls automatic TIFF post-processing, not raw camera capture.
`samplingPeriod` is the minimum TIFF interval and may be `0`.
`includePrePost` selects statuses `10`, `11`, `20`, `21`, and `30` instead of
main statuses `20` and `21` only. See the complete example in
`aorty/examples/general_test_example.json`.

## Offline verification

From MATLAB:

```matlab
cd aorty
addpath(genpath(pwd))
results = runtests("tests");
assert(all([results.Passed]))
```

The suite checks DUT/ADS symbol names and array sizes, interface-version
rejection, single-axis and shared biaxial trigger ordering, 50-entry padding,
service pulses, settings, General JSON validation, SystemStatus-aware
post-processing, and invalid boundary values.

After building TwinCAT, run `verifyGeneratedTmc` from `aorty/tests` to compare
the generated metadata with every required version 6 field and array size.

## Generated TwinCAT symbols

`TwinCat/AortyPLC/main program/main program.tmc` is generated metadata. After
changing a DUT, build the PLC project in TwinCAT/XAE and commit the regenerated
file. Do not edit it by hand.

The checked-in TMC describes the 856-byte version-6 status structure,
50-element buffers, and `nSystemStatus` at byte offset 850. Because the PLC
source has changed, TwinCAT/XAE must still rebuild the project and regenerate
the TMC before commissioning. The MATLAB computer used for this repository
does not need TwinCAT build tools for offline tests.

## Safety

The UI STOP is a controlled software halt, not a safety-rated emergency stop.
Use the machine's approved safety system, conservative first-run settings,
and the commissioning checklist in
`TwinCat/AortyPLC/main program/READMEPLC.md`.
