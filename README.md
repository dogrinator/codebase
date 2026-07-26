# Aorty biaxial test system

This repository contains the MATLAB operator application and TwinCAT PLC
program for a two-axis biaxial test machine. The PLC owns all motion,
pre-conditioning, main-test, post-test, safety, and overforce behavior.
MATLAB validates the test, writes one complete command per selected axis,
records data, and displays machine state.

## Layout

```text
aorty/
  main.m                       MATLAB entry point
  controller/Control.m         PLC operation and recording coordination
  model/Plc.m                  ADS interface version 3 client
  model/GeneralTestDefinition.m
  view/View.m
  view/TestPanel.m
  .config/appConfig/           UI presets
  .config/hwConfig/            PLC/camera settings
  examples/general_test_example.json
  tests/                       Offline MATLAB and ADS-contract tests
MAINplc/
  DUTs/                        ADS command, status, and settings structures
  POUs/                        PLC motion, safety, and buffering logic
  READMEPLC.md                 Complete PLC contract and commissioning guide
```

## Requirements

- MATLAB with UI support and .NET interoperability.
- Beckhoff TwinCAT ADS assembly configured in `aorty/model/Plc.m`.
- TwinCAT PLC project in `MAINplc`, built and deployed with generated symbols.
- Camera and Image Acquisition Toolbox only when camera capture is required.

The current ADS defaults are AMS Net ID `5.85.113.174.1.1`, port `851`, and
interface version `2`. Change the machine-specific values before deployment.

## Start

Run `aorty/main.m`. The application resolves presets and hardware settings
from its own location, so MATLAB's current folder does not matter. It opens
offline; connect the PLC and camera with the UI switches.

At connection, MATLAB reads `nInterfaceVersion` from both axes. A mismatch
stops connection and explains that the matching PLC build must be deployed.

## Test tabs

- **Pre-test** runs PLC-owned force preload and constant force cycles.
- **Single** supports a displacement or force endpoint plus an optional OR
  endpoint.
- **Cyclic** supports independent displacement/force load and unload modes,
  constant values, and 1–100 cycles.
- **General** imports a complete versioned JSON test. See
  `aorty/examples/general_test_example.json`.
- **Post-test** selects stay, saved position, sequence start, pre-test final,
  or zero-force release. The PLC performs the action only after successful
  test completion.

Strain control and force-drop failure detection remain visible but disabled
because they are not part of the current PLC interface.

## Configuration

Hardware settings use `fForceReliefDistance` and
`fForceReliefVelocity`, both defaulting to `1.0`. Loading an older preset
adds these defaults and discards legacy `fMaxPosition`.

UI presets in `aorty/.config/appConfig` contain per-axis pre-test, single,
cyclic, camera, and post-test values. General JSON is authoritative and has
no UI overrides.

## Offline verification

From MATLAB:

```matlab
cd aorty
addpath(genpath(pwd))
results = runtests("tests");
assert(all([results.Passed]))
```

The suite checks DUT/ADS symbol names and array sizes, interface-version
rejection, write and trigger ordering, 100-entry padding, service pulses,
settings, General JSON validation, and invalid boundary values.

After building TwinCAT, run `verifyGeneratedTmc` from `aorty/tests` to compare
the generated metadata with every required version 2 field and array size.

## Generated TwinCAT symbols

`MAINplc/main program.tmc` is generated metadata. After changing a DUT, build
the PLC project in TwinCAT/XAE and commit the regenerated file. Do not edit it
by hand. The MATLAB computer used for this repository does not need TwinCAT
build tools for offline tests, but commissioning requires the freshly built
PLC and symbols.

## Safety

The UI STOP is a controlled software halt, not a safety-rated emergency stop.
Use the machine's approved safety system, conservative first-run settings,
and the commissioning checklist in `MAINplc/READMEPLC.md`.
