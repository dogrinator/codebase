# EL3356-0020 load-cell setup and calibration

This guide is for the two strain-gauge (tenzo) inputs used by Aorty. The
TwinCAT project contains this EtherCAT order:

1. `EL7062` stepper terminal
2. `EL9510` 10 V bridge-supply terminal
3. `EL3356-0020` for the X load cell (`Term 4`)
4. `EL3356-0020` for the Y load cell (`Term 5`)

The EL3356-0020 is a one-channel, 24-bit, high-precision full-bridge input. It
accepts a load cell in 4-wire or 6-wire connection. The Aorty project maps the
terminal's signed 32-bit `RMB Value (INT32)` PDO to:

| Terminal | PLC variable | Sign in Aorty |
| --- | --- | --- |
| Term 4 | `MAIN.nRawTenzoX` | Inverted before conversion |
| Term 5 | `MAIN.nRawTenzoY` | Used directly |

The PLC converts the mapped value to force as:

```text
force_N = raw_value * fTenzoCons + fTenzoOffset
displayed_force_N = force_N + runtime_tare_offset
```

`fTenzoCons` therefore has unit `N/count` and `fTenzoOffset` has unit `N` in
this application.

> **Safety:** Calibrate with motion disabled, the structure mechanically
> supported, and the approved emergency stop and force protection available.
> Never exceed the load cell's rated load. Start later motion tests with low
> velocity and conservative maximum-force limits.

## Beckhoff documentation

- [EL3356-0020 product page](https://www.beckhoff.com/en-en/products/i-o/ethercat-terminals/el-ed3xxx-analog-input/el3356-0020.html)
- [EL3356 English manual (PDF)](https://download.beckhoff.com/download/document/io/ethercat-terminals/el3356en.pdf)
- [EL3356 quick start](https://infosys.beckhoff.com/content/1033/el3356/1942759435.html)
- [EL3356 connection and pin assignment](https://infosys.beckhoff.com/content/1033/el3356/1971758731.html)
- [Sensor calibration procedure](https://infosys.beckhoff.com/content/1033/el3356/1976568587.html)
- [CoE object description and parameterization](https://infosys.beckhoff.com/content/1033/el3356/1942783883.html)
- [EL3356 commands (`0xFB00`)](https://infosys.beckhoff.com/content/1033/el3356/1976649483.html)
- [Automatic self-calibration](https://infosys.beckhoff.com/content/1033/el3356/1976578827.html)
- [EL95xx/EL9510 power-supply manual (PDF)](https://download.beckhoff.com/download/document/io/ethercat-terminals/el95xx_en.pdf)

## 1. Record the sensor data

Before wiring or changing TwinCAT, record this information for each X/Y load
cell:

- manufacturer and serial number;
- rated capacity and unit;
- rated output/sensitivity in `mV/V`;
- zero balance in `mV/V`, if stated;
- permitted excitation voltage;
- wire colours and whether the cable is 4-wire or 6-wire;
- calibration-certificate date;
- direction that should be positive force.

Do not infer wire colours. Use the load-cell manufacturer's data sheet.

## 2. Wire and inspect the bridge

Switch off field power before changing wiring. The EL9510 supplies 10 V on the
power contacts. Confirm that 10 V is permitted by the load-cell data sheet.

The EL3356 terminal points are:

| Point | Signal | Purpose |
| ---: | --- | --- |
| 1 | `+UDIFF` | Positive bridge signal |
| 2 | `-UDIFF` | Negative bridge signal |
| 3 | `-UV` | Negative bridge supply from power contact |
| 4 | Shield | Cable shield |
| 5 | `+UREF` | Positive sense/reference input |
| 6 | `-UREF` | Negative sense/reference input |
| 7 | `+UV` | Positive bridge supply from power contact |
| 8 | Shield | Cable shield |

For a 6-wire cell, connect excitation, sense, signal, and shield according to
the sensor sheet. For a 4-wire cell supplied from the power contacts, Beckhoff
requires jumpers between terminal points `3-6` and `5-7`. Bond the shield as
specified by Beckhoff and the machine EMC design.

Inspect for loose conductors, shorts, correct polarity, and a sound shield
connection before restoring power.

## 3. Verify the terminals in TwinCAT 3

1. Open `TwinCat/AortyPLC/aortyPLC.sln` (or the contained TwinCAT project) in
   the TwinCAT-compatible Visual Studio/XAE environment.
2. Select the target controller and place TwinCAT in **Config mode** if an I/O
   scan or configuration change is necessary.
3. Under **I/O > Devices > Device 1 (EtherCAT)**, verify the physical order:
   `EK1200`, `EL7062`, `EL9510`, X `EL3356-0020`, Y `EL3356-0020`, `EL9011`.
4. If the physical installation differs, use **Scan** carefully and compare
   the result before accepting it. Do not replace the stored configuration
   blindly.
5. Activate the configuration, restart TwinCAT in Run mode, and verify each
   EL3356 reaches EtherCAT OP state. Beckhoff's quick start expects `State = 8`
   and `WC = 0`.
6. For Term 4 and Term 5, open **Process Data** and verify that
   `RMB Value (INT32) > Value` is selected and linked respectively to
   `MAIN.nRawTenzoX` and `MAIN.nRawTenzoY`.
7. Online, observe the raw variables with no load and while applying a small,
   safe force by hand. The values must be stable and must change smoothly.
   Stop if `Data invalid`, `Error`, `Overrange`, or `Sync error` is set.

## 4. Choose one calibration ownership model

Aorty currently applies a linear calibration in the PLC. Use one of these
models consistently:

### Recommended for this project: calibrate raw counts in Aorty

Leave the EL3356 measurement/scaling configuration unchanged and determine
`fTenzoCons` and `fTenzoOffset` from two or more traceable force points. This
matches the current source code and JSON settings.

### Alternative: calculate engineering units in the EL3356

The terminal can calculate the final load from its CoE sensor parameters. If
this mode is adopted, deliberately change the PLC scaling to match the PDO's
unit (often `fTenzoCons = 1` and `fTenzoOffset = 0`) and validate the complete
signal chain. Do not apply terminal engineering-unit scaling and the old
`N/count` conversion at the same time.

The remainder of this guide uses the recommended Aorty-owned calibration.
The Beckhoff terminal-calibration method is included later for reference.

## 5. Measure calibration points

Use a traceable force reference or calibrated test machine. A hanging mass
creates force `F = mass * local_gravity`; use a force reference directly when
the machine orientation, fixtures, or friction make a hanging mass unsuitable.

1. Warm up the electronics and mechanics according to the sensor and machine
   requirements.
2. Disable motion. Mount the normal fixtures and ensure no fixture is binding.
3. Do not press **Tare load cells** during permanent calibration. Runtime tare
   is temporary compensation and is separate from `fTenzoOffset`.
4. With the cell unloaded, wait for a stable reading and average multiple raw
   samples. Record this as `(R0, F0)`. Normally `F0 = 0 N`.
5. Apply a known reference force in the normal working direction. A point at
   20% or more of rated capacity is preferable; more of the safe working range
   generally improves the slope estimate. Wait for mechanical and filtered
   readings to settle, then average and record `(R1, F1)`.
6. Preferably record several increasing and decreasing points across the
   intended working range. This exposes non-linearity, hysteresis, creep, and
   fixture friction that a two-point check cannot reveal.
7. Remove the load and verify that the raw reading returns close to `R0`.

Use the value as it enters each `fb_StatusBuffer`: X is `-MAIN.nRawTenzoX`, Y
is `MAIN.nRawTenzoY`. This accounts for the intentional X sign inversion.

## 6. Calculate the Aorty constants

For two calibration points:

```text
fTenzoCons   = (F1 - F0) / (R1 - R0)       [N/count]
fTenzoOffset = F0 - R0 * fTenzoCons         [N]
```

Example only: if the processed raw reading is `20,000` counts at `0 N` and
`520,000` counts at `100 N`:

```text
fTenzoCons   = 100 / (520000 - 20000) = 0.0002 N/count
fTenzoOffset = 0 - 20000 * 0.0002     = -4 N
```

For three or more points, fit `F = R*C + O` by linear least squares and use
the fitted slope `C` and intercept `O`. Keep the raw data and residuals with
the calibration record.

If the calculated slope is negative when the intended loading direction
should be positive, first recheck the selected axis, the X sign inversion,
and signal polarity. Do not swap wires casually on an energized system.

## 7. Save the constants in Aorty

1. Back up the active hardware JSON from `aorty/.config/hwConfig/`.
2. Open Aorty, open **Settings**, and select the hardware configuration being
   commissioned.
3. In **Tenzo settings**, enter the X and Y `fTenzoCons` and
   `fTenzoOffset` values. The UI describes these as **Force calibration**
   (`N/count`) and **Force sensor offset** (`N`).
4. Save the configuration under a descriptive name rather than overwriting a
   known-good calibration until validation is complete.
5. Apply the settings while the machine is idle. Aorty writes them by ADS to
   `MAIN.stSettingsX` and `MAIN.stSettingsY`.
6. Re-read or reopen the settings and confirm that the saved values match.

The JSON representation is:

```json
{
  "plc": {
    "xAxis": {
      "fTenzoOffset": 0.0,
      "fTenzoCons": 0.0002
    },
    "yAxis": {
      "fTenzoOffset": 0.0,
      "fTenzoCons": 0.0002
    }
  }
}
```

Do not replace a complete hardware file with this abbreviated example; the
real file also contains control, safety, and camera settings.

## 8. Tare and validate

1. Remove the applied reference and put the machine in its normal zero-load
   condition.
2. Home the applicable axis. Aorty intentionally blocks tare during motion or
   homing and before the axis is homed.
3. Press **Tare load cells** once. The PLC averages 100 consecutive converted
   samples and applies a runtime offset.
4. Confirm the displayed force is close to zero and stable.
5. Apply each validation force without editing the constants. Record applied
   force, displayed force, error, loading direction, and temperature.
6. Check both increasing and decreasing loads. Include zero, at least one
   mid-range point, and the highest approved commissioning point.
7. Confirm the X and Y forces have the intended sign and that loading one axis
   does not create unacceptable cross-axis response.
8. Remove the load and verify the zero return. Repeat after the planned warm-up
   time and, if relevant, at the expected operating temperatures.
9. Set `fMaxForce`, force tolerance, force-relief distance/velocity, and motion
   limits only from the approved machine safety assessment. Test protection
   initially at low speed and force under controlled conditions.

Archive the sensor serial number, terminal serial number, JSON filename,
constants, raw measurements, reference instrument, date, operator, ambient
conditions, and validation results.

## 9. Optional Beckhoff sensor calibration in CoE

This procedure writes sensor-characteristic data into the EL3356. Use it only
if terminal-owned engineering-unit conversion was deliberately chosen in
section 4. Calibration changes are stored in terminal EEPROM; do not execute
the commands cyclically.

1. Back up all current CoE values and the TwinCAT project. A reset in the next
   step restores terminal delivery settings and can erase needed
   parameterization.
2. In TwinCAT, select the relevant EL3356 and open **CoE - Online**. Make sure
   online data, not only the offline ESI dictionary, is displayed.
3. If a factory reset is truly intended, write Beckhoff's restore signature
   `0x64616F6C` to `0x1011:01`, then reload/verify the CoE values.
4. Set `Scale factor` `0x8000:27 = 1`.
5. Set `Gravity of earth` `0x8000:26` if weight-to-force conversion needs a
   site-specific value; the Beckhoff default is `9.806650`.
6. Set `Gain` `0x8000:21 = 1` and `Tare` `0x8000:22 = 0`.
7. Set filter `0x8000:11` to the strongest level, `IIR8`, for calibration.
8. Enter the sensor nominal load in `0x8000:24`.
9. With no load and a stable value for at least 10 seconds, write command
   `0x0101` (257 decimal) to `0xFB00:01` to capture zero balance. Confirm
   `0xFB00:02 = 0` and `0xFB00:03 = 0` after completion.
10. Apply a known reference load, preferably at least 20% of nominal load.
    Enter it in the same unit in `0x8000:28`.
11. After the reading is stable for at least 10 seconds, write `0x0102`
    (258 decimal) to `0xFB00:01`. Confirm `0xFB00:02 = 0` and
    `0xFB00:03 = 0`.
12. Write `0x0000` to `0xFB00:01`, restore the required operational filter,
    and validate the whole chain.

Instead of physical adjustment, the certificate method writes rated output
in `mV/V` to `0x8000:23` and zero balance to `0x8000:25`, together with the
nominal load in `0x8000:24`. Follow the sensor certificate and Beckhoff manual
exactly.

Keep periodic self-calibration enabled unless the machine's measurement
design explicitly requires otherwise. Beckhoff enables it by default about
every three minutes; `Calibration in progress` is set while it runs. The 10 V
reference supply must already be present when the terminal starts or when
self-calibration is triggered.

## Troubleshooting

| Symptom | Checks |
| --- | --- |
| No change with load | Sensor wiring, EL9510 output, OP state, PDO link, broken bridge |
| Overrange/error | Excitation and signal limits, shorts, wrong sense wiring, overload |
| Large drift | Warm-up, loose fixture, temperature, moisture, shield/grounding, cable strain |
| Very noisy value | Shielding and routing, ground loops, filter, mechanical vibration, stable supply |
| Wrong sign | Axis identity, X software inversion, signal polarity, calibration-point order |
| Correct at one point only | Bad offset/slope, wrong units, double scaling, non-linearity or binding |
| Value jumps during calibration | Wait for steady state; do not calibrate during motion or vibration |
| Calibration works until replacement | Put required non-sensor CoE settings in the TwinCAT StartUp list and preserve calibration records |

