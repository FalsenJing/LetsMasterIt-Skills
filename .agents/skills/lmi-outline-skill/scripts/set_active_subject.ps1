<#
.SYNOPSIS
    设置/更新活动学科指针脚本：规范创建或更新 knowledge_graphs/active_subject.json。
    【标准 JSON 输出协议】：所有执行结果均以纯 JSON 形式输出到 stdout，便于模型直接解析与自审。
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

# 1. 检查 Subject 参数非空
if ([string]::IsNullOrWhiteSpace($Subject)) {
    Output-Fail @(
        @{ type = "EMPTY_SUBJECT"; message = "Subject name cannot be empty." }
    )
}

# 2. 解析绝对路径并确保父目录存在
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

    # 3. 构造标准化 JSON 指针对象
    $cleanSubject = $Subject.Trim()
    $updatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    $pointerObj = @{
        active_subject = $cleanSubject
        updated_at     = $updatedAt
    }

    # 4. 写入文件 (标准 UTF-8 编码，无 BOM)
    $jsonText = $pointerObj | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($outFullPath, $jsonText, (New-Object System.Text.UTF8Encoding $false))

    # 5. 标准 JSON 响应输出到 stdout
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
