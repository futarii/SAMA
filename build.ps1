param(
    [string]$Cxx = "g++",
    [switch]$SkipZOrder
)

$ErrorActionPreference = "Stop"
$Repo = $PSScriptRoot
$BuildRoot = $Repo
$SubstDrive = ""
$OriginalPath = $env:PATH

$ResolvedCxx = Get-Command $Cxx -ErrorAction SilentlyContinue
if ($null -eq $ResolvedCxx) {
    throw "C++ compiler not found: $Cxx"
}
$CxxPath = $ResolvedCxx.Source
$CxxDir = Split-Path -Parent $CxxPath
if ($CxxDir -ne "") {
    $env:PATH = "$CxxDir;$env:PATH"
}

if ($Repo -match '[^\x00-\x7F]') {
    foreach ($letter in @("Z", "Y", "X", "W", "V")) {
        if (-not (Test-Path "$letter`:\")) {
            $SubstDrive = "$letter`:"
            break
        }
    }
    if ($SubstDrive -eq "") {
        throw "Repository path contains non-ASCII characters and no free temporary drive letter is available for subst."
    }
    Write-Host "[build] non-ASCII path detected; mapping $SubstDrive to $Repo"
    cmd /c "subst $SubstDrive `"$Repo`""
    if ($LASTEXITCODE -ne 0) { throw "subst failed for $Repo" }
    $BuildRoot = "$SubstDrive\"
}

try {

function Invoke-Build {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$WorkingDirectory = $Repo
    )
    Write-Host "[build] $Name"
    Push-Location $WorkingDirectory
    try {
        $output = & $CxxPath @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($output) { $output | ForEach-Object { Write-Error $_ } }
            throw "$Name failed with exit code $LASTEXITCODE"
        }
        if ($output) { $output | ForEach-Object { Write-Host $_ } }
    } finally {
        Pop-Location
    }
}

$SamaDir = Join-Path $BuildRoot "cpp\sama"
$SamaSources = @(
    "dataset_io.cpp",
    "geometry.cpp",
    "kernel.cpp",
    "kd_tree.cpp",
    "sama_solver.cpp",
    "output_io.cpp",
    "commands.cpp",
    "main.cpp"
) | ForEach-Object { Join-Path $SamaDir $_ }
Invoke-Build "SAMA batch executable" (@(
    "-O3", "-std=c++17",
    "-o", (Join-Path $SamaDir "kdv_experiment.exe")
) + $SamaSources)

$SlamSources = @(
    "init_visual.cpp",
    "Euclid_Bound.cpp",
    "Validation.cpp",
    "SS_visual.cpp",
    "kd_tree.cpp",
    "ball_tree.cpp",
    "alg_visual.cpp",
    "SLAM.cpp",
    "main.cpp"
)

$ExactDir = Join-Path $BuildRoot "cpp\baselines\exact"
$ExactSourcePaths = $SlamSources | ForEach-Object { Join-Path $ExactDir $_ }
Invoke-Build "exact baseline executable" (@("-O3", "-w") + $ExactSourcePaths + @("-o", (Join-Path $ExactDir "main.exe")))

if (-not $SkipZOrder) {
    $ZDir = Join-Path $BuildRoot "cpp\baselines\approximate"
    $BinDir = Join-Path $ZDir "bin"
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    Invoke-Build "Z-order executable" @(
        "-O3",
        (Join-Path $ZDir "mtimer.cpp"),
        (Join-Path $ZDir "KDEZKern.cpp"),
        "-o", (Join-Path $BinDir "KDEZKern.exe")
    )
}

Write-Host "[done] build complete"
} finally {
    if ($SubstDrive -ne "") {
        cmd /c "subst $SubstDrive /D" | Out-Null
    }
    $env:PATH = $OriginalPath
}
