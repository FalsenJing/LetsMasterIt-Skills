<#
.SYNOPSIS
    Step 1 validation script: validate node JSON format and object fields.
    Standard JSON output protocol: All validation results and statistics are output to stdout as pure JSON.
#>

[CmdletBinding()]
param(
    [Alias("i")]
    [string]$InputFile = "step1_nodes_raw.json",

    [Alias("o")]
    [string]$OutputFile = "step1_nodes.json"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Output-Fail {
    param([array]$Errors)
    $res = @{
        success = $false
        step    = 1
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

$nodes = @()
if ($data -is [array]) {
    $nodes = $data
} elseif ($data.PSObject.Properties.Name -contains "nodes" -and $data.nodes -is [array]) {
    $nodes = $data.nodes
} else {
    Output-Fail @(
        @{ type = "STRUCTURE_ERROR"; message = "Top-level JSON must be an array of nodes or an object with a 'nodes' array." }
    )
}

if ($nodes.Count -eq 0) {
    Output-Fail @(
        @{ type = "EMPTY_NODES"; message = "Nodes array is empty." }
    )
}

$errors = [System.Collections.ArrayList]::new()
$idSet = [System.Collections.Generic.HashSet[string]]::new()
$totalTeaches = 0
$totalRequires = 0
$totalBlackbox = 0

for ($i = 0; $i -lt $nodes.Count; $i++) {
    $node = $nodes[$i]
    $idx = $i + 1

    if ($null -eq $node -or $node -is [array]) {
        [void]$errors.Add(@{
            type = "INVALID_NODE_OBJECT"
            index = $idx
            message = "Node at index $idx is not a valid JSON object."
        })
        continue
    }

    # 1. id
    $id = $node.id
    if ([string]::IsNullOrWhiteSpace($id)) {
        [void]$errors.Add(@{
            type = "MISSING_FIELD"
            index = $idx
            field = "id"
            message = "Node at index $idx is missing required field 'id'."
        })
    } else {
        if (-not ($id -match '^\d+(\.\d+)+$')) {
            [void]$errors.Add(@{
                type = "INVALID_ID_FORMAT"
                node_id = $id
                field = "id"
                message = "Node ID '$id' does not match required format (e.g. '1.1', '2.3')."
            })
        }
        if ($idSet.Contains($id)) {
            [void]$errors.Add(@{
                type = "DUPLICATE_ID"
                node_id = $id
                field = "id"
                message = "Duplicate node ID '$id'."
            })
        } else {
            [void]$idSet.Add($id)
        }
    }

    # 2. label
    if ([string]::IsNullOrWhiteSpace($node.label)) {
        [void]$errors.Add(@{
            type = "MISSING_FIELD"
            node_id = $id
            field = "label"
            message = "Node '$id' is missing or has empty 'label'."
        })
    }

    # 3. module
    if ([string]::IsNullOrWhiteSpace($node.module)) {
        [void]$errors.Add(@{
            type = "MISSING_FIELD"
            node_id = $id
            field = "module"
            message = "Node '$id' is missing or has empty 'module'."
        })
    }

    # 4. teaches
    if ($node.PSObject.Properties.Name -notcontains "teaches" -or $node.teaches -isnot [array]) {
        [void]$errors.Add(@{
            type = "INVALID_TEACHES"
            node_id = $id
            field = "teaches"
            message = "Node '$id' 'teaches' must be a non-empty array of concept strings."
        })
    } elseif ($node.teaches.Count -eq 0) {
        [void]$errors.Add(@{
            type = "EMPTY_TEACHES"
            node_id = $id
            field = "teaches"
            message = "Node '$id' 'teaches' array is empty. Every node must teach at least 1 concept."
        })
    } else {
        $totalTeaches += $node.teaches.Count
        foreach ($t in $node.teaches) {
            if ([string]::IsNullOrWhiteSpace("$t")) {
                [void]$errors.Add(@{
                    type = "EMPTY_TEACHES_ITEM"
                    node_id = $id
                    field = "teaches"
                    message = "Node '$id' contains an empty concept string in 'teaches'."
                })
            }
        }
    }

    # 5. requires
    if ($node.PSObject.Properties.Name -notcontains "requires" -or $node.requires -isnot [array]) {
        [void]$errors.Add(@{
            type = "INVALID_REQUIRES"
            node_id = $id
            field = "requires"
            message = "Node '$id' 'requires' must be an array (use [] if no prerequisites)."
        })
    } else {
        $totalRequires += $node.requires.Count
    }

    # 6. blackbox_terms
    if ($node.PSObject.Properties.Name -contains "blackbox_terms" -and $null -ne $node.blackbox_terms) {
        if ($node.blackbox_terms -isnot [array]) {
            [void]$errors.Add(@{
                type = "INVALID_BLACKBOX_TERMS"
                node_id = $id
                field = "blackbox_terms"
                message = "Node '$id' 'blackbox_terms' must be an array."
            })
        } else {
            for ($b = 0; $b -lt $node.blackbox_terms.Count; $b++) {
                $bt = $node.blackbox_terms[$b]
                if ([string]::IsNullOrWhiteSpace($bt.term) -or [string]::IsNullOrWhiteSpace($bt.purpose)) {
                    [void]$errors.Add(@{
                        type = "INVALID_BLACKBOX_ITEM"
                        node_id = $id
                        index = ($b + 1)
                        message = "Node '$id' blackbox_terms at index $($b+1) must contain non-empty 'term' and 'purpose'."
                    })
                }
            }
            $totalBlackbox += $node.blackbox_terms.Count
        }
    }
}

if ($errors.Count -gt 0) {
    Output-Fail $errors.ToArray()
}

# Output normalized JSON data file (UTF-8 No BOM)
$outFullPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path (Get-Location).Path $OutputFile }
$cleanData = @{
    nodes = $nodes
}
$jsonOutput = $cleanData | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($outFullPath, $jsonOutput, (New-Object System.Text.UTF8Encoding $false))

# Standard JSON response to stdout
$response = @{
    success     = $true
    step        = 1
    output_file = $OutputFile
    stats       = @{
        node_count          = $nodes.Count
        raw_teaches_count   = $totalTeaches
        raw_requires_count  = $totalRequires
        blackbox_term_count = $totalBlackbox
    }
}
$response | ConvertTo-Json -Depth 5 -Compress:$false
