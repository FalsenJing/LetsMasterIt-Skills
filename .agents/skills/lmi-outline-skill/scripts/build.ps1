<#
.SYNOPSIS
    Generate a study_plan.md file from a structured JSON outline.

.PARAMETER InputFile
    Path to the structured JSON outline file (default: raw_input.json)

.PARAMETER OutputDir
    Target workspace directory for the output (default: current directory)

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build.ps1 -InputFile raw_input.json
    powershell -ExecutionPolicy Bypass -File build.ps1 -InputFile outline.json -OutputDir C:\workspace
#>

[CmdletBinding()]
param(
    [Alias("i")]
    [string]$InputFile = "raw_input.json",

    [Alias("o")]
    [string]$OutputDir = "."
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ── Constants ─────────────────────────────────────────
# These tokens must match the template file exactly.
$SUBJECT_TOKEN      = [char]0x300A + [char]0x79D1 + [char]0x76EE + [char]0x540D + [char]0x79F0 + [char]0x300B   # match template placeholder
$PHASE_TABLE_MARKER = '<' + '!-- PHASE_TABLE --' + '>'

# ── Helper functions ──────────────────────────────────
function Fail {
    param([string[]]$Messages)
    Write-Host ""
    Write-Host "[-] Aborted: the input data has the following issues, please fix and retry:"
    foreach ($m in $Messages) {
        Write-Host "    * $m"
    }
    exit 1
}

function Get-TemplatePath {
    param([string]$TemplateName)
    $scriptDir = Split-Path -Parent $PSCommandPath
    $templatePath = Join-Path (Join-Path $scriptDir "..") "templates"
    $templatePath = Join-Path $templatePath $TemplateName
    if (Test-Path $templatePath) {
        return (Resolve-Path $templatePath).Path
    }
    return $null
}

# ── Validation ────────────────────────────────────────
function Validate-InputData {
    param([psobject]$Data)

    if ($null -eq $Data -or $Data -is [array]) {
        Fail @("Top-level JSON must be an object containing course_name / phases.")
    }

    $errors = [System.Collections.ArrayList]::new()

    # course_name
    $courseName = $Data.course_name
    if (-not $courseName -or [string]::IsNullOrWhiteSpace($courseName)) {
        [void]$errors.Add("Missing valid course_name.")
        $courseName = "Untitled"
    }

    # textbook (optional)
    $textbook = ""
    if ($Data.PSObject.Properties.Name -contains "textbook") {
        $textbook = $Data.textbook
    }

    # phases
    $phases = $Data.phases
    if ($null -eq $phases -or $phases -isnot [array] -or $phases.Count -eq 0) {
        [void]$errors.Add("phases must be a non-empty array (at least one learning phase).")
        $phases = @()
    }

    for ($i = 0; $i -lt $phases.Count; $i++) {
        $idx = $i + 1
        $p = $phases[$i]
        if ($null -eq $p -or $p -is [array]) {
            [void]$errors.Add("Phase #$idx is not an object.")
            continue
        }
        foreach ($key in @("phase_num", "phase_name")) {
            $val = $p.$key
            if ($null -eq $val -or ([string]::IsNullOrWhiteSpace("$val"))) {
                [void]$errors.Add("Phase #$idx is missing field '$key'.")
            }
        }
        # nodes is optional
        if ($p.PSObject.Properties.Name -contains "nodes") {
            if ($p.nodes -isnot [array]) {
                [void]$errors.Add("Phase #${idx}: nodes must be an array.")
            }
        }
    }

    if ($errors.Count -gt 0) {
        Fail $errors.ToArray()
    }

    return @{
        CourseName = $courseName
        Textbook   = $textbook
        Phases     = $phases
    }
}

# ── Build phase table ─────────────────────────────────
function Build-PhaseTable {
    param([array]$Phases)
    $lines = [System.Collections.ArrayList]::new()
    foreach ($p in $Phases) {
        [void]$lines.Add("")
        [void]$lines.Add("### $($p.phase_name)")
        [void]$lines.Add("")
        $nodes = @()
        if ($p.PSObject.Properties.Name -contains "nodes" -and $p.nodes -is [array]) {
            $nodes = $p.nodes
        }
        if ($nodes.Count -gt 0) {
            foreach ($node in $nodes) {
                $name = if ($node -is [string]) { $node } else { $node.name }
                [void]$lines.Add("- [ ] $name")
            }
        }
        else {
            [void]$lines.Add("- [ ] $($p.phase_name)")
        }
    }
    return ($lines -join "`n")
}

# ── Render template ───────────────────────────────────
function Render-StudyPlanTemplate {
    param(
        [string]$TemplateName,
        [hashtable]$Replacements,
        [string[]]$Markers
    )
    $path = Get-TemplatePath $TemplateName
    if (-not $path) {
        Fail @("Template '$TemplateName' not found.")
    }
    $content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)

    foreach ($marker in $Markers) {
        $escaped = [regex]::Escape($marker)
        $count = ([regex]::Matches($content, $escaped)).Count
        if ($count -ne 1) {
            Fail @("Marker in template '$TemplateName' must appear exactly once (found $count).")
        }
    }

    foreach ($token in $Replacements.Keys) {
        $content = $content.Replace($token, $Replacements[$token])
    }
    return $content
}

# ── Main ──────────────────────────────────────────────
if (-not (Test-Path $InputFile)) {
    Write-Host "[-] Error: input file '$InputFile' does not exist."
    Write-Host "Example format:"
    $example = @{
        course_name = "Linear Algebra"
        textbook    = "Linear Algebra Done Right - Sheldon Axler"
        phases      = @(
            @{
                phase_num  = 1
                phase_name = "Phase 1: Foundations"
                nodes      = @("Vector spaces", "Subspaces", "Span and linear independence", "Bases and dimension")
            }
        )
    }
    Write-Host ($example | ConvertTo-Json -Depth 4)
    exit 1
}

Write-Host "[+] Reading input: $InputFile ..."
try {
    $rawJson = [System.IO.File]::ReadAllText((Resolve-Path $InputFile).Path, [System.Text.Encoding]::UTF8)
    $data = $rawJson | ConvertFrom-Json
}
catch {
    Fail @("Failed to parse JSON: $($_.Exception.Message)")
}

$validated  = Validate-InputData $data
$courseName = $validated.CourseName
$textbook   = $validated.Textbook
$phases     = $validated.Phases

Write-Host "[+] Subject: $courseName"
Write-Host "[+] Phases: $($phases.Count)"

$outputDirFull = (Resolve-Path $OutputDir).Path
$planOutPath   = Join-Path $outputDirFull "study_plan.md"

$textbookLine = if ($textbook) { $textbook } else { "[N/A]" }

$phaseTable = Build-PhaseTable $phases

$planContent = Render-StudyPlanTemplate -TemplateName "study_plan_template.md" -Replacements @{
    $SUBJECT_TOKEN                         = [char]0x300A + $courseName + [char]0x300B
    ('{TEXTBOOK_NAME} ' + [char]0x2014 + ' {TEXTBOOK_AUTHOR}')  = $textbookLine
    $PHASE_TABLE_MARKER                    = $phaseTable
} -Markers @($PHASE_TABLE_MARKER)

[System.IO.File]::WriteAllText($planOutPath, $planContent, (New-Object System.Text.UTF8Encoding $false))
Write-Host "[+] Generated: $planOutPath"
Write-Host ""
Write-Host "[+] Done! Study plan initialized successfully."
