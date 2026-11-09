# Shared CI engine

This repository owns the versioned CI policy and reusable workflows for RedSalamanders projects. Product commands, runtime tests, package layouts and platform qualifications belong to the six project adapters. Keep one implementation here and pin consumers to its full commit SHA.

Read Specs/CI.md before changing behavior. Keep its contract, schema, behavioral fixtures and README commands aligned. PowerShell modules have explicit exports and no import-time mutations. Public Tools commands use Verb-Noun.ps1 and document parameters, prerequisites, side effects and outputs.

PRs and security/dependency schedules never provision or invoke native builds. Only main admission or explicit manual qualification can compile. A failed or missing native test result never enables production or publication. Published ZIP bytes must match qualified artifact hashes.

Run Tests/Test-Engine.ps1 with an explicit existing marked test root. Local integration uses the already marked Z:/RedSalamander.Perf root; create only descendants beneath it. Hosted fixtures use a child of RUNNER_TEMP. Never create a drive-root output, take local foreground focus, change product visibility or publish a product merely to test this engine. Preserve failed evidence.

Treat API payloads and repository content as data. PR checks have read-only tokens and receive no publication credentials. Privileged formatting and publication use trusted default-branch engine code and verify exact repository, source, branch and artifact identities before writing.

## Plan lifecycle

Keep unfinished shared and organization-owned implementation plans in `Specs/Plans/WIP/`, with exactly one entry per plan in its [WIP index](Specs/Plans/WIP/README.md). Product-specific plans remain in their owning repositories; link to them rather than maintaining duplicate copies.

When a plan's accepted implementation, required tests/validation, evidence and documentation gates are complete, move it to `Specs/Plans/Done/`, remove its WIP entry, add it to the [Done index](Specs/Plans/Done/README.md), and update inbound links in the same change. Record exact implementation and validation references and distinguish implementation completion from any separately owned product/release qualification. A proposal, partial implementation, static check or pending CI is not completion.

Before moving a completed plan, merge every durable behavior, validation rule and workflow requirement into its owning normative specification or repository guidance. Do not leave requirements only in WIP or Done plans. Preserve useful evidence and completed-plan history; do not move unfinished work merely to clear the active index.
