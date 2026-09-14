# Repository privacy

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
