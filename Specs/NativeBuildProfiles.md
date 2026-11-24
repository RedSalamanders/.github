# Native build profiles

The RedSalamanders native profile applies to x64 and ARM64. Each product's build and dependency contracts
own its entry points, source-specific exceptions and release packaging. [Unified CI](CI.md) owns hosted
admission and the source, engine and artifact identities recorded for each lane.

## Common compiler policy

| Setting | Profile |
| --- | --- |
| Visual Studio and MSVC | Visual Studio 2026 with toolset `v145` and default MSVC `14.52.x`. Discover native MSBuild and verify the toolset selected by the project. |
| Windows SDK | 10.0.26100.0. |
| Language and source text | `stdcpplatest`, `/permissive-`, `/sdl`, `/utf-8` and Unicode Win32 declarations. |
| Warnings | `/Wall` with `/WX` disabled. A passing build reports zero warnings and zero errors. Preserve reviewed exclusions for specific compiler notices and the external classification of pinned dependency headers. |

| Configuration | Compilation | Linking and runtime |
| --- | --- | --- |
| Debug | `/Od` and Edit and Continue program databases (`/ZI`). | Debug dynamic CRT (`/MDd`) and COMDAT folding disabled. |
| ASan Debug | `/Od`, regular program databases (`/Zi`) and actual AddressSanitizer instrumentation. | Debug dynamic CRT (`/MDd`), non-incremental link and COMDAT folding disabled. The product test boundary proves the sanitizer with its real fault probe. |
| Release | `/O2`, function-level linking (`/Gy`) and whole-program optimization (`/GL`). | Full link-time code generation (`/LTCG`), `/OPT:REF`, `/OPT:ICF` and dynamic CRT (`/MD`). |

Product manifests identify reviewed exceptions. The static CRT keeps RedSalamander's portable `RedLauncher.exe`
independent of a separately installed runtime. RedXe declares its bootstrap and camera projects' CRT choices and the
bootstrap's size optimization in those project files. ASan dependency linkage and consumer-specific options follow the
exact dependency recipe. A shared policy change and the consumer's dependency pin advance together where those inputs
enter the archive identity.

## Evidence

A source-bound build records the exact profile, dependency inputs, build diagnostics and artifact identity. Changing
where options are declared uses an evaluated compiler and linker comparison for the supported profiles. A behavioral
profile change records its native builds and the applicable test results at their actual source. Qualification runs
on the target's native architecture. An ARM64 build on x64 supplies the ARM64 compilation result.

The [RedHome convergence plan](https://github.com/RedSalamanders/RedHome/blob/main/Specs/Plans/WIP/Convergence_2026-11-17.md)
records the remaining preprocessor, sanitizer, host-selection, analysis and shared-policy adoption work.
