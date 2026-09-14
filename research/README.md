# Canon research boundary

Original Canon software and extracted assets are interoperability/design research,
never runtime dependencies. Originals are byte-identical, hashed and read-only;
extractions go to separate ignored directories. No Canon executable, embedded
decompressor or proprietary artwork is executed/bundled by the native release.

The existing originals remain under `artifacts/original/`; they have not been moved
or normalized. The new handover copy is under `research/original/`. Hashes and
acquisition status are in `manifests/provenance.json`.

Reproduce the bounded resource inventory with:

```sh
python3 scripts/index-classic-resources.py artifacts/extracted/canon-mac-classic/payload research/extracted/classic-resource-index
```

This produces raw resources, decoded DLOG/DITL/MENU/STR/STR# records, hashes, and a
CSV of UI items. It parses data only. Installer resources must not be mistaken
for the IS Scan application's UI. The opaque `IS Scan file` and `CommonFile`
containers still require further static format analysis.

The handover's archive catalogues are leads, not verified downloads. The printer
driver and Copy Utility pages currently point their named file links to a third
party redirect; the HelpDrivers download form includes a CAPTCHA. Missing
packages remain `not_acquired`, with no invented hashes or redistribution claim.
