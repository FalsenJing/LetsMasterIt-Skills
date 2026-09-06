<#
.SYNOPSIS
    Step 3 core script: automatically generate edges from concept dependencies, strictly detect directed cycles via topological sort, calculate graph metrics, and assemble knowledge_graph.json.
    Standard JSON output protocol: All edge metrics and cycle detection results are output to stdout as pure JSON.
#>

[CmdletBinding()]
param(
    [Alias("i")]
    [string]$InputFile = "step2_concepts.json",

    [Alias("o")]
    [string]$OutputFile = "knowledge_graph.json",

    [string]$Subject = "",

    [string[]]$References = @()
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Output-Fail {
    param([array]$Errors)
    $res = @{
        success = $false
        step    = 3
        errors  = $Errors
    }
    $res | ConvertTo-Json -Depth 6 -Compress:$false
    exit 1
}

if (-not (Test-Path $InputFile)) {
    Output-Fail @(
        @{ type = "FILE_NOT_FOUND"; message = "Input file '$InputFile' not found. Ensure Step 2 completed successfully." }
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

if ($null -eq $data.concept_dictionary -or $null -eq $data.nodes) {
    Output-Fail @(
        @{ type = "MISSING_STRUCTURE"; message = "Input data missing 'concept_dictionary' or 'nodes'." }
    )
}

$nodes = $data.nodes
$concepts = $data.concept_dictionary

$nodeMap = [System.Collections.Generic.Dictionary[string, psobject]]::new()
$adjList = [System.Collections.Generic.Dictionary[string, [System.Collections.Generic.List[string]]]]::new()
$inDegree = [System.Collections.Generic.Dictionary[string, int]]::new()

foreach ($n in $nodes) {
    $nodeMap[$n.id] = $n
    $adjList[$n.id] = [System.Collections.Generic.List[string]]::new()
    $inDegree[$n.id] = 0
}

$conceptMap = [System.Collections.Generic.Dictionary[string, psobject]]::new()
foreach ($c in $concepts) {
    $conceptMap[$c.id] = $c
}

# 1. Automatically generate edges
$edges = [System.Collections.ArrayList]::new()
$edgeKeySet = [System.Collections.Generic.HashSet[string]]::new()
$edgeErrors = [System.Collections.ArrayList]::new()

foreach ($targetNode in $nodes) {
    $toId = $targetNode.id
    if ($targetNode.PSObject.Properties.Name -contains "requires" -and $targetNode.requires -is [array]) {
        foreach ($cid in $targetNode.requires) {
            if (-not $conceptMap.ContainsKey("$cid")) {
                [void]$edgeErrors.Add(@{
                    type = "UNRESOLVED_CONCEPT"
                    node_id = $toId
                    concept_id = "$cid"
                    message = "Node '$toId' requires concept '$cid' not found in dictionary."
                })
                continue
            }
            $concept = $conceptMap["$cid"]
            $fromId = $concept.taught_by
            if ($fromId -eq $toId) {
                [void]$edgeErrors.Add(@{
                    type = "SELF_DEPENDENCY"
                    node_id = $toId
                    concept_id = "$cid"
                    message = "Node '$toId' has self-dependency on concept '$cid'."
                })
                continue
            }

            $edgeKey = "$fromId->$toId"
            if (-not $edgeKeySet.Contains($edgeKey)) {
                [void]$edgeKeySet.Add($edgeKey)
                $edgeObj = @{
                    from        = $fromId
                    to          = $toId
                    type        = "prerequisite"
                    via_concept = $concept.id
                    reason      = "[{0}] requires [{1}]" -f $targetNode.label, $concept.canonical
                }
                [void]$edges.Add($edgeObj)
                $adjList[$fromId].Add($toId)
                $inDegree[$toId]++
            }
        }
    }
}

if ($edgeErrors.Count -gt 0) {
    Output-Fail $edgeErrors.ToArray()
}

# 2. Cycle detection (Kahn's Algorithm topological sort)
$queue = [System.Collections.Generic.Queue[string]]::new()
$inDegreeCopy = [System.Collections.Generic.Dictionary[string, int]]::new()
foreach ($k in $inDegree.Keys) {
    $inDegreeCopy[$k] = $inDegree[$k]
    if ($inDegree[$k] -eq 0) {
        $queue.Enqueue($k)
    }
}

$topoOrder = [System.Collections.Generic.List[string]]::new()
while ($queue.Count -gt 0) {
    $u = $queue.Dequeue()
    $topoOrder.Add($u)
    foreach ($v in $adjList[$u]) {
        $inDegreeCopy[$v]--
        if ($inDegreeCopy[$v] -eq 0) {
            $queue.Enqueue($v)
        }
    }
}

if ($topoOrder.Count -ne $nodes.Count) {
    $cycleNodes = @()
    foreach ($k in $inDegreeCopy.Keys) {
        if ($inDegreeCopy[$k] -gt 0) {
            $cycleNodes += $k
        }
    }
    Output-Fail @(
        @{
            type        = "CYCLE_DETECTED"
            cycle_nodes = $cycleNodes
            message     = "Cycle detected in knowledge graph. Topological sort failed. Involving nodes: $($cycleNodes -join ', ')."
        }
    )
}

# 3. Dynamic programming for critical path and parallelism
$dist = [System.Collections.Generic.Dictionary[string, int]]::new()
$prevNode = [System.Collections.Generic.Dictionary[string, string]]::new()
foreach ($nid in $nodes) {
    $dist[$nid.id] = 1
    $prevNode[$nid.id] = $null
}

foreach ($u in $topoOrder) {
    foreach ($v in $adjList[$u]) {
        if ($dist[$u] + 1 -gt $dist[$v]) {
            $dist[$v] = $dist[$u] + 1
            $prevNode[$v] = $u
        }
    }
}

$maxDist = 1
$endNode = $topoOrder[0]
foreach ($nid in $dist.Keys) {
    if ($dist[$nid] -gt $maxDist) {
        $maxDist = $dist[$nid]
        $endNode = $nid
    }
}

$path = [System.Collections.Generic.List[string]]::new()
$curr = $endNode
while ($null -ne $curr -and $curr -ne "") {
    $path.Add($curr)
    $curr = $prevNode[$curr]
}
$path.Reverse()

$parallelism = [Math]::Round(($nodes.Count / [double]$maxDist), 2)

# 4. Isolated nodes check
$isolatedNodes = @()
foreach ($n in $nodes) {
    if ($inDegree[$n.id] -eq 0 -and $adjList[$n.id].Count -eq 0) {
        $isolatedNodes += $n.id
    }
}

# 5. Assemble and write knowledge_graph.json
$finalSubject = if ($Subject) { $Subject } elseif ($data.meta -and $data.meta.subject) { $data.meta.subject } else { "General Subject" }
$finalRefs = if ($References.Count -gt 0) { $References } elseif ($data.meta -and $data.meta.references) { $data.meta.references } else { @("Standard Textbook") }

$finalMeta = @{
    subject      = $finalSubject
    version      = "2.0"
    last_updated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    references   = $finalRefs
}

foreach ($n in $nodes) {
    if ($n.PSObject.Properties.Name -notcontains "status" -or [string]::IsNullOrWhiteSpace($n.status)) {
        $initStatus = if ($inDegree[$n.id] -eq 0) { "available" } else { "locked" }
        $n | Add-Member -MemberType NoteProperty -Name "status" -Value $initStatus -Force
    }
}

$finalJsonObj = @{
    meta               = $finalMeta
    concept_dictionary = $concepts
    nodes              = $nodes
    edges              = $edges
    error_log          = @()
    difficulty_log     = @()
    selected_node      = $null
}

$outFullPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path (Get-Location).Path $OutputFile }
$outDir = [System.IO.Path]::GetDirectoryName($outFullPath)
if ($outDir -and -not (Test-Path $outDir)) {
    [System.IO.Directory]::CreateDirectory($outDir) | Out-Null
}
$finalJsonText = $finalJsonObj | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($outFullPath, $finalJsonText, (New-Object System.Text.UTF8Encoding $false))

# Standard JSON response to stdout
$response = @{
    success     = $true
    step        = 3
    output_file = $OutputFile
    metrics     = @{
        node_count           = $nodes.Count
        edge_count           = $edges.Count
        is_dag               = $true
        critical_path_length = $maxDist
        critical_path        = $path.ToArray()
        parallelism          = $parallelism
        is_healthy           = ($parallelism -ge 1.5)
        isolated_nodes       = $isolatedNodes
    }
}
$response | ConvertTo-Json -Depth 5 -Compress:$false
