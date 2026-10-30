# Emergency PR merge

This is the exceptional merge route for all six RedSalamanders products. Normal merges require the configured compiler-free CI, CodeQL and dependency-review checks. An organization owner may explicitly bypass those branch gates through a pull request during an emergency. CI automation has no bypass permission.

The branch ruleset grants OrganizationAdmin with bypass_mode=pull_request. It does not grant direct pushes or force pushes. Preserve the existing branch protections, review settings and required checks; never disable the ruleset to perform an emergency merge. Repository administrators who are not organization owners must ask an organization owner to perform this operation.

## Operator procedure

1. Open the ordinary PR. Review its exact changes and capture its full head SHA.
2. Record the emergency reason, blocked checks, accepted risk, operator, rollback and follow-up in the PR and in a local emergency-reason.md file for the merge commit. Keep credentials and personal data out of that file.
3. Use GitHub's PR override control as the organization owner, or the CLI below. The head match refuses a concurrent update; re-review rather than dropping that option.

```powershell
$repository = 'RedSalamanders/RedSalamander' # Select the actual product.
$pr = 123 # Select the reviewed PR.
$head = gh pr view $pr --repo $repository --json headRefOid --jq .headRefOid
if ($LASTEXITCODE -ne 0 -or $head -notmatch '^[a-f0-9]{40}$') { throw 'Cannot identify the reviewed PR head.' }
gh pr merge $pr --repo $repository --admin --merge --match-head-commit $head --body-file emergency-reason.md
if ($LASTEXITCODE -ne 0) { throw 'Emergency merge refused; preserve the diagnostic and review permissions or source drift.' }
```

Use --admin only for the recorded emergency, never as an automatic fallback after an ordinary merge fails. GitHub retains the actual failed/pending checks and bypass audit trail. The reason also stays in the merge commit. This policy adds no bot-owned privileged workflow or publication credential.

## Qualification after merging

The normal main coordinator still admits meaningful inputs after five quiet minutes. Existing native work is not cancelled. Do not add skip-CI directives as part of this procedure. A failed qualification stays failed; an explicit retry is available through the normal main qualification action.

This override changes merge eligibility only. Production Release, ZIP/SDK qualification and manual release/winget publication still require complete matching successful native evidence. An emergency merge is not qualification and does not relabel red checks as green.

## Configuration and verification

All applicable default-branch rulesets must list OrganizationAdmin with pull_request bypass. Any additional classic branch protection must also permit the owner to bypass its merge checks, or that independent rule will still block the operation. Retain deletion/non-fast-forward protections and PR-only changes.

The 2026-10-30 rollout configured RedSalamander ruleset 12858820, RedXe 23723903, DxUi 22346990 and RedMonitor 26241026. RedMonitor retains its previous classic protection and all three required check identities; the new ruleset establishes PR-only changes and the owner route. Before/after API evidence is retained in the organization rollout record. RedPrism and RedTilde remain pending their owner's planned public visibility change because GitHub rejects their ruleset APIs under the current account capability. No emergency merge was exercised as part of this configuration change.

[GitHub PR-only bypass](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository) and [GitHub CLI merge options](https://cli.github.com/manual/gh_pr_merge) define the platform behavior.
