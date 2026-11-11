# Cheap readiness prerequisites only. These checks never supply native acceptance.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Test-CiCandidateReadinessCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Candidate,[Parameter(Mandatory)][object]$Catalog)
    $required=@(
        @{name='checks / ci-gate';appId=15368},
        @{name='security / codeql';appId=15368},
        @{name='security / dependency-review';appId=15368})
    # Root's existing review approval is a distinct prerequisite. App IDs were
    # independently read from the actual check catalog; a same-name Actions job
    # cannot stand in for Entire's approval gate.
    if($Candidate.repository -ceq 'RedSalamanders/RedSalamander'){$required+=@{name='Entire Gates';appId=2626939}}
    if($Catalog.total_count -ne @($Catalog.check_runs).Count){throw 'Readiness check catalog is incomplete.'}
    $records=[Collections.Generic.List[object]]::new()
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($expected in $required){
        $selected=@($Catalog.check_runs|Where-Object name -CEQ $expected.name)
        if($selected.Count -ne 1){throw "Exactly one original readiness check is required: $($expected.name)"}
        $check=$selected[0]
        if($check.head_sha -cne $Candidate.headCommit -or $check.app.id -ne $expected.appId -or
            $check.status -cne 'completed' -or $check.conclusion -cne 'success' -or
            [string]$check.id -cnotmatch '^[1-9][0-9]{0,19}$' -or -not $ids.Add([string]$check.id)){
            throw "Candidate is not ready for native admission: $($expected.name)"
        }
        $records.Add([ordered]@{name=$check.name;id=[string]$check.id;appId=$expected.appId;headCommit=$check.head_sha})
    }
    # An existing native integration check may be pending because admission is
    # about to produce it. Do not confuse that future obligation with the cheap
    # prerequisites or claim that readiness is a native/merge verdict.
    return @($records.ToArray())
}

Export-ModuleMember -Function Test-CiCandidateReadinessCatalog
