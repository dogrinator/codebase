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
  model/PlcAds.m               ADS interface version 5 transport
  model/PostProcessor.m        Phase-aware TIFF post-processing
  model/GeneralTestDefinition.m
  view/View.m
  view/TestPanel.m
  .config/appConfig/           UI presets
  .config/hwConfig/            PLC/camera settings
  examples/general_test_example.json
  tests/                       Offline MATLAB and ADS-contract tests
MAINplc/
  DUTs/                        ADS command, status, and settings structures
  POUs/                        PLC motion, safety, and synchronization logic
  READMEPLC.md                 Complete PLC contract and commissioning guide
```

## Requirements

- MATLAB with UI support and .NET interoperability.
- Beckhoff TwinCAT ADS assembly used by `aorty/model/PlcAds.m`.
- TwinCAT PLC project in `MAINplc`, built and deployed with generated symbols.
- Camera and Image Acquisition Toolbox only when camera capture is required.

The current ADS defaults are AMS Net ID `5.85.113.174.1.1`, port `851`, and
interface version `5`. Change the machine-specific values before deployment.

## Start

Run `aorty/main.m`. The application resolves presets and hardware settings
from its own location, so MATLAB's current folder does not matter. It opens
offline; connect the PLC and camera with the UI switches.

At connection, MATLAB reads `nInterfaceVersion` from both axes. A mismatch
stops connection and explains that the matching PLC build must be deployed.

## Test tabs

- **Pre-test** runs PLC-owned force pre-conditioning. Initial preload is an
  optional one-time force target, while pre-cycle load force is the independent
  repeated load target.
- **Single** supports a displacement or force endpoint plus an optional OR
  endpoint.
- **Cyclic** supports independent displacement/force load and unload modes,
  constant values, and 1-50 cycles.
- **General** imports a complete versioned JSON test. See
  `aorty/examples/general_test_example.json`.
- **Post-test** selects stay, saved position, sequence start, pre-test final,
  or zero-force release. The PLC performs the action only after successful
  test completion.

Single and Cyclic displacement values are positions relative to the coordinate
captured at the synchronized start of the main test; this origin is `0 mm`.
The selector tooltips repeat this definition.

The compact Test status indicator beside PLC connection displays Idle,
Pre-test, Test, or Post-test. If X and Y report different phases, both are
shown. A disconnected PLC produces a neutral disconnected state.

When the live graph shows Force and the Single or Cyclic tab is selected,
dashed reference lines preview the configured force targets for each active
axis. Equal targets share a label. The lines are hidden for displacement
graphs and the Pre-test, General, and Post-test tabs.

Force-drop and arm-above-force controls are not part of interface version 5.
Their command fields and legacy preset/General Test keys are rejected.

## Configuration

Hardware settings use `fForceReliefDistance` and
`fForceReliefVelocity`, both defaulting to `1.0`.

UI presets in `aorty/.config/appConfig` contain per-axis pre-test, single,
cyclic, post-processing, and post-test values. Presets use the current schema;
legacy camera-period and removed force-drop fields are not converted. General
JSON is authoritative and has no UI overrides.

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
settings. TIFF sampling never reduces raw acquisition. Each camera row is:

```text
Index,Timestamp,TestPhase
```

`TestPhase` uses `0` Idle, `1` Pre-test, `2` Test, and `3` Post-test, sampled
from the existing PLC status poll. Recordings without this column are rejected
by phase-aware post-processing.

On the Single and Cyclic tabs, checking **Sampling period [s]** enables
automatic TIFF post-processing. Leaving it unchecked still records all raw
camera data. **Include pre-test and post-test** selects phases 1-3; otherwise
only phase 2 is exported. Standalone Pre-test records raw frames but does not
start automatic TIFF processing. Automatic output is written to
`processed_frames`.

The **Post-process data** button processes a previously recorded test. The
user selects its directory, the minimum TIFF interval (`0.1 s` by default;
`0` exports every eligible frame), and whether to include phases 1 and 3.
Manual output uses a unique
`processed_frames_manual_<timestamp>` directory. Phase eligibility is applied
before interval sampling, and sampling restarts at phase transitions.

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
`includePrePost` selects phases 1-3 instead of phase 2 only. See the complete
example in `aorty/examples/general_test_example.json`.

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
service pulses, settings, General JSON validation, phase-aware
post-processing, and invalid boundary values.

After building TwinCAT, run `verifyGeneratedTmc` from `aorty/tests` to compare
the generated metadata with every required version 5 field and array size.

## Generated TwinCAT symbols

`MAINplc/main program.tmc` is generated metadata. After changing a DUT, build
the PLC project in TwinCAT/XAE and commit the regenerated file. Do not edit it
by hand.

The currently checked-in TMC still describes interface version 4 and must not
be treated as the version 5 deployment contract. TwinCAT/XAE must rebuild the
PLC project and regenerate the TMC before commissioning. The MATLAB computer
used for this repository does not need TwinCAT build tools for offline tests,
but commissioning requires the freshly built PLC and symbols.

## Safety

The UI STOP is a controlled software halt, not a safety-rated emergency stop.
Use the machine's approved safety system, conservative first-run settings,
and the commissioning checklist in `MAINplc/READMEPLC.md`.
