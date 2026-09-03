<#
.SYNOPSIS
    Step 2 校验脚本：校验概念归一化结果 (concept_dictionary) 与节点回写的一致性。
    【标准 JSON 输出协议】：所有校验结果与统计信息均以纯 JSON 形式输出到 stdout，便于模型直接解析与自审。
#>

[CmdletBinding()]
param(
    [Alias("i")]
    [string]$InputFile = "step2_concepts_raw.json",

    [Alias("o")]
    [string]$OutputFile = "step2_concepts.json"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Output-Fail {
    param([array]$Errors)
    $res = @{
        success = $false
        step    = 2
        errors  = $Errors
    }
    $res | ConvertTo-Json -Depth 6 -Compress:$false
    exit 1
}

if (-not (Test-Path $InputFile)) {
    Output-Fail @(
        @{ type = "FILE_NOT_FOUND"; message = "Input file '$InputFile' not found." }
    )
}

try {
    $rawContent = [System.IO.File]::ReadAllText((Resolve-Path $InputFile).Path, [System.Text.Encoding]::UTF8)
    $data = $rawContent | ConvertFrom-Json
}
catch {
    Output-Fail @(
        @{ type = "JSON_SYNTAX_ERROR"; message = "Failed to parse JSON: $($_.Exception.Message)" }
    )
}

$errors = [System.Collections.ArrayList]::new()

if ($null -eq $data.concept_dictionary -or $data.concept_dictionary -isnot [array]) {
    [void]$errors.Add(@{
        type = "MISSING_FIELD"
        field = "concept_dictionary"
        message = "Missing or invalid 'concept_dictionary' (must be an array)."
    })
}
if ($null -eq $data.nodes -or $data.nodes -isnot [array]) {
    [void]$errors.Add(@{
        type = "MISSING_FIELD"
        field = "nodes"
        message = "Missing or invalid 'nodes' (must be an array)."
    })
}

if ($errors.Count -gt 0) {
    Output-Fail $errors.ToArray()
}

$nodeMap = [System.Collections.Generic.Dictionary[string, psobject]]::new()
foreach ($n in $data.nodes) {
    if (-not [string]::IsNullOrWhiteSpace($n.id)) {
        $nodeMap[$n.id] = $n
    }
}

$conceptMap = [System.Collections.Generic.Dictionary[string, psobject]]::new()
$canonicalSet = [System.Collections.Generic.HashSet[string]]::new()
$totalAliases = 0

for ($c = 0; $c -lt $data.concept_dictionary.Count; $c++) {
    $item = $data.concept_dictionary[$c]
    $idx = $c + 1

    if ($null -eq $item -or $item -is [array]) {
        [void]$errors.Add(@{
            type = "INVALID_CONCEPT_OBJECT"
            index = $idx
            message = "Concept item at index $idx is not a valid JSON object."
        })
        continue
    }

    $cid = $item.id
    if ([string]::IsNullOrWhiteSpace($cid)) {
        [void]$errors.Add(@{
            type = "MISSING_FIELD"
            index = $idx
            field = "id"
            message = "Concept item at index $idx is missing 'id'."
        })
    } else {
        if ($conceptMap.ContainsKey($cid)) {
            [void]$errors.Add(@{
                type = "DUPLICATE_CONCEPT_ID"
                concept_id = $cid
                message = "Duplicate concept ID '$cid'."
            })
        } else {
            $conceptMap[$cid] = $item
        }
    }

    $canonical = $item.canonical
    if ([string]::IsNullOrWhiteSpace($canonical)) {
        [void]$errors.Add(@{
            type = "MISSING_FIELD"
            concept_id = $cid
            field = "canonical"
            message = "Concept '$cid' is missing or has empty 'canonical'."
        })
    } else {
        if ($canonicalSet.Contains($canonical)) {
            [void]$errors.Add(@{
                type = "DUPLICATE_CANONICAL_NAME"
                concept_id = $cid
                canonical = $canonical
                message = "Duplicate canonical concept name '$canonical'. Must be merged into one concept with aliases."
            })
        } else {
            [void]$canonicalSet.Add($canonical)
        }
    }

    $taughtBy = $item.taught_by
    if ([string]::IsNullOrWhiteSpace($taughtBy)) {
        [void]$errors.Add(@{
            type = "MISSING_FIELD"
            concept_id = $cid
            field = "taught_by"
            message = "Concept '$cid' ($canonical) is missing 'taught_by'."
        })
    } elseif (-not $nodeMap.ContainsKey($taughtBy)) {
        [void]$errors.Add(@{
            type = "INVALID_TAUGHT_BY_NODE"
            concept_id = $cid
            taught_by = $taughtBy
            message = "Concept '$cid' references non-existent node '$taughtBy' in 'taught_by'."
        })
    }

    if ($item.PSObject.Properties.Name -contains "aliases") {
        if ($item.aliases -isnot [array]) {
            [void]$errors.Add(@{
                type = "INVALID_ALIASES"
                concept_id = $cid
                message = "Concept '$cid' aliases must be an array."
            })
        } else {
            $totalAliases += $item.aliases.Count
        }
    }
}

# 校验节点回写的 teaches 和 requires
foreach ($n in $data.nodes) {
    $nid = $n.id
    
    if ($n.PSObject.Properties.Name -contains "teaches" -and $n.teaches -is [array]) {
        foreach ($cid in $n.teaches) {
            if (-not $conceptMap.ContainsKey("$cid")) {
                [void]$errors.Add(@{
                    type = "UNRESOLVED_TEACHES_CONCEPT"
                    node_id = $nid
                    concept_id = "$cid"
                    message = "Node '$nid' teaches concept '$cid' which is not defined in concept_dictionary."
                })
            } else {
                $conceptObj = $conceptMap["$cid"]
                if ($conceptObj.taught_by -ne $nid) {
                    [void]$errors.Add(@{
                        type = "TAUGHT_BY_MISMATCH"
                        node_id = $nid
                        concept_id = "$cid"
                        concept_taught_by = $conceptObj.taught_by
                        message = "Node '$nid' claims to teach '$cid', but concept_dictionary specifies taught_by='$($conceptObj.taught_by)'."
                    })
                }
            }
        }
    }

    if ($n.PSObject.Properties.Name -contains "requires" -and $n.requires -is [array]) {
        foreach ($cid in $n.requires) {
            if (-not $conceptMap.ContainsKey("$cid")) {
                [void]$errors.Add(@{
                    type = "UNRESOLVED_REQUIRES_CONCEPT"
                    node_id = $nid
                    concept_id = "$cid"
                    message = "Node '$nid' requires concept '$cid' which is not defined in concept_dictionary."
                })
            }
            if ($n.teaches -contains "$cid") {
                [void]$errors.Add(@{
                    type = "SELF_DEPENDENCY"
                    node_id = $nid
                    concept_id = "$cid"
                    message = "Node '$nid' cannot both teach and require concept '$cid' (self-dependency)."
                })
            }
        }
    }
}

if ($errors.Count -gt 0) {
    Output-Fail $errors.ToArray()
}

foreach ($c in $data.concept_dictionary) {
    if ($c.PSObject.Properties.Name -notcontains "mastered") {
        $c | Add-Member -MemberType NoteProperty -Name "mastered" -Value $false
    }
}

$outFullPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path (Get-Location).Path $OutputFile }
$cleanData = @{
    concept_dictionary = $data.concept_dictionary
    nodes              = $data.nodes
}
if ($data.PSObject.Properties.Name -contains "meta") {
    $cleanData["meta"] = $data.meta
}

$jsonOutput = $cleanData | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($outFullPath, $jsonOutput, (New-Object System.Text.UTF8Encoding $true))

$response = @{
    success     = $true
    step        = 2
    output_file = $OutputFile
    stats       = @{
        concept_count = $conceptMap.Count
        alias_count   = $totalAliases
        node_count    = $data.nodes.Count
    }
}
$response | ConvertTo-Json -Depth 5 -Compress:$false
