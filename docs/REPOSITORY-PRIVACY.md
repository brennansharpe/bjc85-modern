# Repository privacy

> Current publication status and superseding verification: [publication readiness](publication-readiness.md).
> Reachable-history cleanup does not establish deletion of GitHub cached objects.

## Cleanup on 2026-09-14

The initial upload to the private GitHub repository included device identifiers
and personal environment details in historical test evidence. The cleanup covers
the working files, all uploaded commits, and the local baseline tags.

| Data | Treatment |
| --- | --- |
| One physical printer serial | Replaced with `TEST-BJC85-0001` |
| 19 distinct capture, document, job and discovery UUIDs | Replaced consistently with synthetic UUIDs in the `00000000-0000-4000-8000-xxxxxxxxxxxx` namespace |
| Local home paths, including escaped JSON paths | Replaced with `/Users/REDACTED` |
| Local account names in IPP logs | Replaced with `REDACTED` |
| Non-public Git author/committer email fields | Replaced with the repository owner's GitHub noreply address |
| Screenshot showing a local computer name | Removed from the tree and history |
| Metadata in 27 retained native UI captures | Removed without changing decoded RGB pixels; manifest hashes updated |

The public GitHub identity, generic Canon model names, standard USB vendor/product
IDs, and loopback addresses remain. Raw private scan directories, original
captures, credentials and the recovery bundle stay outside tracked content.
Historical evidence is now sanitized derivative material, not an untouched
original. Older audit reports describe the pre-cleanup state.

## Verification and limits

The audit checks tracked text and all Git blobs, commit metadata and annotated
tags reachable from branches, tags and remote-tracking refs. It checks known
original identifiers as plain text, escaped JSON,
UTF-16, Base64 and hexadecimal bytes, as well as patterns for credentials, device
serials, UUIDs, personal paths, email addresses, network addresses and local
hostnames. Binary protocol fixtures receive the exact known-value checks.
Image container metadata is checked separately to avoid treating compressed
pixels as text.

All 35 original image assets were checked locally with Apple Vision OCR. The
one capture containing a personal computer label was removed; the seven generated
presentation images and 27 remaining app captures are retained. Metadata removal
was verified by comparing decoded RGB bytes before and after. The screenshot
manifest records the sanitized files' SHA-256 hashes.

No credential tokens, private keys, MAC addresses or non-loopback private network
addresses were found in this audit. Pattern scans and OCR cannot prove the absence
of every possible form of private information. New screenshots and hardware logs
still require review before committing.

Rewriting branches removes the old material from normal clones and repository
history. GitHub may retain unreachable objects and cached commit views. Server
purging requires GitHub Support; see GitHub's
[sensitive-data removal documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).
Do not merge old clones or private recovery bundles back into this repository.

## Before future pushes

```sh
python3 scripts/check-repository-privacy.py --history --staged
git config core.hooksPath .githooks
```

The installed pre-push hook also scans the exact proposed Git ref updates, including
any unusual refs that a push explicitly selects. Local editor review snapshots
and recovery refs are outside normal branch history; use `--all-refs` to audit
those local-only backups too. They must never be uploaded.

The check reports categories and file paths,
without printing matched values. The optional `--private-values` argument accepts
a local, untracked JSON array of known identifiers; never commit that array.
`scripts/audit-source-privacy.py` is a compatibility entry point for the same check.

Run its regression tests with:

```sh
python3 tests/repository_privacy_test.py
```

Hardware replay tests no longer hardcode unique capture directory names. Set
`BJC85_COLOR_360_CAPTURE` for the 360 dpi color capture and `BJC85_BW_CAPTURE` for
the complete grayscale capture used in the one-bit output check. Defaults are
`.state/replay-fixtures/color-360` and `.state/replay-fixtures/gray-360`.
These local inputs must remain untracked.

## Local prevention and publication audits

Install without replacing an unrelated hook setup:

```sh
python3 scripts/install-privacy-hook.py
```

The tracked pre-push hook checks the index plus every actual outgoing commit/tag
and its ancestry, including new branches and annotated tags. It refuses unusual
ref namespaces. It requires a LOCAL private matching configuration; missing
configuration fails with exit 2. Hooks are local prevention, not a server-side
security boundary. Do not bypass them to publish old recovery history.

Store `privacy-local.json` **outside the checkout**, in a directory owned by you
with mode 700; the regular file must be owned by you with mode 600. Its JSON
shape is `{"schema": 1, "known_values": ["replace-with-locally-discovered-values"]}`.
Populate it privately from actual local findings. Do not paste real values into
commands, GitHub, tests, CI, reports or this document. Select its absolute path
with repository-local `git config --local bjc85.privacyConfig /private/path/to/privacy-local.json`
or `BJC85_PRIVACY_CONFIG`. The installer never changes global Git settings.
The publication audit used a populated private list retained with the private
recovery record. Configuration under the repository is rejected even if ignored.

```sh
python3 scripts/check-repository-privacy.py --history --publication
python3 tests/repository_privacy_test.py
```

Without `--publication`, generic CI scans explicitly report `not-configured`;
they are not the complete owner-specific publication audit. The checker searches
ASCII/UTF-8, both UTF-16 byte orders/alignments, and known byte/base64/hex/escaped
variants. PNG/JPEG containers and ZIP/TAR/GZIP/BZIP2/XZ archives receive bounded
inspection: 16 MiB input/member, 32 MiB expanded budget, 128 archive members,
two archive layers. Unsupported, encrypted, malformed, truncated or over-limit
inspection fails explicitly. Compressed image pixels are not treated as text;
metadata, payloads and trailing data are checked. Visual review is still required.

Exact protocol-fixture hash exceptions are explained in
`scripts/privacy-reviewed.json`; text and private-value matching still run.
Synthetic test UUIDs use the reserved `00000000-0000-4000-8000-` prefix; example
email domains, GitHub noreply attribution, loopback/documentation IP addresses,
and explicit redaction/test serials are intentional. Upstream source hashes,
USB vendor/product IDs and resource IDs are useful protocol/provenance constants.
No directory-wide privacy exception is used. A future upstream attribution
finding must be reviewed narrowly, preserving its credit rather than erasing it.

The CI workflow uses hosted runners, read-only contents permission, a pinned
checkout action without persisted credentials, synthetic regression data and a
checksum-pinned Gitleaks binary. It has no private identifier list, Mac/printer
access, signing credentials, privileged pull-request trigger or artifact upload.
Neither scanner is an exhaustive privacy guarantee.
