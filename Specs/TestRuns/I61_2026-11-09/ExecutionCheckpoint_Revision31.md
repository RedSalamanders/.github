# Historical execution checkpoint from plan revision 31

Superseded by revision 32. Pending/running statements below describe their original checkpoint only.

### Current execution checkpoint, 2026-11-11

Monitor #52 is merged as `7a9b64e067331f371b1abf780bc73b9de942383e`.
[Main run 42998339563](https://github.com/RedSalamanders/RedMonitor/actions/runs/42998339563)
passed all seven jobs, including actual x64/ARM64 Release regressions and both
production build/smoke branches. Its original local Full also passed. This is
delivered acceptance for those changes, without a controlled speedup claim.

Shared #70 merged as `766fd7e01aeef2e77ba18df83b9928516155014e` after all five
hosted checks passed. It adds the bounded, independently frozen local SDK data
descriptor reader and shared desktop admission. Root and native DxUi previously
used different mutex names. The new outer admission takes Root's existing mutex
before invoking the unchanged native DxUi lease, only for explicit interactive
entries. The vanished-foreground restoration failure remains a failure. Tilde
#108 at `438ee7fd8aa7a473a25755ae9e5e3e1c68d51149` uses the merged engine and
passed complete compiler-free validation; fresh native qualification is running.
DxUi #249's corresponding adapter is in validation. Producer capture/data readers
do not establish application linker admission, SDK qualification or a test pass.

The Root selected cold experiment at `1c17edc3` built without warnings/errors and
passed ProductUiTests, but ViewerPETests failed because its runtime ViewerVLC
producer was absent. Further inspection found six viewer plugins plus the
application/Common PE fixtures and the plugin contract roster needed explicit
project dependencies. Root #219 at `444d6a28e` declares those runtime inputs,
with nine focused project-selection controls and final ownership/format checks
passing. Corrected cold native acceptance remains open. An actual viewer union
includes the application when its tests inspect that PE input; the earlier
assumption that the application must be absent was wrong. Do not weaken existing
fixture assertions or count the failed experiment as a selective-build pass.

A separate ProductUi-only public affected run at `51501104b` stopped during pinned
DxUi restore before native test execution: vcpkg could not read a versioned helper
at a 260-character path. A shorter isolated fixture is prepared as a diagnostic;
path length is not yet a confirmed cause. Preserve this failure independently.

The following rollout paragraphs retain earlier checkpoints; newer source-bound
facts above take precedence over their pending statuses.

Current rollout: Monitor #50, Tilde #106, Prism #18 and DxUi #246 are merged.
Monitor main42950834765, Tilde main42952565762 and DxUi main42954632514 passed
all seven jobs. Prism main42959845076 passed x64 regression but failed ARM64:
`paste-exhaust` reported a clipboard-work acknowledgement failure, followed by the
unchanged 5,400-second watchdog. Production was skipped. Preserved stdout/stderr
identify the failing scenario; they do not establish a root cause. These are ordinary main results; optional shadow tooling grants no
additional acceptance. Do not cancel running Actions.

Shared #64/#65 merged the canonical actual-engine input reader and Windows path
casing correction at `0573d4f3b294e3c3655349eb618ec7105b3d89b2`. All 120 local
engine controls and all five hosted checks passed. Product Git ignores `.ci-engine`,
so its actual implementation must be bound separately before local receipt reuse.
All six client ports are committed and published as drafts: Root #217, Xe #87,
Monitor #52, Tilde #108, Prism #20 and DxUi #248. Focused integration checks pass;
DxUi's complete tooling validation also passes, including historical paired-reader
controls preserving each side's original engine/pin. Their current native acceptance
remains open. Keep engine
identity separate from product file/iteration maps. This closes an input hole; it
does not replace a gate or grant a test result.

Root's current Source recipe passed all six builds with zero warnings/errors;
PR #213 retains exact source/profile evidence. Its later local-origin SDK Full
finished **FAILED: 2815 passed, 3 failed, 56 skipped**, with 15 of 18 promoted entries.
The tooling fragment is fixed in #213. The ViewerPE close-time and interactive
restoration failures remain unexplained. Quiet diagnostics passed three close
attempts (37/36/36 ms against the unchanged 500 ms budget) and all six interactive churn
cycles with verified restoration. Those passes neither repair nor supersede the
original Full. Root #215 reduces repeated unsafe-archive inspection; #216 permits
exact verified entry continuation from a closed failed/interrupted Full. Both are
drafts with focused integration controls, not complete native acceptance. Entire
approval for #211 remains absent. Source Release Fresh Full at
`03fe8ee22db0407643fb2803a1e974660ae5656d` with engine `0573d4f3` completed with
exit zero, **2,828 passed, zero failed, 56 skipped**, all 18 entries promoted and a
stable passed evidence seal. The Source build has zero warnings/errors. The
[curated original-result index](../../TestRuns/I61_2026-11-09/Root_Source_Full_2026-11-11.json)
binds its original summary hash and scope. This is local x64 Source acceptance;
the prior SDK failure, hosted qualification, ARM64 runtime and controlled overall
targets remain separate. After its actual process drain, the serial sibling queue
started. Monitor's canonical local Full passed at `3d47b6fc`; #52 merged as
`7a9b64e067331f371b1abf780bc73b9de942383e` and main qualification 42998339563
is running. Tilde is executing next; Prism and DxUi remain queued. Queued or running
work is not a passed result.

Xe #83/#84/#86 remain drafts: measurement input closure, contained metadata transport
and independent-tooling retention are included in #87 and focused checks pass. The
original Desk Clock memory-budget failure remains failed; later diagnostics do not
establish its cause. Monitor's remaining independent-check retention port is now
implemented with create-only attempts and failure/interruption invalidation; its
complete independent tooling passed. One fresh/reuse pair measured 105,615/2,248 ms
on unchanged inputs, with another build active: this is limited local cost evidence,
not controlled overall acceleration acceptance. Root #218 adds a single-operation
native project union and exact partial receipt admission for selftest-only routes;
238 integration controls and a real compiler-free MSBuild union fixture passed.
Root #219 at `51501104b9bbe4d365e747920b2517d65d9cf5c9` then moved governed
affected selection before compilation: explicit producer/runtime unions may serve
targeted iteration, while unknown/shared inputs, artifact writers and incomplete
bindings retain the full build. Fresh Full/PR/CI/Resume gates remain. No-build,
zero-entry prose/empty changes now avoid native work, its profile lease and historical
scavenging; applicable ownership checks and a source barrier precede diagnostic-only
archival and NOT_EVALUATED exit 2. All 262 integration controls passed. Actual public
prose and malformed-fragment controls passed in an independent checkout without any
compiled profile, with native builds disabled; [scope and original artifact hashes](../../TestRuns/I61_2026-11-09/Root_Affected_CompilerFree_2026-11-11.json)
retain the evidence. No native result is inferred. Actual cold native union/affected
checks and the remaining Xe profiles are queued serially after the existing native
campaigns; any failure stops the dependent tail. Native cold-build/timing acceptance
remains open. Remaining selected builds, local candidate SDKs, finer
native/case closure, controlled acceleration/detection measurements and rollout keep
this plan WIP. Earlier checkpoints below remain history, not current acceptance.

