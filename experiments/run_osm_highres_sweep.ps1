param(
    [Parameter(Mandatory = $true)]
    [string]$Dataset,
    [Parameter(Mandatory = $true)]
    [string]$DatasetTag,
    [string]$RunTag = "",
    [string[]]$Resolutions = @("2560x1920", "5120x3840", "10240x7680"),
    [string[]]$MethodKeys = @("m7", "m8"),
    [int]$TimeoutSeconds = 14400,
    [ValidateSet("none", "diagnostic", "all")]
    [string]$OutputRetention = "none",
    [ValidateSet("script", "expected_fast_first")]
    [string]$ExecutionOrder = "expected_fast_first",
    [double]$ZOrderEpsilon = 0.01,
    [ValidateSet("SCAN", "RQS_ball")]
    [string]$ZOrderEvalMethod = "SCAN",
    [switch]$Resume
)

$ErrorActionPreference = "Stop"

$Repo = Resolve-Path "."
$Runner = Join-Path $Repo "experiments\run_kdv_experiments.ps1"
if (!(Test-Path $Runner)) {
    throw "Missing runner: $Runner"
}

if ($RunTag -eq "") {
    $RunTag = "osm_highres_" + (Get-Date -Format "yyyyMMdd_HHmmss")
}

foreach ($resolution in $Resolutions) {
    if ($resolution -notmatch "^([0-9]+)x([0-9]+)$") {
        throw "Resolution must be formatted as ROWSxCOLS: $resolution"
    }
    $rows = [int]$Matches[1]
    $cols = [int]$Matches[2]
    Write-Host "[osm-highres] dataset=$DatasetTag run=$RunTag resolution=${rows}x${cols}"

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $Runner,
        "-Dataset", $Dataset,
        "-DatasetTag", $DatasetTag,
        "-RunTag", $RunTag,
        "-Groups", "default",
        "-MethodKeys"
    )
    $args += $MethodKeys
    $args += @(
        "-CustomRows", "$rows",
        "-CustomCols", "$cols",
        "-ExecutionOrder", $ExecutionOrder,
        "-OutputRetention", $OutputRetention,
        "-TimeoutSeconds", "$TimeoutSeconds",
        "-ZOrderEpsilon", "$ZOrderEpsilon",
        "-ZOrderEvalMethod", $ZOrderEvalMethod,
        "-WithZOrder"
    )
    if ($Resume) {
        $args += "-Resume"
    }
    & PowerShell @args
    if ($LASTEXITCODE -ne 0) {
        throw "run_kdv_experiments.ps1 failed for ${rows}x${cols} with exit code $LASTEXITCODE"
    }
}

Write-Host "[done] experiments\results\$DatasetTag\$RunTag\default\runtime.csv"
