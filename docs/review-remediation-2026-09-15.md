# Review remediation — 2026-09-15

This record covers the supplied review of the public SOURCE ALPHA and tests of
current production Swift/Python/C sources. It does not qualify hardware, every
supported macOS version, VoiceOver, licensing or binary distribution.

## Dispositions

| Finding | Disposition and evidence |
| --- | --- |
| PUB-01 owner metadata | Confirmed remotely. A verified owner-only backup preserves history, refs and working changes. A local replacement changes only the owner's author email, preserving tree, parent, dates, message and committer; its invalidated GitHub signature is omitted. Remote history repair and publication are externally blocked by missing authenticated Git transport (CLI signed out; verified-host SSH returns public-key rejection). No contaminated branch is pushed. |
| PUB-01 service false positive | Fixed: only exact `noreply@github.com` joins existing public noreply exceptions. Synthetic positive/negative controls retain personal-author detection. |
| PUB-02 publication claims | Fixed documentation. The original privately mapped capture was retrieved with authentication; a separate anonymous HTTPS request also returned its non-synthetic printer identifier. Advertised cleaned refs do not establish server erasure. This is identifying metadata of low severity, not a credential. No support request, support resolution or owner acceptance is claimed. |
| PUB-03 CI/protection | Three independent hosted jobs are defined: `privacy`, `gitleaks`, `macos-offline`. macOS compiles the complete production entry point and runs offline suites. Hosted results and protection remain externally blocked pending safe history repair and authenticated push. Existing main has no protection/rulesets; none was weakened. |
| PUB-04 historical names | Fixed: byte-safe historical tree traversal checks directory/full paths and ref names separately from blob deduplication, with explicit bounds/failures. CLI regressions cover rename/deletion, reused blobs/subtrees, Unicode/whitespace, index, new branches and tags. |
| APP-01 store availability | Source-derived issue repaired and fixture-tested: store attachment precedes maintenance; corrupt entries and deferred imports are reported while healthy pages remain available. Quotas count partial/corrupt entries and retained bytes. Damaged Copy/print state restricts physical work without synthesizing an empty tracker. |
| APP-02 pre-submission receipt | Reproduced review case repaired against actual tracker. Durable rollback precedes explicit retry; injected failures before write, after replacement, attributes and sync produce zero submissions. Possible queue acceptance retains unknown/no-replay behavior across restart. |
| APP-03 queue ownership | Reproduced review case repaired through actual transition controller with mocked commands. Canonical URI only, explicit absent-queue diagnostics, repeated ownership/idle/error check before reconfiguration. Near matches make no initial mutations. |
| APP-04 persistence recovery | Source-derived latch replaced by per-resource generations and retry closures, including document and active-session transitions, Copy and reference settings. Tests exercise stale/unrelated completions, queued writes, failed Quit, repaired Quit, the actual window-close notification and nonfatal restoration warnings. |
| APP-05 raster preflight | Source-derived ordering issue repaired. Container dimensions and ImageIO metadata are checked before eager decode, then decoded output is revalidated. Same immutable input snapshot prevents source replacement between checks and decode. Decoder spies reject tiny oversized/malformed fixtures without allocating an oversized raster. |
| Capture intent | Versioned host intent is saved beside the helper-owned directory before launch. Stable document identity, acquisition/edits, prescan and Copy association survive import/receipt interruption; repeated recovery never resubmits physical work. Legacy orientation remains unknown, rather than applying an unjustified rotation. |
| Copy crash ownership | Session is authoritative; ownership markers reconcile after readable job/recovery checks. Stable legacy migration identity prevents repeated PDF imports. Outstanding/unknown jobs retain protection; safe orphan markers can be released without deleting masters. |
| Export-receipt expiry risk | Automatic retained-master expiry removed. Past, missing, changed or inaccessible exports never trigger deletion. Explicit confirmed Discard remains, with worker/Copy/unknown-operation guards. Diagnostics and eSCL lifetimes remain separate. |
| Clean-machine prerequisites | Pinned libusb setup is separate from offline execution. Explicit rebuilt dependency prefix is supported. Isolated service tests now create an ephemeral bridge with an inert child instead of falling back to a live port, and generate synthetic URF fixtures. |
| OS/accessibility scope | Existing deployment target, physical limitations, README story, AppKit/C architecture, provenance and licensing boundary preserved. No new runtime/hardware/accessibility acceptance claimed. |

## Validation record

The original Swift evidence harnesses contain embedded reviewed copies; they were
read as reproduction evidence, not used as repair verification. New regressions
compile the current production files. Swift assertions remain enabled, including
optimized test builds. Native tests use fake transport or bounded committed
fixtures. Document/recovery runtimes are disposable; no installed service or queue
is a test target. Swift runners now also inject temporary admission and USB-lock
paths, including state inspection during Copy reconciliation. Earlier iterations
exercised the default lock-file path; no USB command or live runtime migration
occurred. Final verification uses isolated lock paths throughout.

Executed on Apple silicon with the installed Swift 6.4 development/Xcode
compiler in Swift 5 mode, targeting macOS 14:

- `scripts/test-source-alpha.sh` in a source-only candidate: 9/9 C tests,
  seven existing Swift model/UI suites, five hardening suites (including the new
  review regressions), and compilation of the complete production application.
- CMake Debug build with `-fsanitize=address,undefined`: 10/10 native tests,
  including the available Gutenprint capability check; no sanitizer finding.
- `scripts/test-hardening.sh` against the final source snapshot: review repairs,
  document pipeline, workflow controller and service transitions passed. The
  expanded review suite covers intent-before-launch failure, top/bottom intent,
  Copy migration interruption at three boundaries, and protected unknown jobs.
- Isolated service suite: six fake eSCL outcomes, restart journal guard, seven
  HTTP rejection cases, synthetic PAPPL/Gutenprint dry-run acceptance, restart
  and recovery gates passed. No installed service port is used.
- Full-size synthetic 2880×3888 processing: sharpen/TIFF export about 1.25 s,
  63 main-loop heartbeats with a maximum gap about 24 ms; decode/despeckle about
  2.39 s. Pins, immutable revision and obsolete-preview cancellation passed.
- 15 synthetic privacy regressions passed. The final source-only candidate's
  populated publication/index/history check passed. Gitleaks 8.30.1 tree and
  history scans found no leaks in that candidate. The actual reviewed personal
  author remains detected, while GitHub's service committer is accepted.

These are local fixture/source results. The original reviewed remote history
still contains the personal-author finding, despite the clean local candidate.
Some fixture AppKit tests emit a sandbox notification-service warning; assertions
and exit status passed. The benchmark's privileged `time -l` counters were
unavailable; timing/heartbeat measurements come from the test itself. No peak
process-memory measurement is claimed.
The reviewed failing hosted privacy run remains historical evidence; it is not
removed or relabelled as passing. Current local checks do not imply hosted checks
passed.

## External completion steps

1. Establish an approved authenticated Git transport for this exact repository.
   Reinspect all remote refs and compare the expected reviewed main SHA privately.
   Stop on concurrent advancement. Push only the prepared metadata repair using
   an explicit expected-SHA lease, after the complete outgoing privacy check.
2. GitHub Settings → Emails → **Keep my email addresses private** was enabled
   through the signed-in owner browser on 2026-09-15. The resulting UI showed
   both this setting and **Block command line pushes that expose my email**
   checked. This protects future commits; historical correction remains pending.
   Local noreply configuration alone does not control web-created commits.
3. Push the clean repair branch and open a PR; inspect its exact remote commit
   and all three hosted checks. After they pass, require a PR and those exact
   check names on `main`, with zero mandatory independent reviewers for this solo
   repository, no routine owner bypass, no force pushes or deletion. Preserve any
   stronger controls added concurrently. Merge only after required checks pass.
4. Make an explicit owner decision on the low-severity retained printer identifier
   or request conditional GitHub Support assistance. No server-side erasure or
   owner acceptance is implied by cleanup of advertised refs.

[GitHub standard runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
was checked for the standard Apple-silicon `macos-26` label. Paid/larger runners,
self-hosted execution, signing, binary uploads and releases are not enabled.

## Source map

| Items | Production / regression files |
| --- | --- |
| PUB-01, PUB-04 | `scripts/check-repository-privacy.py`, `tests/repository_privacy_test.py` |
| PUB-02 | `docs/publication-readiness.md`, `docs/GITHUB.md`, `THIRD_PARTY.md` |
| PUB-03, build prerequisites | `.github/workflows/privacy.yml`, `scripts/setup-source-alpha.sh`, `scripts/test-source-alpha.sh`, `scripts/test-swift.sh`, `scripts/test-hardening.sh` |
| APP-01, capture intent, disposal | `app/ScanDocument.swift`, `app/CaptureIntent.swift`, `app/ScanOperationController.swift`, `app/ScanActions.swift`, `app/UtilityWindowController.swift`, `tests/document_pipeline_test.swift`, `tests/review_repairs_test.swift` |
| APP-02 | `app/ReceiptStorage.swift`, `app/PrintJobTracker.swift`, `app/PrintActions.swift`, `tests/review_repairs_test.swift` |
| APP-03 | `app/ServiceTransitionController.swift`, `tests/service_transition_test.swift` |
| APP-04 | `app/PersistenceStatus.swift`, `app/DocumentActions.swift`, `app/PrintActions.swift`, `app/UI/UtilityControls.swift`, `tests/review_repairs_test.swift` |
| APP-05 | `app/RasterImport.swift`, `app/ScanDocument.swift`, `app/ImageProcessingService.swift`, `tests/review_repairs_test.swift` |
| Copy crash recovery | `app/CopyOwnership.swift`, `app/CopyWorkflow.swift`, `tests/review_repairs_test.swift` |
| Lifecycle guidance | `docs/document-lifecycle.md`, `docs/USER-GUIDE.md`, `app/UI/UtilitySettings.swift`, `README.md` |
| Service/processing isolation | `scripts/test-isolated-services.sh`, `tests/isolated_http_runner.py`, `tests/make_urf_fixture.c`, `tests/ipp_dry_run_test.py`, `tests/escl_http_test.py`, `tests/escl_recovery_test.py`, `scripts/benchmark-processing.sh` |
