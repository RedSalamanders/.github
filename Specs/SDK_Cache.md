# Immutable dependency SDK inputs

Status: storage/schema foundation implemented; native identity acquisition, producer distribution,
consumer integration and local candidate support remain in [I61](Plans/WIP/TestingAndIntegrationAcceleration_2026-11-09.md).
No consumer currently bypasses source compilation through this module.

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
`Open-CiSdkCacheEntry` verifies and holds a lease (including a lock file on a miss); `Close-CiSdkCacheEntry`
verifies/relinquishes it; `Move-CiSdkCacheEntryToQuarantine` preserves one version through a guarded atomic move.
Callers must close every acquired entry in finally and keep the lease through all compilation/link use.
