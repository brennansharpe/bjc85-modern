# IS-12 calibration path: reconstructed and exercised

The native driver measured a clean white sheet and downloaded the reconstructed
correction to the physical IS-12. Corrected colour charts at 90 and 180 dpi are
saved and independently decoded. The user has neither Canon's calibration sheet
nor its holder; the reference is explicitly experimental ordinary white paper.
See [acquisition evidence](is12-acquisition.md) for results and limitations.

Addresses refer to the same checksum-pinned `Bjshidrv.dll` and `BjsInfo.dll`
described in [is12-wire.md](is12-wire.md). No legacy code was executed.

## Control path and known bytes

`Bjshidrv!ssd_Entry` operation `0x400` dispatches to `0x1000c218`, which opens
the device, enters scanner mode through `0x10002ffc`, checks the head through
`0x10006859`, and invokes `0x10004863` with first argument zero. The latter
contains the white-reference prompt and measurement/cache/download paths.
This host operation value is not transmitted to USB.

The `s` branch of the fresh-reference path contains:

| Stage | Static evidence | Reconstructed outgoing bytes / expected input |
|---|---|---|
| Quiesce current operation | `0x100049ed` calls `0x10003f75`, row 2; waits for row 20 | `1b 28 73 01 00 51`; status response |
| Wait for prior paper operation | `0x10004a05` calls `0x10006677`; polls status byte 0 mask `0x10` and byte 1 mask `0x80` | Existing `R 02` status query; complete meanings of these bits need mapping |
| Request white reference from operator | `0x10004a67` passes message code `0x416`; its `0x100071f1` branch loads string resource `0x0b` | Host UI only: load white calibration sheet |
| Configure measurement | `0x10004c33` initializes five bytes; `0x10004ca6` calls `0x10003339`, row 12 | `1b 28 73 06 00 44 10 88 00 80 01`; status response; both caller and row postprocessor wait about 200 ms |
| Load reference sheet | `0x10004cc3` calls `0x10003425`; if status byte 0 mask `0x10` is clear, it sends row 6 | `1b 28 73 01 00 4c`; asynchronous status transitions and error handling |
| Measure white reference | `0x10004d59` calls `0x10005031`; `0x10005082` selects row 43 with parameters `01 07 07` | `1b 28 73 04 00 57 01 07 07` |
| Receive measurement | `0x100057df` waits for row 27 | `ESC ! S`, discriminator `c`, 12,337-byte payload; interleaved status records are possible |
| Preserve/cache measurement | `0x10005aba` copies `0x3030` bytes starting at payload offset 1 | 12,336 bytes = six 2,056-byte blocks; first reply byte is skipped by the original caller, meaning not established |
| Prepare and download correction | `0x10005b80` applies host transforms, selects a block with `BjsInfo!biCalibDwldDataGet`, then sends row 39 | `ESC ( s`, LE body length `0x080a`, token `T`, 2,057 parameter bytes; first parameter `01`, followed by transformed data; waits for status |

`0x1000ac76` determines the variable `W` parameter size: the `s` branch uses
three bytes if either parameter byte 1 or 2 is nonzero, otherwise one byte.
The generic encoder then adds the discriminator to the little-endian body
length. This is why the fresh-reference `W` request above has body length four.

The original calibration record is not an ordinary RGB image. Before download,
`0x10005bdd` / `0x10005c00` call `0x1000a28f` with a difference between the
current raw temperature and the temperature retained with cached data.
`0x10005c6a` calls `0x1000a9a5` after selecting a block. These transforms,
per-mode block selection, validity checks, and file layout were reconstructed
and implemented in `src/is12_calibration.c`. The ICC profile is not measurement
data and is not used in this path.

## Exact correction arithmetic

The BJC-85 model identifier is 23. `BjsInfo!biIsA202` (`10001d20`) returns false
for this model. Measurement byte 0 is skipped; the remaining 12,336 bytes form
six blocks of 2056 bytes, each with four 514-byte channels. Channel numbering
below is zero-based; no unverified optical meaning is assigned to these channels.

1. `Bjshidrv!10009d5e` adjusts the LE u16 field at channel offset 256 in channels
   1 and 2 of every block. Let `old` be that field, and factor be 50000 or 20000.
   Interpret the low 32 bits of `(old + 64) * -factor` as signed, divide by
   998400 with truncation toward zero, add to `old`, then retain `& 0xff00`.
2. `1000a28f` → `1000a3a9` applies raw-temperature delta to the first 128 BE u16
   words in those same channels. Subtract `signed32(delta * value * rate) / 10000`
   from each word, with rate 50 for channel 1 and 20 for channel 2. Preserve
   the original signed arithmetic and 16-bit result wrapping.
3. `BjsInfo!biCalibDwldDataGet` (`10003030`) selects block 0/1/2 for D mode
   1/2/4, corresponding to 360/180/90 dpi. The download starts with parameter 01.
4. `1000a9a5(1)` → `1000ab6e` scales the initial 128 BE u16 words of the four
   selected channels by `[82, 81, 82, 82]` percent, using integer truncation.
   These values come from BJC-85 carrier-table row `10009f62`:
   `(23, 90, 90, 90, 81, 82, 82)`. This is the original normal branch; other
   host processing modes are not silently treated as equivalent.
5. Send 2063 total bytes: `1b 28 73 0a 08 54`, then 01 and the transformed block.
   The original 100 ms pauses before/after download are retained.

The native code uses explicit wrapped 32-bit arithmetic to reproduce the x86
operations without C signed-overflow undefined behaviour. Synthetic arithmetic
checks and actual measured-data/download fixtures guard the reconstruction.

## Measurement and cache evidence

`is12-calibration-001` sent Q, D, L, and `W 01 07 07`; it received exactly 12,337
bytes in `S/c`. Status `10 02 00` accompanied measurement. The stored raw
temperature was 53; no Celsius interpretation is asserted. The full USB journal
contains 12,664 bytes, with no device error.

The native reference file has a 64-byte header followed by the unchanged
12,337-byte measurement. Header fields are: magic `IS12REF1` (0–7), experimental
paper flag 1 (8), raw temperature (9), reserved zeros (10–11), LE CRC32 of the
measurement (12–15), padded printer USB serial (16–47), observed carrier reply
(48–59), and LE measurement length (60–63).

Cache acceptance checks CRC, printer serial, the original head-class mask and
head-type byte, and a ±10 raw-temperature window, matching `10009478`. The
carrier's mode echo and mutable capability/status fields are deliberately
excluded: measurement changed them on this same cartridge. The initial exact
carrier comparison rejected scan 003 before feed or T; this was corrected before
scan 004. The printer serial does not identify an individual IS-12 cartridge,
so replacing the IS-12 requires fresh calibration.

Scan 004 accepted its complete T download at raw temperature 55, then produced
a corrected chart. Scan 006 accepted the resolution-specific table at temperature
56 following a user power cycle, then produced a corrected 180 dpi chart.

## Native stream handling

The C stream parser now supports uppercase `S` records and the full u16 length
range. It keeps outer USB framing separate from inner records, so either header
or payload can span several USB transfers and outer frames. It rejects malformed
prefixes/lengths, retains incomplete data until more input arrives, and never
reports a partial stream as complete. A synthetic 12,337-byte `S/c` record is
tested across outer frames and many USB chunk sizes. This establishes parser
capacity only; the sample contains deliberately generated test bytes.

The native CLI can decode an IN capture from disk without opening the printer:

```sh
build/bjc85-is12 decode tests/fixtures/is12-extended-status.usb
```

The hardware CLI now implements calibration, scan setup, paper load, image start,
correction download, and bounded stop handling. It journals raw acquisitions
before decoding them and creates native PNGs only for a complete page. The
successful measurements and colour scans establish more than parser capacity;
cancellation and factory-reference colour accuracy still require acceptance.

Canon's [IS-12 manual](https://gdlp01.c-wss.com/gds/2/0900007432/01/BJC85_IS12_user_manual.pdf)
describes the original white reference on pages 18–20 and 83, and holder feeding
on pages 21–23. It specifies a 0.2 mm holder, maximum combined thickness 0.45 mm,
and the envelope/down paper-thickness setting. A substitute holder/reference
would need its own mechanical and colour validation; none has been validated.
