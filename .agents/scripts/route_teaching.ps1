<#
.SYNOPSIS
    Deterministic Routing Engine for Duonav LMI Ecosystem.
    Acts as the single source of truth for turn-start gateway dispatching.
    Inspects active subject, verifies knowledge graph, targets learning node,
    evaluates prerequisites and jumping-mode, detects teaching plan existence,
    and returns an unambiguous "Verdict Packet" to GEMINI.md.
#>

[CmdletBinding()]
param(
    [Alias("s")]
    [string]$Subject,

    [Alias("n")]
    [string]$NodeId,

    [Alias("r")]
    [switch]$Replan,

    [Alias("nm")]
    [switch]$NonMath,

    [Alias("st")]
    [string]$SubjectType,

    [Alias("o")]
    [string]$OutputFile
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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
    if ($PSScriptRoot) {
        $candidate = (Resolve-Path (Join-Path $PSScriptRoot "../..") -ErrorAction SilentlyContinue)
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

function Send-Verdict {
    param(
        [string]$Action,
        [hashtable]$Payload
    )
    $verdict = [ordered]@{
        success = $true
        action  = $Action
    }
    foreach ($k in $Payload.Keys) {
        $verdict[$k] = $Payload[$k]
    }
    $jsonText = $verdict | ConvertTo-Json -Depth 6 -Compress:$false
    if ($OutputFile) {
        [System.IO.File]::WriteAllText($OutputFile, $jsonText, (New-Object System.Text.UTF8Encoding $false))
    }
    $jsonText
    exit 0
}

# ===================================================================
# Stage 1: Active Subject & Graph Existence Verification
# ===================================================================
$activeSubject = $Subject
$pointerPath = Join-Path $wsRoot "knowledge_graphs/active_subject.json"

if ([string]::IsNullOrWhiteSpace($activeSubject)) {
    $pointerData = Read-JsonFile $pointerPath
    if ($pointerData -and -not [string]::IsNullOrWhiteSpace($pointerData.active_subject)) {
        $activeSubject = "$($pointerData.active_subject)".Trim()
    }
}

# Fallback: if no active subject specified or found in pointer
if ([string]::IsNullOrWhiteSpace($activeSubject)) {
    $kgDir = Join-Path $wsRoot "knowledge_graphs"
    $availableSubjects = @()
    if (Test-Path $kgDir) {
        $availableSubjects = @(Get-ChildItem -Path $kgDir -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName "knowledge_graph.json")
        } | ForEach-Object { $_.Name })
    }

    if ($availableSubjects.Count -eq 1) {
        $activeSubject = $availableSubjects[0]
        Write-JsonFileAtomic -Path $pointerPath -Data ([ordered]@{ active_subject = $activeSubject })
    } else {
        Send-Verdict -Action "ROUTE_TO_OUTLINE" -Payload @{
            error           = "GRAPH_NOT_FOUND"
            active_subject  = ""
            display_message = "⚠️ 未检测到活动学科。请在 Duonav 客户端选择学科，或在对话中指定（例如：切换到线性代数）。"
        }
    }
}

# Now verify graph file exists
$graphRelPath = "knowledge_graphs/$activeSubject/knowledge_graph.json"
$graphFullPath = Join-Path $wsRoot $graphRelPath

if (-not (Test-Path $graphFullPath)) {
    Send-Verdict -Action "ROUTE_TO_OUTLINE" -Payload @{
        error           = "GRAPH_NOT_FOUND"
        active_subject  = $activeSubject
        target_path     = $graphRelPath
        display_message = "⚠️ 未检测到学科【$activeSubject】的知识图谱。正在引导初始化图谱大纲..."
    }
}

# If user explicitly specified -Subject and graph exists, persist to active_subject.json
if (-not [string]::IsNullOrWhiteSpace($Subject)) {
    $currentPointer = Read-JsonFile $pointerPath
    if (-not $currentPointer -or "$($currentPointer.active_subject)".Trim() -ne $activeSubject) {
        Write-JsonFileAtomic -Path $pointerPath -Data ([ordered]@{ active_subject = $activeSubject })
    }
}

$graph = Read-JsonFile $graphFullPath
if ($null -eq $graph -or $null -eq $graph.nodes) {
    Send-Verdict -Action "ROUTE_TO_OUTLINE" -Payload @{
        error           = "CORRUPTED_GRAPH"
        active_subject  = $activeSubject
        target_path     = $graphRelPath
        display_message = "⚠️ 学科【$activeSubject】的知识图谱文件损坏或缺失 nodes 列表。请检查文件或重新初始化。"
    }
}

# ===================================================================
# Stage 2: Target Node Resolution
# ===================================================================
$targetId = if (-not [string]::IsNullOrWhiteSpace($NodeId)) { $NodeId.Trim() } else { "$($graph.selected_node)".Trim() }

if ([string]::IsNullOrWhiteSpace($targetId) -or $targetId -eq "null") {
    Send-Verdict -Action "PROMPT_SELECT_NODE" -Payload @{
        error           = "NO_SELECTED_NODE"
        active_subject  = $activeSubject
        display_message = "📍 当前学科【$activeSubject】尚未选中任何学习节点。请在 Duonav 客户端点击选中目标节点，或在对话中指定节点 ID（例如：学 1.3）。"
    }
}

$nodes = @($graph.nodes)
$targetNode = $nodes | Where-Object { "$($_.id)".Trim() -eq $targetId } | Select-Object -First 1

if ($null -eq $targetNode) {
    $allIds = ($nodes | ForEach-Object { "$($_.id)" }) -join ', '
    Send-Verdict -Action "PROMPT_SELECT_NODE" -Payload @{
        error           = "NODE_NOT_FOUND"
        active_subject  = $activeSubject
        target_id      = $targetId
        display_message = "⚠️ 在学科【$activeSubject】中未找到节点 ID【$targetId】。可用节点 ID 列表: [$allIds]。请在客户端重新选择或输入有效 ID。"
    }
}

# If user explicitly passed NodeId and it differs from graph.selected_node, atomically persist
if (-not [string]::IsNullOrWhiteSpace($NodeId) -and "$($graph.selected_node)".Trim() -ne $targetId) {
    $graph.selected_node = $targetId
    if ($graph.meta) {
        $graph.meta.last_updated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    }
    Write-JsonFileAtomic -Path $graphFullPath -Data $graph
}

# ===================================================================
# Stage 3: Prerequisites & Module Position Computation
# ===================================================================
$moduleName = if ($targetNode.module) { "$($targetNode.module)".Trim() } else { "常规" }
$moduleNodes = @($nodes | Where-Object { ("$($_.module)".Trim()) -eq $moduleName })
$nodeIdxInModule = 1
for ($m = 0; $m -lt $moduleNodes.Count; $m++) {
    if ("$($moduleNodes[$m].id)".Trim() -eq $targetId) {
        $nodeIdxInModule = $m + 1
        break
    }
}

$positionSummary = if ($moduleNodes.Count -gt 0) {
    "【$activeSubject】·【$($targetNode.label)】, 【$moduleName】 ($nodeIdxInModule/$($moduleNodes.Count))"
} else {
    "【$activeSubject】·【$($targetNode.label)】"
}

# Evaluate prerequisite edges
$edges = if ($graph.edges) { @($graph.edges) } else { @() }
$prereqEdges = @($edges | Where-Object { "$($_.to)".Trim() -eq $targetId -and "$($_.type)".Trim() -eq "prerequisite" })

$allPrereqsCompleted = $true
foreach ($edge in $prereqEdges) {
    $fromId = "$($edge.from)".Trim()
    $fromNode = $nodes | Where-Object { "$($_.id)".Trim() -eq $fromId } | Select-Object -First 1
    $fromStatus = if ($fromNode) { "$($fromNode.status)".Trim() } else { "unknown" }
    if ($fromStatus -ne "completed") {
        $allPrereqsCompleted = $false
        break
    }
}

$isLocked = ("$($targetNode.status)".Trim() -eq "locked")
$isJumpingMode = ($isLocked -or -not $allPrereqsCompleted)

# ===================================================================
# Stage 4: Teaching Plan Existence & Replan Check
# ===================================================================
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

$safeLabel = "$($targetNode.label)" -replace '[/\\:\*\?\"<>\|]', '_'
$suggestedPlanPath = "teaching_plans/$activeSubject/$targetId $safeLabel-计划.md"

$nodePayload = [ordered]@{
    id               = $targetId
    label            = "$($targetNode.label)"
    safe_label       = $safeLabel
    module           = $moduleName
    module_index     = $nodeIdxInModule
    module_total     = $moduleNodes.Count
    status           = "$($targetNode.status)"
    position_summary = $positionSummary
}

# ===================================================================
# Stage 3.5: Subject Type Resolution & General Teaching Direct Bypass
# ===================================================================
$resolvedType = "math"
if ($NonMath.IsPresent) {
    $resolvedType = "general"
} elseif (-not [string]::IsNullOrWhiteSpace($SubjectType)) {
    $resolvedType = $SubjectType.Trim().ToLower()
} elseif ($graph.meta -and $graph.meta.subject_type) {
    $resolvedType = "$($graph.meta.subject_type)".Trim().ToLower()
} elseif ($graph.meta -and $graph.meta.is_math -ne $null) {
    $resolvedType = if ($graph.meta.is_math) { "math" } else { "general" }
} else {
    $mathPattern = '代数|微积分|高数|高等数学|线性代数|概率|统计|几何|数论|实变函数|复变函数|常微分方程|偏微分方程|人工智能数学|离散数学|运筹学|数学'
    if ($activeSubject -notmatch $mathPattern) {
        $resolvedType = "general"
    }
}

if ($resolvedType -eq "general" -or $resolvedType -eq "non_math" -or $resolvedType -eq "non-math") {
    $conceptMap = [System.Collections.Generic.Dictionary[string, psobject]]::new()
    if ($graph.concept_dictionary) {
        foreach ($c in $graph.concept_dictionary) {
            if (-not [string]::IsNullOrWhiteSpace("$($c.id)")) {
                $conceptMap["$($c.id)".Trim()] = $c
            }
        }
    }

    $teachesResolved = [System.Collections.ArrayList]::new()
    if ($targetNode.teaches) {
        foreach ($cid in $targetNode.teaches) {
            $cidStr = "$cid".Trim()
            $cObj = if ($conceptMap.ContainsKey($cidStr)) { $conceptMap[$cidStr] } else { $null }
            [void]$teachesResolved.Add([ordered]@{
                id        = $cidStr
                canonical = if ($cObj) { $cObj.canonical } else { $cidStr }
                aliases   = if ($cObj -and $cObj.aliases) { @($cObj.aliases) } else { @() }
            })
        }
    }

    $requiresResolved = [System.Collections.ArrayList]::new()
    if ($targetNode.requires) {
        foreach ($cid in $targetNode.requires) {
            $cidStr = "$cid".Trim()
            $cObj = if ($conceptMap.ContainsKey($cidStr)) { $conceptMap[$cidStr] } else { $null }
            [void]$requiresResolved.Add([ordered]@{
                id        = $cidStr
                canonical = if ($cObj) { $cObj.canonical } else { $cidStr }
                aliases   = if ($cObj -and $cObj.aliases) { @($cObj.aliases) } else { @() }
            })
        }
    }

    $displayMsg = if ($isJumpingMode) {
        "💡 【通用教学模式】检测到节点【$($targetNode.label)】的前置依赖尚未全部掌握。已开启【跳级旁听模式】：本次教学将直接展开知识讲解；学完后暂不点亮完成状态与解锁后置节点。"
    } else {
        "📍 路径对齐：$positionSummary。当前学科【$activeSubject】采用通用教学模式，无需制定教案与公式推演，正在直接展开知识点讲解..."
    }

    Send-Verdict -Action "ROUTE_TO_GENERAL_TEACHING" -Payload @{
        active_subject    = $activeSubject
        subject_type      = "general"
        target_node       = $nodePayload
        is_jumping_mode   = $isJumpingMode
        teaches_concepts  = $teachesResolved.ToArray()
        requires_concepts = $requiresResolved.ToArray()
        display_message   = $displayMsg
    }
}

# Branch 4A: Plan does not exist OR user requested Replan -> ROUTE_TO_PLAN
if (-not $hasPlan -or $Replan.IsPresent) {
    $msg = if ($Replan.IsPresent) {
        "📍 重新规划：【$($targetNode.label)】。正在重新制定教学计划..."
    } else {
        "📍 路径对齐：$positionSummary。检测到该节点尚未制定教学计划，正在制定二级大纲与完备性清单..."
    }

    Send-Verdict -Action "ROUTE_TO_PLAN" -Payload @{
        active_subject      = $activeSubject
        target_node         = $nodePayload
        is_replan           = $Replan.IsPresent
        suggested_plan_path = $suggestedPlanPath
        display_message     = $msg
    }
}

# ===================================================================
# Stage 5: Both Graph & Plan Exist -> ROUTE_TO_EXECUTION
# ===================================================================
$displayMsg = if ($isJumpingMode) {
    "💡 检测到节点【$($targetNode.label)】的前置依赖尚未全部掌握。已开启【跳级旁听模式】：本次教学将默认具备相关基础直接展开推演；为保证图谱真实性，学完后暂不点亮完成状态与解锁后置节点。"
} else {
    "📍 路径对齐：$positionSummary"
}

Send-Verdict -Action "ROUTE_TO_EXECUTION" -Payload @{
    active_subject   = $activeSubject
    target_node      = $nodePayload
    is_jumping_mode  = $isJumpingMode
    plan_file        = $planFile
    display_message  = $displayMsg
}
