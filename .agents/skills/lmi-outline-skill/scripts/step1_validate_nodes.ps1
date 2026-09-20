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
        @{
            type       = "FILE_NOT_FOUND"
            message    = "Input file '$InputFile' not found."
            suggestion = "Ensure the draft file '$InputFile' is created in the working directory before running this validation script."
        }
    )
}

try {
    $rawContent = [System.IO.File]::ReadAllText((Resolve-Path $InputFile).Path, [System.Text.Encoding]::UTF8)
    $data = $rawContent | ConvertFrom-Json
}
catch {
    Output-Fail @(
        @{
            type       = "JSON_SYNTAX_ERROR"
            message    = "Failed to parse JSON: $($_.Exception.Message)"
            suggestion = "Check JSON syntax in '$InputFile': ensure valid double quotes for keys and strings, remove trailing commas, and match braces."
        }
    )
}

$nodes = @()
if ($data -is [array]) {
    $nodes = $data
} elseif ($data.PSObject.Properties.Name -contains "nodes" -and $data.nodes -is [array]) {
    $nodes = $data.nodes
} else {
    Output-Fail @(
        @{
            type       = "STRUCTURE_ERROR"
            message    = "Top-level JSON must be an array of nodes or an object with a 'nodes' array."
            suggestion = "In '$InputFile', format the root structure as an object containing a 'nodes' array: { 'nodes': [ ... ] }."
        }
    )
}

if ($nodes.Count -eq 0) {
    Output-Fail @(
        @{
            type       = "EMPTY_NODES"
            message    = "Nodes array is empty."
            suggestion = "In '$InputFile', add at least one valid node object to the 'nodes' array."
        }
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
            type       = "INVALID_NODE_OBJECT"
            index      = $idx
            message    = "Node at index $idx is not a valid JSON object."
            suggestion = "In '$InputFile', fix item at index $idx to be a valid JSON object { ... }."
        })
        continue
    }

    # 1. id
    $id = $node.id
    if ([string]::IsNullOrWhiteSpace($id)) {
        [void]$errors.Add(@{
            type       = "MISSING_FIELD"
            index      = $idx
            field      = "id"
            message    = "Node at index $idx is missing required field 'id'."
            suggestion = "In '$InputFile', add an 'id' field matching dot-separated hierarchy format (e.g. '1.1', '2.3') to node at index $idx."
        })
    } else {
        if (-not ($id -match '^\d+(\.\d+)+$')) {
            [void]$errors.Add(@{
                type       = "INVALID_ID_FORMAT"
                node_id    = $id
                field      = "id"
                message    = "Node ID '$id' does not match required format (e.g. '1.1', '2.3')."
                suggestion = "In '$InputFile', change node '$id' 'id' field to match dot-separated hierarchy format (e.g. '1.1', '2.3'). Do not use Chinese or letters."
            })
        }
        if ($idSet.Contains($id)) {
            [void]$errors.Add(@{
                type       = "DUPLICATE_ID"
                node_id    = $id
                field      = "id"
                message    = "Duplicate node ID '$id'."
                suggestion = "In '$InputFile', assign a globally unique hierarchy ID to duplicate node '$id'."
            })
        } else {
            [void]$idSet.Add($id)
        }
    }

    # 2. label
    if ([string]::IsNullOrWhiteSpace($node.label)) {
        [void]$errors.Add(@{
            type       = "MISSING_FIELD"
            node_id    = $id
            field      = "label"
            message    = "Node '$id' is missing or has empty 'label'."
            suggestion = "In '$InputFile', add a non-empty 'label' field describing the academic concept name to node '$id'."
        })
    }

    # 3. module
    if ([string]::IsNullOrWhiteSpace($node.module)) {
        [void]$errors.Add(@{
            type       = "MISSING_FIELD"
            node_id    = $id
            field      = "module"
            message    = "Node '$id' is missing or has empty 'module'."
            suggestion = "In '$InputFile', add a non-empty 'module' field describing chapter/module name to node '$id'."
        })
    }

    # 4. teaches
    if ($node.PSObject.Properties.Name -notcontains "teaches" -or $node.teaches -isnot [array]) {
        [void]$errors.Add(@{
            type       = "INVALID_TEACHES"
            node_id    = $id
            field      = "teaches"
            message    = "Node '$id' 'teaches' must be a non-empty array of concept strings."
            suggestion = "In '$InputFile', define 'teaches' as an array of strings with at least 1 concept for node '$id'."
        })
    } elseif ($node.teaches.Count -eq 0) {
        [void]$errors.Add(@{
            type       = "EMPTY_TEACHES"
            node_id    = $id
            field      = "teaches"
            message    = "Node '$id' 'teaches' array is empty. Every node must teach at least 1 concept."
            suggestion = "In '$InputFile', add at least 1 concept string to the 'teaches' array of node '$id'."
        })
    } else {
        $totalTeaches += $node.teaches.Count
        foreach ($t in $node.teaches) {
            if ([string]::IsNullOrWhiteSpace("$t")) {
                [void]$errors.Add(@{
                    type       = "EMPTY_TEACHES_ITEM"
                    node_id    = $id
                    field      = "teaches"
                    message    = "Node '$id' contains an empty concept string in 'teaches'."
                    suggestion = "In '$InputFile', remove empty items or provide valid concept strings in 'teaches' for node '$id'."
                })
            }
        }
    }

    # 5. requires
    if ($node.PSObject.Properties.Name -notcontains "requires" -or $node.requires -isnot [array]) {
        [void]$errors.Add(@{
            type       = "INVALID_REQUIRES"
            node_id    = $id
            field      = "requires"
            message    = "Node '$id' 'requires' must be an array (use [] if no prerequisites)."
            suggestion = "In '$InputFile', define 'requires' as an array of strings for node '$id' (use [] if no prerequisites)."
        })
    } else {
        $totalRequires += $node.requires.Count
    }

    # 6. blackbox_terms
    if ($node.PSObject.Properties.Name -contains "blackbox_terms" -and $null -ne $node.blackbox_terms) {
        if ($node.blackbox_terms -isnot [array]) {
            [void]$errors.Add(@{
                type       = "INVALID_BLACKBOX_TERMS"
                node_id    = $id
                field      = "blackbox_terms"
                message    = "Node '$id' 'blackbox_terms' must be an array."
                suggestion = "In '$InputFile', define 'blackbox_terms' as an array for node '$id' (use [] if no blackbox terms)."
            })
        } else {
            for ($b = 0; $b -lt $node.blackbox_terms.Count; $b++) {
                $bt = $node.blackbox_terms[$b]
                if ([string]::IsNullOrWhiteSpace($bt.term) -or [string]::IsNullOrWhiteSpace($bt.purpose)) {
                    [void]$errors.Add(@{
                        type       = "INVALID_BLACKBOX_ITEM"
                        node_id    = $id
                        index      = ($b + 1)
                        message    = "Node '$id' blackbox_terms at index $($b+1) must contain non-empty 'term' and 'purpose'."
                        suggestion = "In '$InputFile', provide non-empty 'term' and 'purpose' strings for blackbox_terms item at index $($b+1) in node '$id'."
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
