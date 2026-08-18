# Aorty MATLAB architecture

This guide describes how the MATLAB application divides responsibility and how
its main workflows move through those components. For PLC internals and the ADS
wire contract, see the
[TwinCAT PLC guide](<../TwinCat/AortyPLC/main program/READMEPLC.md>) and the
[MATLAB-TwinCAT interface guide](hardware/plc/interfaceReadme.md).

## Component responsibilities

```mermaid
flowchart LR
    Operator["Operator"] --> View["View and UI components"]
    View --> Control["Control"]
    Control --> Camera["Camera"]
    Control --> Plc["PLC facade"]
    Plc --> Ads["PlcAds transport"]
    Ads <--> TwinCAT["TwinCAT PLC"]
    Control --> Buffer["AcquisitionBuffer"]
    Camera --> RecordingSession["RecordingSession recording coordination"]
    Buffer --> RecordingSession["RecordingSession recording coordination"]
    RecordingSession --> Store["RecordingStore"]
    Store --> Files["recording.h5 and cam.bin"]
    Files --> Processor["PostProcessor"]
    Files --> Validation["RecordingAnalysis"]
    View --> Settings["Settings"]
    Control --> Settings
    Settings --> Camera
    Settings --> Plc
```

- `View` and its components own presentation, operator input, and dialogs.
- `Control` coordinates UI requests, hardware operations, acquisition, tests,
  recording, and application-level error handling.
- `Plc` exposes machine operations while `PlcAds` owns ADS handles, packet
  encoding, and packet decoding.
- `Camera` owns camera acquisition and the latest captured frame.
- `AcquisitionBuffer` holds PLC samples between the read and display timers.
- `RecordingSession` coordinates recording state and delegates file
  persistence to `RecordingStore`.
- `PostProcessor` reads completed recordings and exports compatible TIFF
  frames. `RecordingAnalysis` performs separate offline analysis of HDF5 data.

## Test execution flow

TwinCAT owns the real-time test sequence. MATLAB validates and prepares a
complete command before it sends the start trigger.

```mermaid
sequenceDiagram
    actor Operator
    participant View
    participant Control
    participant Builder as TestCommandBuilder
    participant Plc
    participant TwinCAT

    Operator->>View: Start selected test
    View->>Control: Run test with UI configuration
    Control->>Builder: Build and validate commands
    Builder-->>Control: Complete per-axis commands
    Control->>Control: Prepare optional recording
    Control->>Plc: Write commands, then trigger start
    Plc->>TwinCAT: ADS command writes
    loop While the operation is active
        Control->>Plc: Read FIFO samples and status
        Plc-->>Control: Samples, state, and integrity counters
        Control-->>View: Display data and machine state
    end
    TwinCAT-->>Plc: Completion or error state
    Plc-->>Control: Final status
    Control-->>View: Finish or report the failure
```

## Recording flow

Camera frames and PLC samples retain independent timing and sample counts.
They are synchronized only during post-processing.

```mermaid
flowchart TD
    Start["Control prepares recording"] --> Store["RecordingStore opens outputs"]
    Store --> Ready["Recording becomes active"]
    Ready --> Camera["Camera callback supplies full Mono8 frames"]
    Ready --> Plc["Read timer receives PLC FIFO batches"]
    Camera --> CameraWrite["RecordingSession appends frame bytes, timestamps, and status"]
    CameraWrite --> CamBin["cam.bin and camera rows in recording.h5"]
    Plc --> Buffer["AcquisitionBuffer"]
    Buffer --> Display["Display timer drains plot data"]
    Buffer --> HDF5["RecordingSession appends axis samples to recording.h5"]
    HDF5 --> Finish["Control finishes or aborts recording"]
    CamBin --> Finish
    Finish --> Closed["RecordingStore closes both files independently"]
    Closed --> Process["PostProcessor filters and aligns recorded data"]
    Process --> TIFF["Compatible TIFF frames"]
```

## Shutdown flow

Shutdown is best-effort: failure to release one resource must not prevent
attempts to release the remaining resources.

```mermaid
sequenceDiagram
    actor Operator
    participant View
    participant Control
    participant Camera
    participant Plc

    Operator->>View: Close application
    View->>View: Disable repeated close requests
    View->>View: Stop controller timer objects
    View->>Control: Abort active work and finish recording
    View->>Camera: Close acquisition
    View->>Plc: Disconnect and power off
    View->>View: Close child windows and delete UI
```

The current shutdown call sequence begins in `View`; moving lifecycle ownership
into `Control` remains a separate review item and is intentionally outside this
documentation-only description.
