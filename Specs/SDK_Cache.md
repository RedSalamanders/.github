# Immutable dependency SDK inputs

Status: immutable storage, pinned producer/distribution and explicit application readers are implemented.
Monitor and RedXe have locally qualified SDK consumer paths. Automatic hosted SDK-hit acceptance,
the other application integrations, local candidates and acceleration acceptance remain in
[I61](Plans/WIP/TestingAndIntegrationAcceleration_2026-11-09.md).

## Explicit pinned native SDK producer

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
verdict. Automatic distribution and application readers still use the v1 contract
above until their separate versioned continuation is implemented and accepted.

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
