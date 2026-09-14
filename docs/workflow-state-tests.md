# Workflow contracts and controller tests

The controllers use identified attempts and injected boundaries. UI state is
projected on the main actor; blocking service commands, image work and job
queries run on a serial worker. The original ARM64 acquisition, calibration,
readiness checks, byte accounting and cancellation barriers remain the engines.

## Copy and cartridge transactions

| Stable state | Available next step, subject to device safety |
|---|---|
| Empty | Connect/revalidate scanner, acquire original with valid Copy settings |
| Scanning | Cancel acquisition; no Reset or second acquisition |
| Awaiting print cartridge | Review/edit retained document, confirm swap, or release Copy session |
| Ready to print | Explicit Print retained copy; correct inline settings; prepare printing again if needed |
| Printing | Specific job cancellation and queue details; no replay or Reset |
| Reprint ready | Explicit Reprint retained copy with current settings, edit, or release Copy session |
| Job unknown | Recheck exact queue reference and inspect evidence; no automatic retry or Reset |
| Recovery required | Inspect device/evidence; protected image stays retained; no force-continue action |

`ScanOperationController` gives each scan a UUID and optional Copy attempt ID.
Preflight refusal, canceled preflight, helper launch failure and process exit all
use its shared completion path. Only a matching current attempt can retain an
image or stop Copy. A later ordinary scan cannot inherit a stale Copy attempt.
Known refusal before helper launch rolls back the coordinator's prior state and
keeps the document. Busy does not imply disconnection.

Opening a cartridge sheet does not mutate the device state. Cancel with no
physical change preserves existing evidence of readiness. “Changed cartridge /
unsure” invalidates readiness and requires a connection check or fresh print
confirmation. Confirming the print cartridge prepares services, then exposes an
explicit Print action; it does not automatically submit the copy. A preparation
failure remains retryable without claiming the physical cartridge is unchanged.
Invalid copies/media never consume the retained image. Fields revalidate as
they change. Buttons, toolbar and menus share capability validation.

## Admission, services and recovery

The cross-process admission lock is separate from the exclusive USB lock.
Native jobs take shared admission for their lifetime; service transitions take
exclusive admission across idle checks and mutation. Lock order is admission,
then USB. Parents never hold the USB lease while synchronously waiting for a
child that needs USB. eSCL holds admission from accepted request through child
startup/finalization; PAPPL holds it through raster/transfer processing.

`SharedDeviceState.inspect` checks both locks even with no recovery marker.
Permission errors, malformed markers, symlinks and unreadable state fail closed.
Availability is observational; native USB admission remains the final authority.
An exclusive transition blocks new native admissions, pauses only the verified
utility queue, and checks again for queued work. It never clears another client's
jobs. An active eSCL job refuses quiescence instead of being killed.

The new eSCL `/utility/idle` endpoint is a read-only transition handshake. A
previous installed service without this handshake refuses a transition; an idle
service upgrade must be performed deliberately. This session did not install or
stop production services. Native recovery markers and existing journal formats
are retained; queue state cannot clear them.

## Job truth and restart

`PrintJobTracker` writes a submission-intent journal before `lp`, then records
destination, exact ID, attempt, document and revision. `bjc85-job-query` uses
CUPS IPP Get-Job-Attributes for that job and verifies its destination. Completed,
canceled, aborted, rejected, pending and unknown have different labels.
Disappearance from `lpstat -W not-completed` is never a success signal.

A known refusal before acceptance is retryable. An ambiguous submission failure,
timeout, missing/purged history or failed query is unknown; no automatic replay
is permitted. Restart queries an outstanding job and never resubmits it. Job
cancellation itself is not terminal evidence. A canceled terminal job plus idle
safe device state permits an explicit retry; an unsafe physical outcome requires
recovery even when the queue says canceled or completed. “Queue reports
completed” still requires inspection of the paper, especially given the known
black-ink delivery fault.

## Executed regression coverage

`sh scripts/test-hardening.sh` runs four native executables, compiling the actual
app controllers with `BJC85_TESTING`. It does not substitute a production-success
stub. Results: [hardening-tests.txt](verification/macos27-hardening/hardening-tests.txt).

| Test file | Exercised boundary |
|---|---|
| `workflow_controller_test.swift` | Actual scan controller: busy, timeout, failed quiescence, launch failure, canceled preflight, duplicate/stale completion, subsequent normal scan |
| Same | Actual window-controller actions: refused Copy preflight, corrected settings and action availability, fixture guard; safe canceled job versus canceled-after-transfer recovery projection |
| Same | Copy/coordinator unchanged versus uncertain swap cancellation; rejection/retry, reconnect, reprint, recovery/reset protection |
| Same | Injected queue: completed/canceled/aborted/unknown, submission/query failures, pending restart and duplicate callbacks without replay |
| `service_transition_test.swift` | Actual service controller with injected commands: busy lease, pending queue, active scanner, timeout, failed bootstrap and successful isolated transition |
| `shared_device_state_test.swift` | Marker absent/present contention, finalization, malformed/symlink/permission failures, shared/exclusive admission/release, stable private discovery identity |
| `document_pipeline_test.swift` | Document/export ownership, aliases, failure/cancellation, cleanup/Copy/recovery protection and restoration; 2D image contract |

`tests/usb_lease_test.py` additionally runs the real native helper against private
temporary lock/state paths, with its offline USB guard active even after lease
release. Existing C fake-USB tests exercise wrong heads, startup/finalization,
cancel barriers and persistent recovery under ASAN/UBSAN. Isolated service tests
run fake eSCL children and PAPPL `--dry-run`, never installed queues or launchd.

`BJC85_OFFLINE_TEST=1` blocks production service adapters and libusb access.
`--fixture`/legacy `--preview` independently disables production UI adapters and
uses isolated storage. Test path overrides are accepted by native locks only
with the offline guard. Models do not fabricate successful production outcomes.

These are controller/transport/fixture tests, not observed physical cancellation,
queue delivery or cartridge changes. The full physical sequence is separately
listed in [opt-in physical acceptance](physical-acceptance-plan.md). The unlocked
fixture UI checks verified retained Copy edits and correction of invalid copies,
native PNG/TIFF/PDF exports, managed-storage rejection and close/reopen restoration.
Keyboard focus, Settings Command-W and small-window auto-scroll were checked in
the running app; see [the UI audit](macos27-ui-ux-audit.md) for screenshots and
the remaining VoiceOver/Inspector limits.

The controller suite also asserts that a synchronous service refusal keeps its
terminal error text instead of being overwritten by preparing progress. A busy
lease updates both the visible and accessible last-check label while preserving
scanner readiness. The constructed accessibility suite checks that focus scrolls
an offscreen inspector control into view and that zoomed canvas drawing is clipped.
