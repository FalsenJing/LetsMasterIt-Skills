<#
.SYNOPSIS
    Automated lesson settlement script for Duonav LMI Execution Skill.
    Safely updates teaching plan subtopic checkboxes, computes learning progress,
    appends error/difficulty logs, resolves node completion status, unlocks downstream nodes,
    and atomically persists updates to knowledge_graph.json and plan_file without data corruption.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias("s")]
    [string]$Subject,

    [Parameter(Mandatory = $true)]
    [Alias("n")]
    [string]$NodeId,

    [Alias("p")]
    [string]$PlanFile,

    [Alias("i")]
    [int]$SubtopicIndex,

    [Alias("t")]
    [string]$SubtopicTitle,

    [string]$ErrorJson,

    [string]$DifficultyJson,

    [Alias("o")]
    [string]$OutputFile,

    [Alias("dc")]
    [switch]$DirectComplete
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$cOpen = [char]0x3010
$cClose = [char]0x3011
$cDot = [char]0x00B7
$cPlanSuffix = '-' + [char]0x8BA1 + [char]0x5212 + '.md'
$cSec2Prefix = '^##\s*' + [char]0x4E8C + [char]0x3001
$cSec3Prefix = '^##\s*' + [char]0x4E09 + [char]0x3001

function Output-Fail {
    param(
        [string]$ErrorType,
        [string]$Message,
        [hashtable]$Extra = @{}
    )
    $res = [ordered]@{
        success = $false
        action  = "settle_lesson"
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

# ===================================================================
# 1. Resolve Teaching Plan File Path
# ===================================================================
$activeSubject = $Subject.Trim()
$targetId = $NodeId.Trim()
$resolvedPlanPath = $null

if ($DirectComplete.IsPresent) {
    $checkedCount = 1
    $uncheckedCount = 0
    $totalCount = 1
    $matchedSubtopicTitle = "通用节点教学"
} else {
    if (-not [string]::IsNullOrWhiteSpace($PlanFile)) {
        $resolvedPlanPath = if ([System.IO.Path]::IsPathRooted($PlanFile)) { $PlanFile } else { Join-Path $wsRoot $PlanFile }
    }

    if (-not $resolvedPlanPath -or -not (Test-Path $resolvedPlanPath)) {
        $planDir = Join-Path $wsRoot "teaching_plans/$activeSubject"
        if (Test-Path $planDir) {
            $escapedId = [regex]::Escape($targetId)
            $pattern = "^$escapedId\s.*\.md$"
            $matched = Get-ChildItem -Path $planDir -File | Where-Object { $_.Name -match $pattern } | Select-Object -First 1
            if ($matched) {
                $resolvedPlanPath = $matched.FullName
            }
        }
    }

    if (-not $resolvedPlanPath -or -not (Test-Path $resolvedPlanPath)) {
        Output-Fail -ErrorType "PLAN_NOT_FOUND" -Message "Teaching plan file not found for node '$targetId' in subject '$activeSubject'." -Extra @{
            active_subject = $activeSubject
            target_node_id = $targetId
        }
    }

    # ===================================================================
    # 2. Update Plan File Subtopics (- [ ] -> - [x])
    # ===================================================================
    $planLines = [System.IO.File]::ReadAllLines($resolvedPlanPath, [System.Text.Encoding]::UTF8)
    $updatedLines = [System.Collections.Generic.List[string]]::new()
    $subtopicRegex = '^\s*-\s*\[([ xX])\]\s*\*\*(\d+)\.\s*(.*?)\*\*'

    $subtopicCount = 0
    $matchedSubtopicTitle = ""
    $inSectionTwo = $false

    for ($i = 0; $i -lt $planLines.Count; $i++) {
        $line = $planLines[$i]
        if ($line -match $cSec2Prefix) {
            $inSectionTwo = $true
        } elseif ($line -match $cSec3Prefix) {
            $inSectionTwo = $false
        }

        if ($inSectionTwo -and ($line -match $subtopicRegex)) {
            $subtopicCount++
            $currState = $Matches[1]
            $currNum = [int]$Matches[2]
            $currTitle = $Matches[3].Trim()

            $shouldCheck = $false
            if ($SubtopicIndex -gt 0 -and $subtopicCount -eq $SubtopicIndex) {
                $shouldCheck = $true
                $matchedSubtopicTitle = $currTitle
            } elseif (-not [string]::IsNullOrWhiteSpace($SubtopicTitle) -and $currTitle -like "*$SubtopicTitle*") {
                $shouldCheck = $true
                $matchedSubtopicTitle = $currTitle
            }

            if ($shouldCheck -and $currState -ne 'x' -and $currState -ne 'X') {
                $line = $line -replace '^\s*-\s*\[\s*\]', '- [x]'
            }
        }
        $updatedLines.Add($line)
    }

    # Persist updated plan markdown file atomically
    $planTemp = "$resolvedPlanPath.tmp.$([System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
    [System.IO.File]::WriteAllLines($planTemp, $updatedLines.ToArray(), (New-Object System.Text.UTF8Encoding $false))
    Move-Item -Path $planTemp -Destination $resolvedPlanPath -Force

    # Scan again to count checked vs unchecked in Section 2
    $checkedCount = 0
    $uncheckedCount = 0
    $inSectionTwo = $false
    $allSubtopicTitles = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $updatedLines) {
        if ($line -match $cSec2Prefix) {
            $inSectionTwo = $true
            continue
        } elseif ($line -match $cSec3Prefix) {
            $inSectionTwo = $false
            continue
        }

        if ($inSectionTwo -and ($line -match $subtopicRegex)) {
            $state = $Matches[1]
            $title = $Matches[3].Trim()
            $allSubtopicTitles.Add($title)
            if ($state -eq 'x' -or $state -eq 'X') {
                $checkedCount++
            } else {
                $uncheckedCount++
            }
        }
    }

    $totalCount = $checkedCount + $uncheckedCount
    if (-not $matchedSubtopicTitle -and $SubtopicIndex -gt 0 -and $SubtopicIndex -le $allSubtopicTitles.Count) {
        $matchedSubtopicTitle = $allSubtopicTitles[$SubtopicIndex - 1]
    }
}

# ===================================================================
# 3. Read Knowledge Graph Data
# ===================================================================
$graphRelPath = "knowledge_graphs/$activeSubject/knowledge_graph.json"
$graphFullPath = Join-Path $wsRoot $graphRelPath

if (-not (Test-Path $graphFullPath)) {
    Output-Fail -ErrorType "GRAPH_NOT_FOUND" -Message "Knowledge graph file not found: '$graphRelPath'." -Extra @{
        active_subject = $activeSubject
    }
}

$graph = Read-JsonFile $graphFullPath
if ($null -eq $graph -or $null -eq $graph.nodes) {
    Output-Fail -ErrorType "CORRUPTED_GRAPH" -Message "Knowledge graph file corrupted or missing nodes." -Extra @{
        active_subject = $activeSubject
    }
}

# 4. Append Error Log & Difficulty Log if provided
$currentTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
$hasGraphUpdates = $false

if ($graph.PSObject.Properties.Name -notcontains "error_log" -or $null -eq $graph.error_log) {
    $graph | Add-Member -MemberType NoteProperty -Name "error_log" -Value @() -Force
}
if ($graph.PSObject.Properties.Name -notcontains "difficulty_log" -or $null -eq $graph.difficulty_log) {
    $graph | Add-Member -MemberType NoteProperty -Name "difficulty_log" -Value @() -Force
}

if (-not [string]::IsNullOrWhiteSpace($ErrorJson)) {
    try {
        $errObj = $ErrorJson | ConvertFrom-Json
        $errId = "E{0:D3}" -f (@($graph.error_log).Count + 1)
        $newErr = [ordered]@{
            id               = $errId
            node_id          = $targetId
            question_summary = if ($errObj.question_summary) { "$($errObj.question_summary)" } else { "Practice question review" }
            error_reason     = if ($errObj.error_reason) { "$($errObj.error_reason)" } else { "Conceptual confusion" }
            status           = "pending_review"
            timestamp        = $currentTime
        }
        $graph.error_log = @($graph.error_log) + $newErr
        $hasGraphUpdates = $true
    } catch {}
}

if (-not [string]::IsNullOrWhiteSpace($DifficultyJson)) {
    try {
        $diffObj = $DifficultyJson | ConvertFrom-Json
        $diffId = "D{0:D3}" -f (@($graph.difficulty_log).Count + 1)
        $newDiff = [ordered]@{
            id             = $diffId
            node_id        = $targetId
            concept_id     = if ($diffObj.concept_id) { "$($diffObj.concept_id)" } else { "" }
            difficulty     = if ($diffObj.difficulty) { "$($diffObj.difficulty)" } else { "Difficulty record" }
            key_resolution = if ($diffObj.key_resolution) { "$($diffObj.key_resolution)" } else { "" }
            status         = "confused"
            timestamp      = $currentTime
        }
        $graph.difficulty_log = @($graph.difficulty_log) + $newDiff
        $hasGraphUpdates = $true
    } catch {}
}

# ===================================================================
# 5. Settlement Branch A: Node not fully finished yet (unchecked > 0)
# ===================================================================
if ($uncheckedCount -gt 0) {
    if ($hasGraphUpdates) {
        if ($graph.meta) { $graph.meta.last_updated = $currentTime }
        Write-JsonFileAtomic -Path $graphFullPath -Data $graph
    }

    $titleDisplay = if ($matchedSubtopicTitle) { $matchedSubtopicTitle } else { "Subtopic $SubtopicIndex" }
    $dispMsg = "✅ 子主题$cOpen$titleDisplay$cClose已掌握并销项！当前节点学习进度 ($checkedCount/$totalCount)。回复【继续】推进下一子主题，或针对本节提出疑问深入探讨。"

    $res = [ordered]@{
        success                = $true
        action                 = "settle_lesson"
        node_completed         = $false
        active_subject         = $activeSubject
        target_node_id         = $targetId
        current_subtopic_title = $titleDisplay
        checked_count          = $checkedCount
        unchecked_count        = $uncheckedCount
        total_count            = $totalCount
        display_message        = $dispMsg
    }

    $json = $res | ConvertTo-Json -Depth 6 -Compress:$false
    if ($OutputFile) { [System.IO.File]::WriteAllText($OutputFile, $json, (New-Object System.Text.UTF8Encoding $false)) }
    $json
    exit 0
}

# ===================================================================
# 6. Settlement Branch B: All subtopics completed (unchecked == 0)
# ===================================================================
$nodes = @($graph.nodes)
$targetNode = $nodes | Where-Object { "$($_.id)".Trim() -eq $targetId } | Select-Object -First 1

if ($null -eq $targetNode) {
    Output-Fail -ErrorType "NODE_NOT_FOUND" -Message "Node '$targetId' not found in graph." -Extra @{
        active_subject = $activeSubject
    }
}

$origStatus = "$($targetNode.status)".Trim()
$isJumpingMode = ($origStatus -eq "locked")
$newlyUnlockedNodes = [System.Collections.ArrayList]::new()

# Update concept_dictionary mastered status for all concepts taught in targetNode
if ($targetNode.teaches -and $graph.concept_dictionary) {
    $teachesSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($cid in $targetNode.teaches) {
        [void]$teachesSet.Add("$cid".Trim())
    }
    foreach ($concept in $graph.concept_dictionary) {
        if ($teachesSet.Contains("$($concept.id)".Trim())) {
            $concept.mastered = $true
        }
    }
}

if ($origStatus -eq "available") {
    $targetNode.status = "completed"
} elseif ($origStatus -eq "completed") {
    # Keep completed status for review mode
    $targetNode.status = "completed"
}

# Unlock downstream nodes if not in jumping mode
if (-not $isJumpingMode) {
    $edges = if ($graph.edges) { @($graph.edges) } else { @() }
    $downstreamEdges = @($edges | Where-Object { "$($_.from)".Trim() -eq $targetId -and "$($_.type)".Trim() -eq "prerequisite" })

    foreach ($edge in $downstreamEdges) {
        $postNodeId = "$($edge.to)".Trim()
        $postNode = $nodes | Where-Object { "$($_.id)".Trim() -eq $postNodeId } | Select-Object -First 1

        if ($postNode -and "$($postNode.status)".Trim() -eq "locked") {
            # Check if all prerequisites of postNode are completed
            $postPrereqEdges = @($edges | Where-Object { "$($_.to)".Trim() -eq $postNodeId -and "$($_.type)".Trim() -eq "prerequisite" })
            $allDone = $true
            foreach ($pe in $postPrereqEdges) {
                $prereqNode = $nodes | Where-Object { "$($_.id)".Trim() -eq "$($pe.from)".Trim() } | Select-Object -First 1
                if (-not $prereqNode -or "$($prereqNode.status)".Trim() -ne "completed") {
                    $allDone = $false
                    break
                }
            }

            if ($allDone) {
                $postNode.status = "available"
                [void]$newlyUnlockedNodes.Add([ordered]@{
                    id    = "$($postNode.id)"
                    label = "$($postNode.label)"
                })
            }
        }
    }
}

if ($graph.meta) {
    $graph.meta.last_updated = $currentTime
}

Write-JsonFileAtomic -Path $graphFullPath -Data $graph

# Assemble celebratory response message
$displayMsg = ""
if ($isJumpingMode) {
    $displayMsg = "🎉 当前节点$cOpen$($targetNode.label)$cClose已完成全部子主题推演！由于该节点的前置依赖尚未在图谱中补齐，图谱暂不点亮完成状态与解锁后续；待您后续补齐前置节点后，本节点将自动认证通关！"
} else {
    $unlockedText = ""
    if ($newlyUnlockedNodes.Count -gt 0) {
        $names = ($newlyUnlockedNodes | ForEach-Object { $_.label }) -join [char]0x3001
        $unlockedText = "`n🔓 已成功解锁后续节点：$cOpen$names$cClose"
    }
    $displayMsg = "🎉 恭喜！当前节点$cOpen$($targetNode.label)$cClose已全部学完并掌握！$unlockedText`n请在 Duonav 舵手桌面端中选中下一节点，或直接在对话中指定下一节点 ID 继续学习。"
}

$response = [ordered]@{
    success              = $true
    action               = "settle_lesson"
    node_completed       = $true
    active_subject       = $activeSubject
    target_node          = [ordered]@{
        id     = "$($targetNode.id)"
        label  = "$($targetNode.label)"
        status = "$($targetNode.status)"
    }
    is_jumping_mode      = $isJumpingMode
    newly_unlocked_nodes = $newlyUnlockedNodes.ToArray()
    checked_count        = $checkedCount
    total_count          = $totalCount
    display_message      = $displayMsg
}

$jsonText = $response | ConvertTo-Json -Depth 6 -Compress:$false

if ($OutputFile) {
    [System.IO.File]::WriteAllText($OutputFile, $jsonText, (New-Object System.Text.UTF8Encoding $false))
}

$jsonText
