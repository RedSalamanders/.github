# RedSalamanders shared CI

One versioned CI engine serves RedSalamander, DxUi, RedXe, RedPrism, RedTilde and RedMonitor. Each project pins its reusable workflows and engine checkout to the same immutable commit and supplies a reviewed `.ci/project.json` adapter manifest.

PRs run formatting and compiler-free tooling. Main changes are classified cumulatively and admitted after five quiet minutes. Native x64 and ARM64 Release test builds must both execute and pass their regressions before either production Release build starts. Qualified ZIPs remain internal artifacts until an explicit publication action promotes their unchanged bytes. DxUi publishes an SDK ZIP and has no winget application.

Long benchmarks, repeated stress, Debug and ASan qualification are explicit manual actions. Dependency and security monitoring remain automated without native builds.

The normative contract is [Specs/CI.md](Specs/CI.md). Engine behavior tests use actual temporary Git histories and deterministic coordinator events:

```powershell
./Tests/Test-Engine.ps1 -TestRoot Z:/RedSalamander.Perf
```

Implementation and live acceptance are tracked by [RedSalamander I55](https://github.com/RedSalamanders/RedSalamander/blob/main/Specs/Plans/WIP/CI_OrganizationStandardization_2026-10-29.md). A local test pass is not native project qualification.
