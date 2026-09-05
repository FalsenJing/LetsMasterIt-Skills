<#
.SYNOPSIS
    Set/Update active subject pointer script: creates or updates knowledge_graphs/active_subject.json.
    Standard JSON output protocol: All execution results are output to stdout as pure JSON.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias("s")]
    [string]$Subject,

    [Alias("o")]
    [string]$OutputFile = "knowledge_graphs/active_subject.json"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Output-Fail {
    param([array]$Errors)
    $res = @{
        success = $false
        action  = "set_active_subject"
        errors  = $Errors
    }
    $res | ConvertTo-Json -Depth 6 -Compress:$false
    exit 1
}

# 1. Check Subject parameter
if ([string]::IsNullOrWhiteSpace($Subject)) {
    Output-Fail @(
        @{ type = "EMPTY_SUBJECT"; message = "Subject name cannot be empty." }
    )
}

# 2. Resolve absolute path and ensure directory exists
try {
    $outFullPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) {
        $OutputFile
    } else {
        Join-Path (Get-Location).Path $OutputFile
    }

    $outDir = [System.IO.Path]::GetDirectoryName($outFullPath)
    if ($outDir -and -not (Test-Path $outDir)) {
        [System.IO.Directory]::CreateDirectory($outDir) | Out-Null
    }

    # 3. Construct JSON object
    $cleanSubject = $Subject.Trim()
    $updatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    $pointerObj = @{
        active_subject = $cleanSubject
        updated_at     = $updatedAt
    }

    # 4. Write file (Standard UTF-8 without BOM)
    $jsonText = $pointerObj | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($outFullPath, $jsonText, (New-Object System.Text.UTF8Encoding $false))

    # 5. Standard JSON response to stdout
    $response = @{
        success        = $true
        action         = "set_active_subject"
        active_subject = $cleanSubject
        output_file    = $OutputFile
        updated_at     = $updatedAt
    }
    $response | ConvertTo-Json -Depth 4 -Compress:$false
}
catch {
    Output-Fail @(
        @{ type = "IO_ERROR"; message = "Failed to write active subject pointer: $($_.Exception.Message)" }
    )
}
