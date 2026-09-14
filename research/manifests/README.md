# Provenance fields

`provenance.json` records source URL, local path, byte length, SHA-256, retrieval
time when known, research purpose and acquisition status. A local hash pins bytes;
it does not independently authenticate a proprietary installer.

`resource-index.json` is a metadata-only index. Decoded labels, geometry, raw
payloads and images stay in ignored research storage. Modern UI source uses the
manual-derived feature map in `docs/legacy-ui-map.md`; unknown application resource
IDs remain TBD. No resource payload is included in release packaging.
