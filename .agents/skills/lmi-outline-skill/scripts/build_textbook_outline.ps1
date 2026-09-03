<#
.SYNOPSIS
    教材原版大纲校验与生成脚本：
    对子代理收集的原始教材大纲进行两级章节（章-节）格式约束校验，并规范输出 textbook_outline.json。
    【标准 JSON 输出协议】：所有校验指标、错误均以纯 JSON 形式输出到 stdout。
#>

[CmdletBinding()]
param(
    [Alias("i")]
    [string]$InputFile = "textbook_outline_raw.json",

    [Alias("o")]
    [string]$OutputFile = "textbook_outline.json"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Output-Fail {
    param([array]$Errors)
    $res = @{
        success = $false
        errors  = $Errors
    }
    $res | ConvertTo-Json -Depth 6 -Compress:$false
    exit 1
}

# 1. 检查输入文件
if (-not (Test-Path $InputFile)) {
    Output-Fail @(
        @{ type = "FILE_NOT_FOUND"; message = "Input file '$InputFile' not found." }
    )
}

# 2. 解析 JSON
try {
    $rawContent = [System.IO.File]::ReadAllText((Resolve-Path $InputFile).Path, [System.Text.Encoding]::UTF8)
    $data = $rawContent | ConvertFrom-Json
}
catch {
    Output-Fail @(
        @{ type = "JSON_SYNTAX_ERROR"; message = "Failed to parse JSON: $($_.Exception.Message)" }
    )
}

# 3. 校验顶层字段 (title, chapters)
$errors = [System.Collections.ArrayList]::new()

if ($null -eq $data.title -or [string]::IsNullOrWhiteSpace($data.title)) {
    [void]$errors.Add(@{ type = "MISSING_TITLE"; message = "Missing or empty top-level 'title' field (教材书名)." })
}

if ($null -eq $data.chapters -or -not ($data.chapters -is [array]) -or $data.chapters.Count -eq 0) {
    [void]$errors.Add(@{ type = "MISSING_CHAPTERS"; message = "Top-level 'chapters' must be a non-empty array of chapters." })
}

if ($errors.Count -gt 0) {
    Output-Fail $errors.ToArray()
}

# 4. 校验二级章节结构（严格两级约束：章 -> 节，禁止第三级子节）
$cleanChapters = [System.Collections.ArrayList]::new()
$totalSections = 0

for ($cIdx = 0; $cIdx -lt $data.chapters.Count; $cIdx++) {
    $ch = $data.chapters[$cIdx]
    $chId = if ($ch.id) { "$($ch.id)".Trim() } else { "第$($cIdx + 1)章" }
    $chTitle = if ($ch.title) { "$($ch.title)".Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($chTitle)) {
        [void]$errors.Add(@{ type = "MISSING_CHAPTER_TITLE"; chapter_index = $cIdx; message = "Chapter at index $cIdx is missing 'title'." })
    }

    if ($null -eq $ch.sections -or -not ($ch.sections -is [array]) -or $ch.sections.Count -eq 0) {
        [void]$errors.Add(@{ type = "EMPTY_SECTIONS"; chapter_id = $chId; message = "Chapter '$chId' must contain a non-empty 'sections' array." })
        continue
    }

    $cleanSections = [System.Collections.ArrayList]::new()
    for ($sIdx = 0; $sIdx -lt $ch.sections.Count; $sIdx++) {
        $sec = $ch.sections[$sIdx]
        $secId = if ($sec.id) { "$($sec.id)".Trim() } else { "$($cIdx + 1).$($sIdx + 1)" }
        $secTitle = if ($sec.title) { "$($sec.title)".Trim() } else { "" }

        if ([string]::IsNullOrWhiteSpace($secTitle)) {
            [void]$errors.Add(@{ type = "MISSING_SECTION_TITLE"; chapter_id = $chId; section_index = $sIdx; message = "Section at index $sIdx in chapter '$chId' is missing 'title'." })
        }

        # 严格禁止第三级子小节 (no subsections / sub_items / children)
        if ($sec.PSObject.Properties.Name -contains "subsections" -or $sec.PSObject.Properties.Name -contains "sub_items" -or $sec.PSObject.Properties.Name -contains "children") {
            [void]$errors.Add(@{ type = "EXCEEDED_LEVEL_LIMIT"; section_id = $secId; message = "Section '$secId' contains nested sub-items. Textbook outline must be strictly two levels (chapters -> sections)." })
        }

        $rawConceptsList = [System.Collections.Generic.List[string]]::new()
        if ($sec.PSObject.Properties.Name -contains "concepts" -and $null -ne $sec.concepts) {
            if ($sec.concepts -is [array]) {
                foreach ($item in $sec.concepts) {
                    $val = "$item".Trim()
                    if (-not [string]::IsNullOrWhiteSpace($val)) {
                        $rawConceptsList.Add($val)
                    }
                }
            } elseif (-not [string]::IsNullOrWhiteSpace("$($sec.concepts)")) {
                $val = "$($sec.concepts)".Trim()
                if ($val -ne "{}") {
                    $rawConceptsList.Add($val)
                }
            }
        }
        $concepts = $rawConceptsList.ToArray()

        [void]$cleanSections.Add(@{
            id       = $secId
            title    = $secTitle
            concepts = $concepts
        })
        $totalSections++
    }

    [void]$cleanChapters.Add(@{
        id       = $chId
        title    = $chTitle
        sections = $cleanSections.ToArray()
    })
}

if ($errors.Count -gt 0) {
    Output-Fail $errors.ToArray()
}

# 5. 输出规范化文件
$finalObj = @{
    title        = "$($data.title)".Trim()
    author       = if ($data.author) { "$($data.author)".Trim() } else { "" }
    edition      = if ($data.edition) { "$($data.edition)".Trim() } else { "" }
    last_updated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    chapters     = $cleanChapters.ToArray()
}

$outFullPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path (Get-Location).Path $OutputFile }
$jsonText = $finalObj | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($outFullPath, $jsonText, (New-Object System.Text.UTF8Encoding $true))

$response = @{
    success     = $true
    output_file = $OutputFile
    metrics     = @{
        title         = $finalObj.title
        chapter_count = $cleanChapters.Count
        section_count = $totalSections
    }
}
$response | ConvertTo-Json -Depth 4 -Compress:$false
