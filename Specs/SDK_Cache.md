# Immutable dependency SDK inputs

Status: immutable storage, pinned producer/distribution and explicit application-reader mechanisms are implemented.
Every consumer retains its own integration, native, production and runtime acceptance
under its owning contracts. Current deployment, failures, local-candidate work and
controlled acceleration acceptance are tracked in
[I61](Plans/WIP/TestingAndIntegrationAcceleration_2026-11-09.md).

## Explicit pinned native SDK producer

Raw checkout acquisition is centralized in `Ci.SourceInputs.psm1`'s
`Get-CiCheckoutContentIdentity`. The existing SDK bootstrap entrypoint
`Get-CiSdkCheckoutContentIdentity` remains a thin compatibility route to that exact
ordinal path/raw SHA-256 projection, including fresh no-follow and missing-file
checks. Moving the implementation grants no new SDK admission or producer trust.

The qualified producer's final ABI metadata query must select the same native compiler host as its
library build: x64 on x64 and arm64 on ARM64. Pass that property explicitly because historical source
props can override an environment default. Resolve the corresponding native MSBuild executable
(`Bin/amd64` or `Bin/arm64`); selecting legacy `Bin/MSBuild.exe` is not equivalent metadata acquisition.
Native SDK checks and the final host guard remain required. A failed reference publishes no reusable input.
Native SDK jobs have the explicit stable name `sdk (<platform>, <runner>)`. The artifact verifier requires
that exact architecture/runner identity; automatic matrix-key enumeration order is not an identity contract.
Changing matrix data order must not change names or broaden the verifier's native execution checks.

The `sdk-inputs.yml` reusable workflow is a read-only, explicitly dispatched DxUi-main dependency-input
role. `Policy/sdk-producer.json` owns exact reviewed source/API pins, producer-tooling snapshot and its
storage-engine pin. Source, producer tooling and controller code are separate checkouts. Every actual
checkout must match its full expected commit, remain clean and retain the exact source API; producer
tooling must already be an ancestor of its normally integrated main before native setup. Unsupported
sources, repositories, events or refs refuse. This is never a PR or scheduled native build route.

Policy also freezes the full raw source, tooling and storage-engine content identities of canonical Windows checkouts
(`core.autocrlf=true`, with each version's attributes taking precedence). The controller verifies these
bytes before importing producer code. Its small bootstrap hash adapter deliberately mirrors the SDK's
ordinal path/raw SHA-256 map: invoking unverified producer code to establish its own trust would be circular.
Full checkouts are required; sparse, missing, reparse or mutated inputs refuse, including mutations hidden
from Git status or preserving file size and timestamps. Other checkout bytes remain different identities;
existing receipts are never relabeled to match this canonical producer.

The producer supports only pinned Release/MD/stdcpplatest/full GL-LTCG/enabled-annotation SDK inputs.
It preserves each original source/dependency pin, uses the reviewed producer's existing build/profile/
zero-warning/process guards, and executes every SDK extraction/header/license/symbol/warning control
on the architecture's native hosted runner before byte publication. The complete stored payload must
match its independently held pre-archive snapshot. Generic storage remains data-only and grants no verdict.

Manual platform selection is All, x64 or ARM64. Each archive has independent native SDK proof; a failed
architecture can be retried without rebuilding a passed architecture. A selected producer is not full
product qualification. Immutable artifact names bind source, platform and workflow attempt. Consumers
still independently verify the trusted producer workflow/ref/source/run/attempt and transport digest,
complete actual input key and full entry manifest/bytes before use. A missing artifact/access/profile is
source fallback. No token writes, main-state advancement, merge approval or product publication occurs.

Only SDK projects receive the manual SDK-input caller template. Application callers retain their
independent native regression, production, packaging, sanitizer and interactive obligations.

## Authority and identity

`Tools/Modules/Ci.SdkCache.psm1` stores dependency bytes. It grants no test, merge, SDK qualification,
production or publication result. An input key is not a promise of reproducible output bytes: multiple
immutable output versions may exist for one input identity, and readers select a particular version by
an independently retained full manifest SHA-256. Never trust a digest supplied only by the same mutable entry.
Hosted callers must verify the trusted producer workflow/run/attempt and artifact digest before accepting
that descriptor; local callers retain their separate owned producer descriptor. These producer checks are
not implemented by the generic storage layer.

The strict identity schema binds exact source repository, commit, raw source bytes and API revision;
platform/configuration, CRT, annotations, language/optimization policy; full toolchain, evaluated compiler
profile, installed dependencies, integration policy and environment identities. Producers must acquire
those identities from actual inputs with before/after barriers. Strings supplied by an unverified manifest
cannot establish that acquisition. Native producer/admission must also prove the actual archive architecture,
headers, symbols, licenses, imported policy and linker provenance. These native gates remain open.

Version 1 accepts pinned Release/MD, enabled annotations, stdcpplatest and full GL/LTCG inputs only.
Debug, ASan, local candidate and other policy variants use existing source builds until separately implemented;
they cannot be relabeled as a supported cache profile. All native product tests and production smoke remain.

## Storage ownership and transactions

New stores initialize only in a repository's `.build` descendants. A marker records ownership; nonempty unowned
directories, drive roots and reparse paths refuse. Readers may use an already marked shared store. Both input
and output short locators verify their complete identities. Manifest schemas reject unexpected verdict fields.
Payload paths are portable relative names, without traversal, streams, device names or Windows case collisions.
The v1 bound is 4,096 files and one GiB; unsupported payloads retain source-build fallback.

Publication copies to unique staging, hashes the complete inventory and bytes, rechecks source and copied
payloads and atomically renames the completed directory. Failed staging remains diagnostic evidence; it is not
a cache hit. Publishing another output version never overwrites accepted bytes. Reads verify the independently
held manifest digest and every actual file, reject extra/missing/changed files and retain a reader lease through
use. Closing verifies integrity again. Source/file changes with preserved size or timestamps still invalidate.

Entry leases are operating-system file handles. Multiple readers coexist; publication/quarantine takes an
exclusive input-identity lease, including across processes. Disjoint input identities remain independent.
Quarantine moves one exact output version to a new owned location, preserves its bytes and refuses active
readers. No recursive deletion, foreign-process termination, credential creation or publication occurs.

## Verification and use

`Tests/Test-SdkCache.ps1 -TestRoot <existing marked root>` executes synthetic storage fixtures, including actual
separate-process lease controls. It does not compile a library or establish native SDK acceptance. Hosted CI
runs it on Windows and Ubuntu and retains the results with engine evidence.

Internal functions have explicit effects: `Get-CiSdkCacheKey` validates/reads schemas; `Initialize-CiSdkStore`
creates marked owned directories; `Publish-CiSdkCacheEntry` copies and publishes an immutable version;
`Import-CiSdkCacheEntry` verifies an independently held input identity and manifest hash and publishes the
original raw manifest through the same guarded writer, preserving its cross-platform output identity;
`Open-CiSdkCacheEntry` verifies and holds a lease (including a lock file on a miss); `Close-CiSdkCacheEntry`
verifies/relinquishes it; `Move-CiSdkCacheEntryToQuarantine` preserves one version through a guarded atomic move.
Callers must close every acquired entry in finally and keep the lease through all compilation/link use.

## Explicit local pinned application input

### Local unpinned snapshot data foundation

`Ci.LocalSdkConsumer.psm1` adds an explicit local dependency-admission reader.
It refuses hosted use and non-Release profiles before discovery, verifies the
application's unchanged API lock and actual clean pinned engine, then opens the
independently frozen descriptor and immutable data lease. Only after toolkit
authentication may it import the producer's original library-provenance reader.
The captured library/PDB must match that original current build record; the
canonical public interface and integration files must be present. The captured
portable ABI reference must equal the actual application-selected MSBuild/tool,
header and library reference. A mismatch refuses this explicit local request.

The reader's role is `LocalUnpinnedSdkConsumerInput` and its evidence recipe is
`LocalUnpinnedReleaseSdk`. Neither is accepted as a pinned build or a test result.
The snapshot's Windows producer identity normalizes path casing for its key.
Before original native build/provenance or ABI evaluation, the reader resolves
that same plain source directory to its filesystem spelling. Expanded MSBuild
path identities otherwise differ for a casing alias despite unchanged bytes.
Only equivalent Windows casing is accepted here; this does not redirect source,
rewrite the descriptor/key or remove any source, native-input, byte or ABI check.
Opening the reader does not create a compiler witness, link an application,
choose output paths or publish a build receipt. Consumer build adapters remain
unfinished.
Acquire this dependency reader before the consumer write lease; no producer
profile lease is held. Retain its immutable data lease through every future
compile/link use. Close rechecks application/actual-engine bytes, the frozen
toolkit/descriptor, original library provenance, ABI and complete snapshot, and
releases ownership even when verification fails. Failed close cannot authorize
a successful local build. Ordinary qualification, PrePush and package routes
continue to refuse local unpinned inputs.

Synthetic reader controls execute the actual storage/descriptor/Git/engine/file
binding and failure cleanup. Only original native-build acquisition and Windows
ABI metadata evaluation use recording boundaries; they grant no native verdict.

`Start-CiLocalSdkCompilerLease` explicitly binds an active dependency reader to
its separate local output operation. Acquire the consumer output write lease
after opening dependency input and before starting compilation. Starting the
compiler frame rechecks consumer/engine/toolkit/producer source and original
library provenance before and after ABI evaluation, then uses the canonical
shared tool-binding projection and schema-3 witness factory. Hosted and
compiler-free execution refuse before discovery; duplicate live frames refuse.
Drain owned children, stop the compiler frame with `Stop-CiLocalSdkCompilerLease`,
then close dependency input. Misordered close fails and releases both handles;
it cannot authorize a local build receipt. These APIs perform no application
build, linker-input verification or build-result publication by themselves.

`Ci.LocalSdkBuild.psm1` supplies the explicit local application build broker.
Each product owns its reviewed literal solution/project, target, executable and
distinct SDK/engine/output/test/version property names. An application with no configurable
test surface declares exactly the empty-string `testsProperty` sentinel: the broker omits
that override instead of inventing a product switch. Null, whitespace, malformed and colliding
property names still refuse. The other four property names remain required and distinct;
omitting a test switch changes no SDK, compiler, output, source or version binding and grants
no test result. The shared engine does not infer product layouts. An optional product-owned dependency preparation
callback runs after dependency acquisition and before consumer output ownership.
The broker creates a fresh exclusive operation beneath `.build/local-unpinned/`,
starts the compiler frame, evaluates the actual application project and checks
both output paths before compilation. It invokes the selected real MSBuild with
the same Release SDK and tool properties, requires zero warnings/errors, and
reads bounded, plain linker tracking files to establish that the actual link
used the held `DxUi.lib` and no other archive with that name. Tracking is inventoried
across the complete fresh leased operation, including sibling plugin intermediates;
recorded tracking paths are relative to that operation. Missing tracking
fails. This route does not reuse canonical application outputs or kill an
independently launched application.

After child drain, successful compiler/input close is required before a
create-only `LocalUnpinnedApplicationBuild` result is written. Failed operations
retain their directories, available build log and a failure record; they produce
no accepted result. The result records source, engine, dependency, actual linker
inputs and executable bytes. Its `testsExecuted`, `repositoryQualified` and
`productionQualified` fields remain false. Product tests, pinned PrePush/native
qualification, packaging and publication remain separate gates. The broker
refuses hosted and compiler-free invocation before discovery. Synthetic contract
and linker-file controls do not establish application build acceptance.

Each operation with an acquired output directory also attempts to retain
`operation-timing.json`, including failed operations. It uses one monotonic
clock and contiguous, non-overlapping phases for request checks, SDK admission,
dependency preparation/output acquisition, compiler lease, project metadata,
native compilation, output verification, dependency close, result publication
and owned cleanup. SDK admission and close include their byte, producer and ABI
checks; those aggregate phases do not claim separate per-check timings.
The total is explicitly scoped to the broker invocation: adapter bootstrap and
locks before entry, timing-file serialization and return are excluded. Public
entry latency needs a separate outer measurement. `buildElapsedMs` remains the
native-build observation and must never be presented as the end-to-end total.
Primary failure and cleanup failure retain distinct phase outcomes. Timing
diagnostics supply no test/qualification result, mask no original failure and
change no local, main, packaging or publication gate. Failure to write this
diagnostic emits a warning; it cannot turn a failed operation into a pass.

The shared MSBuild guard has a separate `LocalUnpinnedAbiV1` compiler-lease
contract (witness schema 3). It retains the live process/handle check and every
actual-tool/search-path/per-translation-unit ABI restriction of v2. Local output
and intermediate directories must be absolute, plain paths beneath one distinct
operation in the application's `.build/local-unpinned/` tree. Read-only local
preflight checks that ownership before MSBuild creates directories or writes its
tool-properties file; the subsequent full verifier checks the evaluated output
paths and bounded actual tool properties again. A local owner cannot downgrade
to a pinned contract or skip actual metadata verification. Closed owners refuse.
This guard does not create an application build adapter, accept a local test
verdict or allow canonical qualification/package routes to consume local outputs.
Explicit `Tests/Test-SdkCache.ps1 -NativeMsBuildPath <application-selected MSBuild.exe>`
also exercises the actual MSBuild target with spaced, trailing output paths,
escaped output/intermediate refusals, per-file CRT rejection and contract downgrade.
It compiles no product and refuses compiler-free/non-Windows execution before
discovery or fixture creation. Ordinary hosted storage tests omit that option.

`Ci.LocalSdkSnapshot.psm1` exposes a separate data-only `LocalUnpinnedSdkSnapshot`
role. It is not accepted by the pinned SDK reader, importer, application build,
qualification or publication routes. Producer capture and consumer/linker integration
remain unfinished; this primitive alone does not enable a local override.

`Get-CiLocalSdkSnapshotKey` validates a strict identity and returns its disjoint key.
It binds the absolute producer checkout, original HEAD, complete raw dirty-source
identity, the existing Release SDK input families and nonempty portable path bindings
for headers, libraries, symbols, integration files, licenses and build provenance.
Missing families, unsupported profiles and verdict fields refuse. The nested SDK
input record retains all existing Release/MD/annotation/toolchain requirements;
this initial foundation adds no Debug, ASan or annotation variant.

`Publish-CiLocalSdkSnapshot` requires an already initialized owned store. It verifies
the current producer HEAD/raw bytes, checks every bound file, then uses the canonical
SDK storage writer for complete inventory/hash verification, unique preserved
staging and atomic immutable publication. It rechecks source after publication and
returns no usable acquisition on mutation. Immutable diagnostic bytes may remain.
`Open-CiLocalSdkSnapshot` checks the independently retained identity and manifest
hash, every stored byte, declared artifact bindings and current producer again,
holding the existing shared entry lease. An absent exact locator returns null;
malformed or corrupt data fail. `Close-CiLocalSdkSnapshot` verifies producer and
payload again and always releases the lease, including on failure. Double close
refuses. Editing the producer invalidates acquisition/use without deleting the
captured evidence. No function compiles, restores, invokes producer code or changes
a pin, source file or consumer output. Store initialization remains explicit.

The future producer adapter must capture/build under its canonical operation lease
and independently acquire actual source/profile/toolchain/dependency identities
and library/PDB/header provenance. Declared bindings and synthetic storage fixtures
do not prove ABI compatibility, native library validity or a producer build. The
future consumer adapter must independently admit these inputs, bind actual linker
inputs and isolated local-unpinned outputs/receipts, and reject them in PrePush,
authoritative qualification, package and publication. Never relabel this role or
copy its bytes into a managed pin. Acquire/release producer capture before entering
the consumer write lease to avoid a cross-repository lease cycle.

The existing `Test-SdkCache.ps1` owner executes local dirty-source, retained-timestamp
mutation, untracked-source, changed HEAD, corruption, missing-family, role separation,
reader concurrency and close-failure controls alongside the unchanged pinned cases.
These controls use synthetic payloads and establish storage behavior only.

`Ci.LocalSdkDescriptor.psm1` provides a strict descriptor/data-reader seam before any
producer code is imported. `Read-CiLocalSdkSnapshotDescriptor` requires an absolute
descriptor path and the caller's independently frozen SHA-256. It reads a bounded
nonempty file of at most eight MiB, rejects truncation/growth, unknown fields and
input-key changes, and requires the original descriptor and store below the
identified tooling checkout's `.build`. The canonical no-follow guard covers all
path ancestors. It verifies the tooling's original HEAD, raw source bytes and actual
clean pinned engine bytes using the independently executing shared reader. Pass
the tooling's own `.ci-engine` explicitly to that reader; its default belongs to
the calling consumer and cannot identify another checkout's engine.

`Open-CiLocalSdkSnapshotDescriptor` holds the existing immutable payload reader,
rechecks the original descriptor/bootstrap after acquisition and returns a distinct
`LocalUnpinnedSdkSnapshotDescriptorLease`. A missing exact payload is a null miss.
`Close-CiLocalSdkSnapshotDescriptor` rechecks descriptor/bootstrap, producer source
and payload and always releases the underlying reader, even if descriptor validation
fails. Double close refuses. No function imports or invokes producer code, creates
a compiler witness, changes a pin, builds or qualifies anything. The descriptor
hash freezes selected local data; it does not authenticate a hosted producer.

Consumer adapters still must reacquire complete current producer profile/library
provenance, admit the exact compatible API/ABI and actual linker inputs, use separate
local-unpinned outputs/receipts and retain all authoritative refusal boundaries.
Descriptor/data admission alone cannot enable that unfinished integration. Synthetic
controls verify an executable producer marker remains uninvoked, raw toolkit and
ignored actual-engine mutation, descriptor/schema/path corruption, bounded/locked
reads and failure-close lease release.

`Ci.SdkConsumer.psm1` provides one shared application seam for a deliberately selected local Release SDK.
The strict descriptor resides below the application's `.build`, outside the store, and binds source/API,
platform, full existing source/tooling/storage checkouts, store and independently retained manifest hash.
Preparation constructs the same strict `LocalPinnedDependencyInput` role consumed by the reader;
the successful-hit constructor is checked through that actual reader schema before integration.
It cannot change the application's lock. Canonical raw bootstrap checks precede SDK imports; the native
input acquisition then independently derives the complete key and leases the verified payload. A precise
miss supplies no bytes and permits the adapter's unchanged source-build fallback. Malformed/corrupt inputs
fail. No clone, dependency restore, product launch or test verdict occurs in this shared helper.

The adapter holds the reader through all native use and closes it successfully before publishing a build
receipt. Close rechecks the independent descriptor, complete SDK inputs and payload bytes; failure releases
handles and prevents a successful build receipt. Existing build/test/package source and byte checks remain.
The receipt identifies `PinnedReleaseSdkV1`, its actual key, manifest and complete input identity. It must
never pretend this SDK recipe is an execution of the previous source wrapper.

MSBuild calls `Test-SdkConsumerLease.ps1` before compilation with the exact project/payload/profile and a
unique operation witness. The guard checks owner PID plus creation time and an actual still-held file handle.
PID existence or a surviving witness alone is insufficient. Closed, stale and other-profile settings refuse.
Witnesses stay as diagnostic data after handles close; they grant no reuse authority. This prevents accidental
direct/stale compilation; it is not a security boundary against a user controlling the local build process.

This local seam does not authenticate an arbitrary hosted artifact. Use the following separate transport
contract before opening imported bytes. Application adapter adoption, native architecture qualification,
local dirty-source candidates and overall speedup acceptance remain separate obligations.

## Authenticated hosted SDK transport

`Tools/Import-HostedSdk.ps1` accepts a complete independently evaluated SDK identity below the consumer's
`.build`, an explicit producer run and attempt. It changes no dependency pin. `Ci.SdkTransport.psm1` reads
current GitHub REST metadata using an existing repository-read credential. The reviewed caller blob and
reusable engine are pinned in `Policy/sdk-transport.json`; a changed workflow requires an explicit policy review.
Only a successful main `workflow_dispatch` of the exact DxUi SDK workflow is eligible. The selected native
architecture job must pass with its reviewed runner label and attempt. Truncated metadata, duplicate/missing
artifacts, another source/head/repository, unknown/expired digests and failed/pending/cancelled work refuse.

The selected artifact name binds source, architecture and attempt. The authenticated server SHA-256 and
byte count freeze the entire archive. The API credential is sent only to api.github.com; the signed storage
redirect is fetched using a separate client without authentication headers. Download size/time and expanded
entry count/bytes are bounded. All archive paths are validated before the first extraction; traversal,
Windows device/stream names, links/reparse entries and case collisions refuse. Existing files are never overwritten.
Extraction holds a read handle on the archive and rechecks its authenticated digest on that same stream.
The independent entry-manifest digest is acquired directly from that verified archive, not from mutable
extracted files; substitution after download or extraction refuses before publication.

After transfer, read the producer metadata again and require identical provenance. Exactly one SDK entry
must match its full independent input key and original raw manifest hash. Generic storage verifies the
complete identity and payload inventory, then publishes atomically using the existing writer/read-lease
contract. Retain the authenticated envelope, original archive, extraction, import record and failed staging
under unique owned `.build/sdk-downloads` paths. No cleanup or implicit retry of a newer attempt occurs.

Transport supplies dependency bytes only. It does not prove application ABI compatibility, a product test,
native consumer runtime, release qualification or publication. The application must independently bootstrap
its source/tooling policy, derive its actual compiler/dependency/profile key, acquire and close a reader,
and run its existing required checks. A different local compiler is a distinct input, even when the source pin matches.

## Hosted main consumer preparation

Application SDK wrappers import `Tools/MSBuild/Ci.SdkConsumer.targets` only for
actual SDK-linking projects and set `CiSdkRoot`, `CiSdkProjectRoot` and
`CiSdkLeasePath`. This canonical target requires a live owner before preparation
and compilation, refuses mixed source/SDK roots, and checks the effective metadata
of every translation unit: Release `/MD`, latest language mode, enabled STL
annotations, default iterator layout, packing, wchar_t and calling convention.
The actual SDK import root must match the verified reader payload; omitting the
guard's root while retaining SDK imports also refuses. Application build/package
entrypoints call `Open-CiApplicationSdkInput`, which binds the actual source/API/
target lock and exact clean pinned controller before opening the shared reader.
Opaque compiler options cannot override those ABI properties. SDK archive imports
retain their independent exact compiler/architecture checks.

The explicit `Tools/Test-SdkConsumerPolicy.ps1` executes the real targets using an
already verified held reader, retaining compatible/incompatible MSBuild controls
and a closed-witness negative control beneath the application `.build`. It does
not compile a product, run in compiler-free PR checks, or grant runtime acceptance.

`Ci.SdkPreparation.psm1` prepares an explicit descriptor only for admitted matching-native Windows hosted
main ReleaseTestBuild/Production roles. Local, PR/compiler-free, other-profile and emulated execution refuse
before network or filesystem side effects. The exact source/API must have an explicit run/attempt in
`Policy/sdk-distribution.json`; absence retains the governed source recipe, never a newer dependency pin.

Each operation uses a unique `.build/sdk-preparation` workspace, so mutable package restores do not collide
across builds or platforms. Acquire full canonical clean source/tooling/storage-engine checkouts and verify
their entire reviewed raw maps before importing SDK tooling or running the pinned source's vcpkg restore.
Independently evaluate the actual complete native input key; preparation never compiles DxUi.lib.
Authenticate/import its exact hosted bytes through the transport contract, then write the descriptor outside
the shared byte store. Retain workspace, timings, downloaded evidence and failed attempts without cleanup.
Revalidate the canonical frozen application context before and after preparation; source, version or engine
movement during transfer cannot qualify the originally admitted input.

Retain create-only JSON records beneath `.build/evidence/sdk-input-preparation` for
the independent expected input key before transfer and its prepared/exact-miss
outcome, or the absence of a distributed pin. These records travel with the normal
native evidence artifact; earlier records are never replaced. They supply diagnostic
identities and timings only, without a product acceptance verdict.

A verified artifact with another compiler, compiler-profile, dependency or environment hash is an exact
cache miss; retain source fallback and accept no bytes. A different source/API/architecture/ABI/integration
policy, malformed manifest, corrupt archive or unknown producer fails rather than being relabelled as a
compatible hit. The application reader still rechecks bootstrap, actual inputs and payload and holds its
lease through native use. Preparation/transport supplies no test verdict or artifact receipt on its own.

An authenticated exact recipe miss also retains both complete hash-only identities,
the changed field names and producer run/attempt in a create-only
`.build/evidence/sdk-recipe-misses` record. It supplies no dependency bytes and does
not initialize the input store. The ordinary native workspace artifact retains this
record so a successful source fallback cannot be mistaken for SDK-hit acceptance.

## Portable SDK toolchain references

`Ci.SdkAbi.psm1` supplies a separate v2 byte-reference format. It does not alter
the v1 recipe, authenticate an SDK origin, admit a consumer, or cache a product
verdict by itself. Reviewed automatic distribution now selects the versioned qualified
ABI continuation below; the original v1 identity and explicit legacy reader remain available.

The portable reference names explicit tool/header/library roles and relative
paths, not installation or checkout locations. Every file's actual SHA-256 and
length remain binding; timestamps are not an identity shortcut. It covers the
selected MSBuild, VC targets/tasks, MSVC headers/libraries/host tools, Windows
headers/target libraries, CRT libraries and SDK tools. Required roots must exist
and contain files. Reparse ancestors, internal links, case collisions, drive
roots, oversized/empty inventories and unreadable files refuse. The real Windows
acquisition uses the reviewed producer's canonical tool-selection guard rather
than duplicating MSBuild architecture or executable-selection rules. Its caller
must authenticate that producer-tooling snapshot before importing it.

Real acquisition is explicit native tooling, never a compiler-free PR action.
Unsupported `CL`, `_CL_`, `INCLUDE`, `LIB` and `LIBPATH` environment overrides
refuse. The strict schema and canonical digest checks reject changed bytes,
missing roles, duplicate/unsafe paths, inconsistent compiler hosts and injected
verdict fields. A valid self-computed reference establishes data integrity only;
it is not evidence of trusted origin or compatibility with arbitrary consumers.

`Ci.SdkQualifiedProducer.psm1` can create a separate ABI reference for an already
qualified SDK. It bootstraps the exact source/API/tooling/storage pins, requires
every existing native SDK receipt gate, rederives the complete v1 producer key,
holds the original input's reader lease and binds its original key/manifest hash.
It retains the exact source's public-header Git tree for consumer provenance;
an application need not reconstruct that committed tree from a source build.
The full producer identity is checked again after portable acquisition. Source
and payload close checks must pass before the create-only reference is written
outside the immutable store. The original SDK entry and receipts are preserved.
The reference's nested toolchain record is independently schema/digest-validated.

This producer-side file cannot authenticate itself. Hosted provenance, an
archive-bound reference, actual per-consumer ABI/tool selection, reader lifetime,
native tests and package qualification remain separate required work in I61.

The explicit SDK producer accepts `sdk_contract=QualifiedAbiV2` alongside the
backward-compatible `LegacyV1` default. The resolver validates and freezes that
choice. V2 selects the matching native compiler host before restore/build and
creates its ABI reference only after all existing native SDK gates succeed. A
failed reference prevents the successful SDK artifact upload. Its separate file
travels in that same source/platform/attempt-bound archive; it does not mutate
the SDK entry. Read-only tokens, manual main admission and independent native
architecture gates remain unchanged. Existing v1 producer attempts stay governed
by their original pinned transport policy. No consumer trusts a new producer
attempt until its distinct caller/engine and archive contract are accepted.

## Qualified SDK archive transport

`Ci.SdkQualifiedTransport.psm1` uses a separate v2 policy. The enabled reviewed
policy names producer caller blob `08d6806d6ef3db8be937042d6f6a1d57a2e1c6df`
and engine `0ab35be5d746b8a23cad066f64fcd0062678d06d`. The three unchanged pins
use successful native x64/ARM64 campaigns 42866937316, 42866944166 and 42866951701.
All six actual archives pass server digest, extraction, original entry/reference/receipt
binding verification. Product SDK use and runtime acceptance remain separate.
A disabled policy still refuses before API calls or output; its regression control
uses the actual modules in an isolated child with an owned disabled policy fixture.
The existing v1 transport policy and successful historical attempts are retained.
V2 uses the same strict main/manual/native-job/run/attempt/artifact checks, with
an explicit `HostedQualifiedSdkEnvelope` role.

The original archive is held read-only and its server-authenticated digest and
length rechecked before reading JSON. The complete bounded ZIP catalog is checked
for unsafe paths, collisions, links and excessive expansion. The exact entry,
ABI reference and native SDK receipt are acquired directly from that held archive,
not from their extracted copies. All three must be unique and remain byte-identical
after extraction. The native receipt retains every SDK gate and binds the same
source/API/architecture, run-derived version, original key and manifest. The ABI
reference's receipt hash must match those original receipt bytes.

The original v1 input identity is preserved. Source bytes, ABI/integration policy,
reviewed tooling/storage and the reference's key/manifest must agree with the
requested pin and independently acquired archive contents. Another compiler or
environment in the original producer identity is not relabelled as a local v1
recipe. Generic storage still verifies every payload byte and publishes atomically.
Producer metadata is read again after transfer; changed provenance refuses before
store initialization. Failed downloads/extraction stay retained for diagnosis.

This transport provides dependency bytes and their authenticated producer reference.
It does not establish consumer compatibility, a native application result, local
delegation or main adoption. V2 application readers and their actual tool/header/
per-file ABI checks must be implemented and accepted before any v2 input can
replace an existing consumer obligation.

## Qualified SDK application reader

The separate `HostedQualifiedDependencyInput` descriptor names the retained
original archive, exact entry/reference/receipt paths, producer run/attempt and
unchanged application source/API. It remains independently retained below the
application `.build`, outside the byte store. The strict schema admits no result
fields. Source/tooling/storage checkouts still pass the canonical raw bootstrap.

An explicit qualified distribution uses authenticated v2 transport before writing
that descriptor. It does not restore the producer's vcpkg inventory or recompute
the producer's entire v1 build recipe in the consumer. Legacy distribution and
reader behavior retain their existing path. Distribution entries select
`QualifiedAbiV2` explicitly only after review of successful producers and their
authenticated bytes; schema support alone never activates another source or attempt.

`Open-CiApplicationSdkInput` accepts the application's actual `MSBuildPath` for
v2. It reauthenticates the exact producer envelope, derives the original binding
from held archive bytes and compares the actual complete portable tool/header/
library reference with the producer's reference. A precise mismatch supplies no
SDK bytes and retains source fallback. Invalid origin, descriptor, byte binding
or unsupported overrides refuse. A hit holds the generic original SDK entry
lease and validates the canonical SDK payload before creating its live witness.
The evidence role is `PinnedQualifiedReleaseSdkV2`, distinct from a local v1
recipe execution; it preserves the producer's original identity, key and manifest.

The v2 witness binds the actual selected local MSBuild, VC/SDK roots, compiler
version/host and CL/link/lib/shader tools. The real MSBuild guard writes bounded
plain tool properties beneath the profile's `.build` intermediate directory;
the separate verifier checks those actual values against the held reader. It
rejects contract downgrade, unknown/stale/closed owners, missing metadata, another
tool/root or unsupported compiler environment. The immutable SDK include tree
precedes other include directories in each SDK-consuming translation unit. All
existing per-file ABI checks remain; v2 also rejects managed, custom exception/
character-layout and opaque backend ABI overrides.

The parent reader still refuses ambient `CL`, `_CL_`, `INCLUDE`, `LIB` and
`LIBPATH` overrides before evaluation. Its live witness also binds the pinned
project's evaluated default `IncludePath`, `LibraryPath` and `ReferencePath`.
Each actual consumer project preserves the default ordered system paths, then
may append existing plain paths owned by the application or immutable SDK include
tree. Foreign paths, reordered/omitted system paths and linked additions refuse.
The old pinned library project's implicit Visual C++ UnitTest include/lib defaults
are optional; ordinary application projects do not enable that legacy default.
VC targets may initialize the child check's `INCLUDE`, `LIB` and `LIBPATH` only
to the same validated actual properties; other environment values refuse.
The bounded property file represents semicolons as pipes, never shell arguments.
Percent, pipe and line-break characters in default search paths are unsupported
and fail closed. These checks do not change the portable SDK byte reference or
admit an application test result.

Close reauthenticates producer/archive provenance, rechecks tool/header/library,
canonical source/tooling/storage and payload bytes, then releases the witness.
The independent descriptor and current controller bytes must remain unchanged.
A failed close releases ownership and cannot publish accepted build provenance.
Applications must explicitly pass the v2 contract returned by the verified reader
and reopen the same known recipe for packaging. Runtime, native architecture,
ETW, package, symbol and other product gates remain independent. Controlled-origin
reader or guard fixtures do not establish live hosted-origin or product acceptance.
