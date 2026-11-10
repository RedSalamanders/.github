# Immutable dependency SDK inputs

Status: storage/schema foundation implemented; native identity acquisition, producer distribution,
consumer integration and local candidate support remain in [I61](Plans/WIP/TestingAndIntegrationAcceleration_2026-11-09.md).
No application currently bypasses source compilation through this module.

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

A verified artifact with another compiler, compiler-profile, dependency or environment hash is an exact
cache miss; retain source fallback and accept no bytes. A different source/API/architecture/ABI/integration
policy, malformed manifest, corrupt archive or unknown producer fails rather than being relabelled as a
compatible hit. The application reader still rechecks bootstrap, actual inputs and payload and holds its
lease through native use. Preparation/transport supplies no test verdict or artifact receipt on its own.
