# RedSalamanders shared CI

One versioned CI engine serves RedSalamander, DxUi, RedXe, RedPrism, RedTilde and RedMonitor. Each project pins its reusable workflows and engine checkout to the same immutable commit and supplies a reviewed `.ci/project.json` adapter manifest.

PRs run formatting and compiler-free tooling. Main changes are classified cumulatively and admitted after five quiet minutes. Native x64 and ARM64 Release test builds must both execute and pass their regressions before either production Release build starts. Qualified ZIPs remain internal artifacts until an explicit publication action promotes their unchanged bytes. DxUi publishes an SDK ZIP and has no winget application.

Long benchmarks, repeated stress, Debug and ASan qualification are explicit manual actions. Dependency and security monitoring remain automated without native builds.

The normative contract is [Specs/CI.md](Specs/CI.md). Engine behavior tests use actual temporary Git histories and deterministic coordinator events:

```powershell
./Tests/Test-Engine.ps1 -TestRoot Z:/RedSalamander.Perf
```

Implementation and live acceptance are tracked by [RedSalamander I55](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Plans/WIP/CI_OrganizationStandardization_2026-10-29.md). A local test pass is not native project qualification.

Each product has six canonical callers: compiler-free PR/main coordination, serialized main qualification, manual formatting, manual diagnostic qualification, compiler-free security, and manual publication. Tools/Update-ProjectPin.ps1 updates the manifest and callers together from a clean, exact engine checkout. A moving branch or a workflow-only pin update is refused by project conformance checks.

Operator actions start from the product's main branch. Formatting names an open same-repository PR and explicitly requests new checks after its narrow fast-forward commit. Manual native retry requires retry=true for already admitted inputs. Extended qualification selects Debug, ASan Debug or Release and Normal or Full scope; it cannot qualify a public release. Publication selects an original successful main qualification run and defaults to Prepare. Release promotes its ZIPs, and Winget requires the published anonymous URLs and native install evidence before submitting manifests with the dedicated credential.

No release or winget submission is part of engine validation. Ninety-day qualification artifacts may expire: operators then run an explicit fresh native qualification rather than reconstructing old ZIPs. Public reusable workflows let public and private products share the engine without changing product visibility.

The winget idempotency implementation derives from the MIT-licensed RedSalamander module; its original notice is retained in [ThirdParty/RedSalamander/LICENSE.txt](ThirdParty/RedSalamander/LICENSE.txt). This does not assign a license to an application.

The compiler-free organization dependency report is produced by .github/workflows/dependency-status.yml (weekly/manual) and Tools/Get-DependencyStatus.ps1. It inventories the six exact main trees, custom source locks, vcpkg pins and the latest engine tag without adoption or compilation. Unreadable/private repositories fail complete-coverage status while retaining readable results; the JSON report states remaining native/vendored vulnerability coverage limits. Run Tests/Test-DependencyStatus.ps1 for the seven independent API fixtures.

Optional winget.smokeTests declare bounded product-specific installed-alias commands in the reviewed adapter; the shared engine always exercises every alias with --help. Native installed registration, alias target/version and exact cleanup are required before submission. The installer does not rely on upstream source correlation for an unpublished package.
