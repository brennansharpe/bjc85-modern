# IS-12 wire reconstruction, September 13, 2026

This combines static interoperability evidence from the preserved IS Scan 3.50
package with the first native USB status experiment. Identification and status
are verified; calibration and image acquisition are not. No legacy code is
executed. All addresses below are virtual addresses at the DLL's preferred
image base `0x10000000`.

## Model and transport selection

`BjsInfo.dll` SHA-256
`eee85b17967c895fbc410337338d2c947eafcd4e2bbf04faf326b25d794b6ba3`
maps `BJC-85` at `0x1000d15e` to model ID 23. `biSetScannerCommandType`
(`0x10001f20`) selects the 18-byte model row at `0x1000d8ee`, whose fields are
`23, 1, 0, 11, 12`. The nonzero command type selects the `s` family; the `x`
family belongs to other paths and is not selected for this printer.

`Bjshidrv.dll` SHA-256
`31f8a384505f05da9c2d21215ec70d536e99cb6fdaca18f4b049b9e37d904afc`
loads `BjsUsb.dll` and its `InitializePortManager` table. Its `0x10009088`
wrapper calls table slot +0x14 for writing and `0x100090bb` calls slot +0x18
for reading. These are host callbacks, not packet opcodes. The native replacement
uses the observed printer interface's bulk OUT 0x01 and IN 0x82.

## Encoder and minimal information sequence

The 54-entry packed command table begins at `Bjshidrv!0x10012130`; entries are
24 bytes: host selector (u16), prefix pointer (u32), prefix length (u16), signed
parameter size (i32), discriminator (i32), preprocessing and postprocessing
callbacks (u32 each). `0x1000be07` constructs the wire record. For nonnegative
parameter sizes, the two-byte little-endian length includes the discriminator
when present. Host selectors are never sent as opcodes.

| Action | Evidence | Outgoing bytes | Expected reply |
|---|---|---|---|
| Enter scanner command mode | host row 0; `0x10002ffc` sends it and waits for row 20 | `1b 5b 4b 02 00 00 0d` | `ESC ! s`, discriminator `s`, 3 bytes |
| Carrier/head information | `0x10006af5`: row 14, argument 0; expects row 16 | `1b 28 73 02 00 52 00` | `ESC ! s`, `c`, 12 bytes |
| Scanner information | `0x10006c87`: row 14, argument 1; expects row 18 | `1b 28 73 02 00 52 01` | `ESC ! s`, `i`, 9 bytes |
| Current status | `0x100039f2`: row 14, argument 2; expects row 20 | `1b 28 73 02 00 52 02` | `ESC ! s`, `s`, 3 bytes |
| Raw temperature | `0x10004f59`: row 14, argument 3; expects row 37 | `1b 28 73 02 00 52 03` | `ESC ! s`, `t`, 1 byte |
| Extended information | `0x10006d7a`: row 14, argument 4; expects row 24 | `1b 28 73 02 00 52 04` | `ESC ! s`, `e`, variable; 18 bytes observed |

The original mode-entry path waits approximately 200 ms in its postprocessor and
another 200 ms before reading. These operations do not include the scan/feed,
white-calibration, or calibration-download entries. Those operations were later
implemented separately; see [is12-acquisition.md](is12-acquisition.md).
Entering scanner mode is a state change, not a USB descriptor read.

`0x100016e3` reads an outer two-byte **big-endian, inclusive** record length,
subtracts two, and buffers the body. `0x100014b2` parses the inner `ESC ! s`
record and its **little-endian** payload length, including the one-byte
discriminator. Multiple inner records can be buffered. `ESC * s` records are
also present in the table. **Correction from acquisition tracing:** `ESC ! e`
carries a two-byte signed BE line advance without a discriminator, not error
bytes. Positive advances finish image lines and negative advances rewind between
RGB planes. This is now verified by two full uncompressed colour acquisitions.

## Cartridge checks

`BjsInfo!biIsScannerHeadPuton` (`0x10002d80`) in the `s` branch requires
`information[0] & 0x60 == 0x60`, `carrier[0] & 0xe0 == 0xa0`, and a separate
host error/change flag to be clear. `biIsScannerHeadValid` (`0x10002e30`) routes
model 23 to `0x10002e73`, accepting `carrier[11] == 0x0e`. It rejects 0x4e and
other values for that model. The prototype reports whether the returned bytes
match these checks; it does not yet recreate all host error/change handling.

The IS-12 descriptor/class-status baseline is unchanged from BC-11e, including
`STA:10`. See `usb-is12-baseline.json`. USB class status alone is insufficient
for cartridge detection.

Full extracted table metadata is kept locally in the ignored
`artifacts/analysis/is12-command-tables.json`. `scripts/inspect-pe.py` provides
bounds-checked, read-only PE32 address, import/export, and string inspection.

## Native hardware result

The user installed the IS-12. The CUPS queue was paused and its login print
service stopped before this diagnostic. Native ARM64 `bjc85-is12` transmitted
mode entry and selectors 0–2, exactly 28 bytes, each fully accepted without retry.
The raw USB IN data used exactly the outer and inner framing reconstructed above.
The complete record is [is12-first-status.jsonl](is12-first-status.jsonl).

| Reply | Raw payload |
|---|---|
| Mode-entry acknowledgement, `!s` | `00 00 00` |
| Asynchronous status, `*s` | `00 08 00` |
| Carrier, `!c` | `b0 01 0e 80 01 00 00 0b 40 00 10 0e` |
| Information, `!i` | `70 19 11 01 1f 01 68 0b 88` |
| Requested status, `!s` | `00 08 00` |

The carrier/information bytes pass all three implemented byte checks, including
the model-specific IS-12 identifier `0x0e`. This demonstrates native bidirectional
scanner communication and a positive head match. It does not establish that the
scanner is calibrated or ready to acquire an image. The diagnostic sent no feed, scan, calibration, reset,
or automatic exit commands. The scanner remains in scanner command mode.

### Warm-up and additional queries

`0x10003c1f` tests status byte 1 mask `0x08` and calls `0x10007552(1)` while
it is set. That function opens the `PREHEAT` dialog (`0x10012038`); the dialog
resource reads "Warming up scanner cartridge." The bit cleared in the next
[status experiment](is12-status-after-warmup.jsonl), with both an asynchronous
`*s` update and requested `!s` reply returning `00 00 00`. This is evidence of
warm-up completion, not of calibration.

The [extended query experiment](is12-extended-status.jsonl) returned temperature
raw byte `34` (52 decimal); its unit has not been established. Extended
information returned `01 0f 00 81 00 c8 00 b4 82 00 c8 01 68 83 01 2c 01 68`.
The original postprocessor `0x1000b3c4` handles 6- or 18-byte records and swaps
the two big-endian u16 values in each five-byte subrecord beginning at offset 3.
Observed subrecords are `81/200/180`, `82/200/360`, and `83/300/360`; their full
selection semantics are not yet exposed as supported scan modes.

The final [streaming-parser hardware check](is12-stream-status.jsonl) received
all five expected replies in about 0.8 seconds, with warm-up clear. Successful
zero-length IN packets are treated as idle observations. Each request has a
five-second reply deadline; matched, complete responses finish after a short
quiet interval. There is no retry after a partial write or malformed stream.

Additional status meanings were traced through `0x1000670d`, the message-code
switch in `0x10006f38`, and its string resources:

| Status condition | Driver message code / string ID | Meaning in that path |
|---|---|---|
| Byte 0, mask `04` | `410` / `5` | Low scanner LED light |
| Byte 1, mask `10` | `411` / `6` | Low battery |
| Byte 1, mask `40` | `412` / `7` | Unrecoverable scanner error |
| Byte 1, mask `80` | `40e` / `3` | Paper jam |

These errors are clear in the observed all-zero status. Other masks and the
complete transition/error policy remain unfinished. The partial calibration
control path is recorded in [is12-calibration-trace.md](is12-calibration-trace.md).

The initial five CTest checks passed under AddressSanitizer and UndefinedBehaviorSanitizer.
`tests/fixtures/is12-captures.json` records hashes for three raw IN fixtures
extracted from the byte logs. Stream tests replay those fixtures in chunks from
one byte through 65,535 bytes and test an independently constructed calibration-
sized record split across outer frames. Malformed or incomplete streams and
callback rejection cannot be reported as complete.
To inspect the request plan without opening USB:

```sh
build/bjc85-is12 plan
```

With IS-12 installed, print service stopped, and queue paused, the status command
is `build/bjc85-is12 status --scanner-installed`. Add `--enter-scanner-mode`
only when entering that mode. Every request and reply is logged as JSON lines;
partial writes or malformed replies stop the diagnostic without automatic replay.
