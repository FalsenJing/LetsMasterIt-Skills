<#
.SYNOPSIS
    Infrastructure probe script for GEMINI.md routing in Duonav LMI Ecosystem.
    Resolves active subject, targets learning node, checks prerequisite completion,
    atomically persists selected_node if overridden, and detects teaching plan existence.
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
        action  = "get_knowledge_graph"
        error   = $ErrorType
        message = $Message
    }
    foreach ($k in $Extra.Keys) {
        $res[$k] = $Extra[$k]
    }
    $json = $res | ConvertTo-Json -Depth 6 -Compress:$false
    if ($OutputFile) {
        [System.IO.File]::WriteAllText($OutputFile, $json, (New-Object System.Text.UTF8Encoding $false))
    }
    $json
    exit 1
}

function Get-WorkspaceRoot {
    $dir = $PSScriptRoot
    while ($dir -and (Test-Path $dir)) {
        if (Test-Path (Join-Path $dir "knowledge_graphs")) {
            return (Resolve-Path $dir).Path
        }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    $cwd = (Get-Location).Path
    if (Test-Path (Join-Path $cwd "knowledge_graphs")) {
        return (Resolve-Path $cwd).Path
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
        $activeSubject = "$($pointerData.active_subject)".Trim()
    }
}

$graphRelPath = if ($activeSubject) {
    Join-Path $wsRoot "knowledge_graphs/$activeSubject/knowledge_graph.json"
} else {
    Join-Path $wsRoot "knowledge_graph.json"
}

if (-not (Test-Path $graphRelPath)) {
    Output-Fail -ErrorType "GRAPH_NOT_FOUND" -Message "未检测到学科【$activeSubject】的知识图谱文件：'$graphRelPath'。" -Extra @{
        active_subject = $activeSubject
        target_path    = $graphRelPath
        workspace_root = $wsRoot
    }
}

# 2. Read Graph Data
$graph = Read-JsonFile $graphRelPath
if ($null -eq $graph -or $null -eq $graph.nodes) {
    Output-Fail -ErrorType "INVALID_GRAPH_DATA" -Message "知识图谱文件 '$graphRelPath' 数据损坏或缺少 'nodes' 列表。" -Extra @{
        workspace_root = $wsRoot
    }
}

# 3. Determine Target Node ID
$targetId = if (-not [string]::IsNullOrWhiteSpace($NodeId)) { $NodeId.Trim() } else { "$($graph.selected_node)".Trim() }

if ([string]::IsNullOrWhiteSpace($targetId) -or $targetId -eq "null") {
    Output-Fail -ErrorType "NO_SELECTED_NODE" -Message "当前学科【$activeSubject】未检测到选中的学习节点。请先在 Duonav 桌面端点击目标节点，或直接在对话中指定你想学习的节点 ID（例如：1.3）。" -Extra @{
        active_subject = $activeSubject
    }
}

# 4. Lookup Target Node in Graph
$nodes = @($graph.nodes)
$targetNode = $nodes | Where-Object { "$($_.id)".Trim() -eq $targetId } | Select-Object -First 1

if ($null -eq $targetNode) {
    $allIds = ($nodes | ForEach-Object { "$($_.id)" }) -join ', '
    Output-Fail -ErrorType "NODE_NOT_FOUND" -Message "在学科【$activeSubject】中未找到节点 ID【$targetId】。可选节点 ID 列表: [$allIds]" -Extra @{
        active_subject     = $activeSubject
        target_id          = $targetId
        available_node_ids = @($nodes | ForEach-Object { "$($_.id)" })
    }
}

# 5. Atomically update selected_node if overridden by CLI parameter
$persistedUpdate = $false
if (-not [string]::IsNullOrWhiteSpace($NodeId) -and "$($graph.selected_node)" -ne $targetId) {
    $graph.selected_node = $targetId
    if ($graph.meta) {
        $graph.meta.last_updated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    }
    Write-JsonFileAtomic -Path $graphRelPath -Data $graph
    $persistedUpdate = $true
}

# 6. Compute Module & Position
$moduleName = if ($targetNode.module) { "$($targetNode.module)".Trim() } else { "常规" }
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

# 7. Check Prerequisites & Edges
$edges = if ($graph.edges) { @($graph.edges) } else { @() }
$prereqEdges = @($edges | Where-Object { "$($_.to)".Trim() -eq $targetId -and "$($_.type)".Trim() -eq "prerequisite" })

$completedPrereqs = [System.Collections.ArrayList]::new()
$uncompletedPrereqs = [System.Collections.ArrayList]::new()

foreach ($edge in $prereqEdges) {
    $fromId = "$($edge.from)".Trim()
    $fromNode = $nodes | Where-Object { "$($_.id)".Trim() -eq $fromId } | Select-Object -First 1
    $fromLabel = if ($fromNode) { "$($fromNode.label)".Trim() } else { $fromId }
    $fromStatus = if ($fromNode) { "$($fromNode.status)".Trim() } else { "unknown" }

    $prereqInfo = [ordered]@{
        id     = $fromId
        label  = $fromLabel
        status = $fromStatus
        reason = if ($edge.reason) { "$($edge.reason)".Trim() } else { "" }
    }

    if ($fromStatus -eq "completed") {
        [void]$completedPrereqs.Add($prereqInfo)
    } else {
        [void]$uncompletedPrereqs.Add($prereqInfo)
    }
}

$allPrereqsCompleted = ($uncompletedPrereqs.Count -eq 0)
$isLocked = ("$($targetNode.status)".Trim() -eq "locked")

# 8. Check Teaching Plan Existence (Accurate prefix matching with space separator)
$planDir = Join-Path $wsRoot "teaching_plans/$activeSubject"
$hasPlan = $false
$planFile = $null

if (Test-Path $planDir) {
    $escapedId = [regex]::Escape($targetId)
    $pattern = "^$escapedId\s.*\.md$"
    $matched = Get-ChildItem -Path $planDir -File | Where-Object { $_.Name -match $pattern } | Select-Object -First 1
    if ($matched) {
        $hasPlan = $true
        $planFile = "teaching_plans/$activeSubject/$($matched.Name)"
    }
}

$safeLabel = "$($targetNode.label)"
foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
    $safeLabel = $safeLabel.Replace($c, '_')
}
$suggestedPlanPath = "teaching_plans/$activeSubject/$targetId $safeLabel-计划.md"

# 9. Output Clean Structured Response
$response = [ordered]@{
    success               = $true
    action                = "get_knowledge_graph"
    active_subject        = $activeSubject
    target_id             = $targetId
    persisted_update      = $persistedUpdate
    node                  = [ordered]@{
        id               = $targetId
        label            = "$($targetNode.label)"
        safe_label       = $safeLabel
        module           = $moduleName
        module_index     = $nodeIdxInModule
        module_total     = $moduleNodes.Count
        status           = "$($targetNode.status)"
        position_summary = $positionSummary
    }
    prerequisites         = [ordered]@{
        all_completed     = $allPrereqsCompleted
        is_locked         = $isLocked
        completed_nodes   = $completedPrereqs.ToArray()
        uncompleted_nodes = $uncompletedPrereqs.ToArray()
    }
    plan                  = [ordered]@{
        has_plan            = $hasPlan
        plan_file           = $planFile
        suggested_plan_path = $suggestedPlanPath
    }
}

$jsonText = $response | ConvertTo-Json -Depth 6 -Compress:$false

if ($OutputFile) {
    [System.IO.File]::WriteAllText($OutputFile, $jsonText, (New-Object System.Text.UTF8Encoding $false))
}

$jsonText
