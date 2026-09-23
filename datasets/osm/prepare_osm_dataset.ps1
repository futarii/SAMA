param(
    [Parameter(Mandatory=$true)]
    [string]$Url,
    [Parameter(Mandatory=$true)]
    [string]$DatasetTag,
    [string]$WorkRoot = ".\datasets\osm\work",
    [string]$StandardizedDir = ".\datasets\osm\work\standardized",
    [ValidateSet("download", "sample", "full", "all")]
    [string]$Stage = "sample",
    [int]$SampleMod = 100,
    [int]$SampleRem = 0,
    [int]$MaxSamplePoints = 1000000,
    [double]$MinX = [double]::NaN,
    [double]$MaxX = [double]::NaN,
    [double]$MinY = [double]::NaN,
    [double]$MaxY = [double]::NaN
)

$ErrorActionPreference = "Stop"

$Repo = Resolve-Path "."
$Extractor = Join-Path $Repo "datasets\osm\extract_osm_nodes.py"
if (!(Test-Path $Extractor)) { throw "Missing extractor: $Extractor" }

$WorkRootPath = [System.IO.Path]::GetFullPath((Join-Path $Repo $WorkRoot))
$StandardizedPath = [System.IO.Path]::GetFullPath((Join-Path $Repo $StandardizedDir))
$DownloadDir = Join-Path $WorkRootPath "downloads"
$PreviewDir = Join-Path $WorkRootPath "preview"
New-Item -ItemType Directory -Force $DownloadDir | Out-Null
New-Item -ItemType Directory -Force $PreviewDir | Out-Null
New-Item -ItemType Directory -Force $StandardizedPath | Out-Null

$PbfName = Split-Path ([Uri]$Url).AbsolutePath -Leaf
if ([string]::IsNullOrWhiteSpace($PbfName)) {
    $PbfName = "$DatasetTag-latest.osm.pbf"
}
$PbfPath = Join-Path $DownloadDir $PbfName

function Add-BBoxArgs {
    param([object[]]$ArgsIn)
    $argsOut = @($ArgsIn)
    if (![double]::IsNaN($MinX)) { $argsOut += @("--min-x", "$MinX") }
    if (![double]::IsNaN($MaxX)) { $argsOut += @("--max-x", "$MaxX") }
    if (![double]::IsNaN($MinY)) { $argsOut += @("--min-y", "$MinY") }
    if (![double]::IsNaN($MaxY)) { $argsOut += @("--max-y", "$MaxY") }
    return $argsOut
}

function Invoke-Download {
    if (Test-Path $PbfPath) {
        Write-Host "[download] resume/check existing $PbfPath"
    } else {
        Write-Host "[download] $Url"
    }
    $maxAttempts = 80
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $before = 0
        if (Test-Path $PbfPath) { $before = (Get-Item $PbfPath).Length }
        Write-Host "[download] attempt=$attempt existing_bytes=$before"
        & curl.exe `
            --fail `
            --location `
            --continue-at - `
            --connect-timeout 60 `
            --speed-time 120 `
            --speed-limit 1024 `
            --output $PbfPath `
            $Url
        $code = $LASTEXITCODE
        $after = 0
        if (Test-Path $PbfPath) { $after = (Get-Item $PbfPath).Length }
        Write-Host "[download] attempt=$attempt exit=$code bytes=$after"
        if ($after -lt $before) {
            throw "download size went backwards: before=$before after=$after"
        }
        if ($code -eq 0) { return }
        if ($attempt -eq $maxAttempts) {
            throw "curl failed after $maxAttempts attempts; last exit code $code"
        }
        Start-Sleep -Seconds 10
    }
}

function Invoke-Sample {
    $sample = Join-Path $StandardizedPath "${DatasetTag}_sample_1m.txt"
    $summary = Join-Path $StandardizedPath "${DatasetTag}_sample_1m.summary.txt"
    $scatter = Join-Path $PreviewDir "${DatasetTag}_sample_1m_scatter.png"
    Write-Host "[sample] $sample"
    $args = @(
        $Extractor,
        "--pbf", $PbfPath,
        "--output", $sample,
        "--summary", $summary,
        "--scatter", $scatter,
        "--sample-mod", "$SampleMod",
        "--sample-rem", "$SampleRem",
        "--max-points", "$MaxSamplePoints",
        "--max-plot-points", "$MaxSamplePoints",
        "--log-every", "100000"
    )
    $args = Add-BBoxArgs $args
    & python @args
    if ($LASTEXITCODE -ne 0) { throw "sample extraction failed with exit code $LASTEXITCODE" }
    Write-Host "[sample done] $summary"
    Write-Host "[scatter] $scatter"
}

function Invoke-Full {
    $full = Join-Path $StandardizedPath "${DatasetTag}.txt"
    $summary = Join-Path $StandardizedPath "${DatasetTag}.summary.txt"
    $scatter = Join-Path $PreviewDir "${DatasetTag}_full_scatter.png"
    Write-Host "[full] $full"
    $args = @(
        $Extractor,
        "--pbf", $PbfPath,
        "--output", $full,
        "--summary", $summary,
        "--scatter", $scatter,
        "--sample-mod", "1",
        "--sample-rem", "0",
        "--max-points", "0",
        "--max-plot-points", "1000000",
        "--log-every", "1000000"
    )
    $args = Add-BBoxArgs $args
    & python @args
    if ($LASTEXITCODE -ne 0) { throw "full extraction failed with exit code $LASTEXITCODE" }
    Write-Host "[full done] $summary"
    Write-Host "[scatter] $scatter"
}

Invoke-Download
if ($Stage -eq "download") { return }
if ($Stage -eq "sample" -or $Stage -eq "all") { Invoke-Sample }
if ($Stage -eq "full" -or $Stage -eq "all") { Invoke-Full }
