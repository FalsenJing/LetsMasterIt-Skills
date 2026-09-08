<#
.SYNOPSIS
    Get Node Info Script for lmi-plan-skill in Duonav LMI Ecosystem.
    Fetches target learning node metadata, concept coverage (teaches), prerequisite concepts (requires),
    and edge dependency reasons required to draft a secondary syllabus teaching plan.
    Target node is determined by Duonav's live selected_node in knowledge_graph.json, or via optional -NodeId override.
#>

[CmdletBinding()]
param(
    [Alias("s")]
    [string]$Subject,

    [Alias("n")]
    [string]$NodeId,

    [Alias("o")]
    [string]$OutputFile
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Output-Fail {
    param(
        [string]$ErrorType,
        [string]$Message,
        [hashtable]$Extra = @{}
    )
    $res = [ordered]@{
        success = $false
        action  = "get_node_info"
        error   = $ErrorType
        message = $Message
    }
    foreach ($k in $Extra.Keys) {
        $res[$k] = $Extra[$k]
    }
    $res | ConvertTo-Json -Depth 6 -Compress:$false
    exit 1
}

function Get-WorkspaceRoot {
    # Search upwards from script directory to locate 'knowledge_graphs'
    $dir = $PSScriptRoot
    while ($dir -and (Test-Path $dir)) {
        if (Test-Path (Join-Path $dir "knowledge_graphs")) {
            return (Resolve-Path $dir).Path
        }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    # Fallback to current working directory
    $cwd = (Get-Location).Path
    if (Test-Path (Join-Path $cwd "knowledge_graphs")) {
        return (Resolve-Path $cwd).Path
    }
    # Fallback: 4 levels up from $PSScriptRoot
    if ($PSScriptRoot) {
        $candidate = (Resolve-Path (Join-Path $PSScriptRoot "../../../..") -ErrorAction SilentlyContinue)
        if ($candidate) { return $candidate.Path }
    }
    return $cwd
}

$wsRoot = Get-WorkspaceRoot

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $raw = [System.IO.File]::ReadAllText((Resolve-Path $Path).Path, [System.Text.Encoding]::UTF8)
    if ($raw.Length -gt 0 -and [int]$raw[0] -eq 0xFEFF) {
        $raw = $raw.Substring(1)
    }
    return ($raw | ConvertFrom-Json)
}

function Write-JsonFileAtomic {
    param([string]$Path, [object]$Data)
    $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $wsRoot $Path }
    $dir = [System.IO.Path]::GetDirectoryName($fullPath)
    if ($dir -and -not (Test-Path $dir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }
    $tempPath = "$fullPath.tmp.$([System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
    $json = $Data | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding $false))
    Move-Item -Path $tempPath -Destination $fullPath -Force
}

# 1. Resolve Active Subject
$activeSubject = $Subject
if ([string]::IsNullOrWhiteSpace($activeSubject)) {
    $pointerPath = Join-Path $wsRoot "knowledge_graphs/active_subject.json"
    $pointerData = Read-JsonFile $pointerPath
    if ($pointerData -and -not [string]::IsNullOrWhiteSpace($pointerData.active_subject)) {
        $activeSubject = $pointerData.active_subject.Trim()
    }
}

# Fallback check
$graphRelPath = if ($activeSubject) {
    Join-Path $wsRoot "knowledge_graphs/$activeSubject/knowledge_graph.json"
} else {
    Join-Path $wsRoot "knowledge_graph.json"
}

if (-not (Test-Path $graphRelPath)) {
    Output-Fail -ErrorType "GRAPH_NOT_FOUND" -Message "Knowledge graph file not found: '$graphRelPath'. Please verify subject name or initialize the knowledge graph first." -Extra @{
        active_subject = $activeSubject
        target_path    = $graphRelPath
        workspace_root = $wsRoot
    }
}

# 2. Read Graph Data
$graph = Read-JsonFile $graphRelPath
if ($null -eq $graph -or $null -eq $graph.nodes) {
    Output-Fail -ErrorType "INVALID_GRAPH_DATA" -Message "Knowledge graph file '$graphRelPath' is corrupted or missing 'nodes' array." -Extra @{
        workspace_root = $wsRoot
    }
}

# 3. Determine Target Node ID (Priority: CLI override > Duonav GUI selected_node)
$targetId = if (-not [string]::IsNullOrWhiteSpace($NodeId)) { $NodeId.Trim() } else { "$($graph.selected_node)".Trim() }

if ([string]::IsNullOrWhiteSpace($targetId) -or $targetId -eq "null") {
    Output-Fail -ErrorType "NO_SELECTED_NODE" -Message "No active learning node selected in subject '$activeSubject'. Please select a node in Duonav desktop app, or specify a node ID (e.g. 1.3) directly in chat." -Extra @{
        active_subject = $activeSubject
    }
}

# 4. Find Target Node in Graph
$nodes = @($graph.nodes)
$targetNode = $nodes | Where-Object { "$($_.id)".Trim() -eq $targetId } | Select-Object -First 1

if ($null -eq $targetNode) {
    $allIds = ($nodes | ForEach-Object { "$($_.id)" }) -join ', '
    Output-Fail -ErrorType "NODE_NOT_FOUND" -Message "Node ID '$targetId' not found in subject '$activeSubject'. Available node IDs: [$allIds]" -Extra @{
        active_subject = $activeSubject
        target_id      = $targetId
    }
}

# If user specified NodeId and it differs from graph.selected_node, atomically update graph.selected_node
$persistedUpdate = $false
if (-not [string]::IsNullOrWhiteSpace($NodeId) -and "$($graph.selected_node)" -ne $targetId) {
    $graph.selected_node = $targetId
    if ($graph.meta) {
        $graph.meta.last_updated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    }
    Write-JsonFileAtomic -Path $graphRelPath -Data $graph
    $persistedUpdate = $true
}

# 5. Compute Module / Chapter Position
$moduleName = if ($targetNode.module) { "$($targetNode.module)".Trim() } else { "General" }
$moduleNodes = @($nodes | Where-Object { ("$($_.module)".Trim()) -eq $moduleName })
$nodeIdxInModule = 1
for ($m = 0; $m -lt $moduleNodes.Count; $m++) {
    if ("$($moduleNodes[$m].id)".Trim() -eq $targetId) {
        $nodeIdxInModule = $m + 1
        break
    }
}

$cOpen = [char]0x3010
$cClose = [char]0x3011
$cDot = [char]0x00B7
$positionSummary = if ($moduleNodes.Count -gt 0) {
    "$cOpen$activeSubject$cClose$cDot$cOpen$($targetNode.label)$cClose, $cOpen$moduleName$cClose ($nodeIdxInModule/$($moduleNodes.Count))"
} else {
    "$cOpen$activeSubject$cClose$cDot$cOpen$($targetNode.label)$cClose"
}

# 6. Build Concept Lookup Map
$conceptMap = [System.Collections.Generic.Dictionary[string, psobject]]::new()
if ($graph.concept_dictionary) {
    foreach ($c in $graph.concept_dictionary) {
        if (-not [string]::IsNullOrWhiteSpace("$($c.id)")) {
            $conceptMap["$($c.id)".Trim()] = $c
        }
    }
}

# 7. Resolve Teaches Concepts (Concepts taught in this node)
$teachesResolved = [System.Collections.ArrayList]::new()
if ($targetNode.teaches) {
    foreach ($cid in $targetNode.teaches) {
        $cidStr = "$cid".Trim()
        if ($conceptMap.ContainsKey($cidStr)) {
            $cObj = $conceptMap[$cidStr]
            [void]$teachesResolved.Add([ordered]@{
                id        = $cidStr
                canonical = $cObj.canonical
                aliases   = if ($cObj.aliases) { @($cObj.aliases) } else { @() }
            })
        } else {
            [void]$teachesResolved.Add([ordered]@{
                id        = $cidStr
                canonical = $cidStr
                aliases   = @()
            })
        }
    }
}

# 8. Resolve Requires Concepts & Edge Reasons (Prerequisites required by this node)
$edges = if ($graph.edges) { @($graph.edges) } else { @() }
$prereqEdges = @($edges | Where-Object { "$($_.to)".Trim() -eq $targetId -and "$($_.type)".Trim() -eq "prerequisite" })

$requiresResolved = [System.Collections.ArrayList]::new()
if ($targetNode.requires) {
    foreach ($cid in $targetNode.requires) {
        $cidStr = "$cid".Trim()
        $cObj = if ($conceptMap.ContainsKey($cidStr)) { $conceptMap[$cidStr] } else { $null }
        $canonical = if ($cObj) { $cObj.canonical } else { $cidStr }
        $aliases = if ($cObj -and $cObj.aliases) { @($cObj.aliases) } else { @() }
        $taughtBy = if ($cObj) { "$($cObj.taught_by)".Trim() } else { "" }

        # Find matching prerequisite edge for dependency reason
        $edge = $prereqEdges | Where-Object { "$($_.via_concept)".Trim() -eq $cidStr } | Select-Object -First 1
        if (-not $edge -and $taughtBy) {
            $edge = $prereqEdges | Where-Object { "$($_.from)".Trim() -eq $taughtBy } | Select-Object -First 1
        }
        $edgeReason = if ($edge -and $edge.reason) {
            "$($edge.reason)".Trim()
        } else {
            "[$($targetNode.label)] requires [$canonical]"
        }

        $fromNode = if ($taughtBy) { $nodes | Where-Object { "$($_.id)".Trim() -eq $taughtBy } | Select-Object -First 1 } else { $null }
        $fromNodeLabel = if ($fromNode) { "$($fromNode.label)".Trim() } else { $taughtBy }

        [void]$requiresResolved.Add([ordered]@{
            id              = $cidStr
            canonical       = $canonical
            aliases         = $aliases
            taught_by       = $taughtBy
            from_node_label = $fromNodeLabel
            edge_reason     = $edgeReason
        })
    }
}

# 9. Format Safe Output Filename & Suggested Path
$safeLabel = "$($targetNode.label)" -replace '[/\\:\*\?\"<>\|]', '_'
$planSuffix = '-' + [char]0x8BA1 + [char]0x5212 + '.md'
$suggestedPlanPath = "teaching_plans/$activeSubject/$targetId $safeLabel$planSuffix"

# 10. Assemble Output JSON
$response = [ordered]@{
    success             = $true
    action              = "get_node_info"
    active_subject      = $activeSubject
    selected_node_id    = $targetId
    persisted_update    = $persistedUpdate
    node                = [ordered]@{
        id              = $targetId
        label           = "$($targetNode.label)"
        safe_label      = $safeLabel
        module          = $moduleName
        status          = "$($targetNode.status)"
        blackbox_terms  = if ($targetNode.blackbox_terms) { @($targetNode.blackbox_terms) } else { @() } # [RESERVED] 预留字段，消费方式待定，当前无技能消费
        position_summary = $positionSummary
    }
    teaches_concepts    = $teachesResolved.ToArray()
    requires_concepts   = $requiresResolved.ToArray()
    suggested_plan_path = $suggestedPlanPath
}

$jsonText = $response | ConvertTo-Json -Depth 6 -Compress:$false

if ($OutputFile) {
    [System.IO.File]::WriteAllText($OutputFile, $jsonText, (New-Object System.Text.UTF8Encoding $false))
}

$jsonText
