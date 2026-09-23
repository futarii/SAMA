param(
    [string]$Dataset = "datasets\crime.txt",
    [string]$OutRoot = "experiments\results",
    [string]$DatasetTag = "",
    [string]$RunTag = "",
    [int]$TimeoutSeconds = 0,
    [int]$QuickTimeoutSeconds = 120,
    [int]$BaselineTimeoutSeconds = 14400,
    [switch]$DevelopmentTimeout,
    [switch]$Quick,
    [switch]$Sf311Light,
    [switch]$NoZOrder,
    [switch]$WithZOrder,
    [switch]$ZOrderOnly,
    [switch]$Resume,
    [switch]$AllMethods,
    [ValidateSet("none", "diagnostic", "all")]
    [string]$OutputRetention = "none",
    [string[]]$Groups = @("default"),
    [string[]]$MethodKeys = @(),
    [double]$ZOrderEpsilon = 0.01,
    [ValidateSet("SCAN", "RQS_ball")]
    [string]$ZOrderEvalMethod = "SCAN",
    [ValidateSet("script", "expected_fast_first")]
    [string]$ExecutionOrder = "script",
    [string[]]$MethodOrder = @(),
    [int]$CustomRows = 0,
    [int]$CustomCols = 0
)

$ErrorActionPreference = "Stop"

if ($DevelopmentTimeout) {
    $TimeoutSeconds = 300
}
if ($Quick) {
    $Groups = @("quick")
    if (-not $PSBoundParameters.ContainsKey("TimeoutSeconds")) {
        $TimeoutSeconds = $QuickTimeoutSeconds
    }
}
if ($Sf311Light) {
    if (-not $PSBoundParameters.ContainsKey("Dataset")) {
        $Dataset = "datasets\sf_311_cases.txt"
    }
    if (-not $PSBoundParameters.ContainsKey("DatasetTag")) {
        $DatasetTag = "sf_311_cases"
    }
    if (-not $PSBoundParameters.ContainsKey("Groups")) {
        $Groups = @(
            "resolution",
            "bandwidth",
            "zoom_pan",
            "kernels",
            "dataset_size",
            "memory",
            "kernel_dataset_size",
            "mechanism",
            "parameter_sensitivity",
            "correctness"
        )
    }
    if (-not $PSBoundParameters.ContainsKey("MethodKeys")) {
        $MethodKeys = @("m7", "m8")
    }
    if (-not $PSBoundParameters.ContainsKey("OutputRetention")) {
        $OutputRetention = "none"
    }
    $NoZOrder = $true
}

$Repo = Resolve-Path "."
$DatasetPath = Resolve-Path $Dataset
if ($DatasetTag -eq "") {
    $DatasetTag = [System.IO.Path]::GetFileNameWithoutExtension($DatasetPath.Path)
}
if ($RunTag -eq "") {
    $RunTag = Get-Date -Format "yyyyMMdd_HHmmss"
}
$OutRoot = Join-Path (Join-Path $OutRoot $DatasetTag) $RunTag
$SamaExe = Join-Path $Repo "cpp\sama\kdv_experiment.exe"
$SlamDir = Join-Path $Repo "cpp\baselines\exact"
$SlamExe = Join-Path $SlamDir "main.exe"
$SlamInput = Join-Path $SlamDir "crime_slam_input.txt"
$RqsDir = $SlamDir
$RqsExe = $SlamExe
$RqsInput = $SlamInput
$HeaderInput = Join-Path $OutRoot "_dataset_slam_input.txt"
$ZOrderDir = Join-Path $Repo "cpp\baselines\approximate"
$MsysUcrtBin = ""

$SamaDefaults = @{
    MinTile = 8
    Leaf = 64
    Work = 200000
}

$Methods = @(
    @{ Key = "m0"; Label = "SCAN"; Id = 0; Kernels = @(0, 1, 2); Fast = $false },
    @{ Key = "m1"; Label = "aKDE"; Id = 1; Kernels = @(0, 1, 2); Fast = $false },
    @{ Key = "m2"; Label = "QUAD"; Id = 2; Kernels = @(1); Fast = $false },
    @{ Key = "m3"; Label = "RQS_kd"; Id = 3; Kernels = @(0, 1, 2); Fast = $false },
    @{ Key = "m4"; Label = "RQS_ball"; Id = 4; Kernels = @(0, 1, 2); Fast = $false },
    @{ Key = "m5"; Label = "SLAM_SORT"; Id = 5; Kernels = @(0, 1, 2); Fast = $true },
    @{ Key = "m6"; Label = "SLAM_BUCKET"; Id = 6; Kernels = @(0, 1, 2); Fast = $true },
    @{ Key = "m7"; Label = "SLAM_SORT_RAO"; Id = 7; Kernels = @(0, 1, 2); Fast = $true },
    @{ Key = "m8"; Label = "SLAM_BUCKET_RAO"; Id = 8; Kernels = @(0, 1, 2); Fast = $true }
)

$Kernels = @{
    Uniform = 0
    Epanechnikov = 1
    Quartic = 2
}
$ZOrderCache = @{}
$DatasetSampleCache = @{}
$RepresentativeOutputCache = @{}
$CoreMethodKeys = @("m5", "m6", "m7", "m8")

function Get-SelectedMethods {
    param([switch]$FastOnly, [switch]$AllMethods)
    $selected = $Methods
    if (!$AllMethods) {
        $core = @{}
        foreach ($key in $CoreMethodKeys) { $core[$key] = $true }
        $selected = $selected | Where-Object { $core.ContainsKey($_.Key) }
    }
    if ($FastOnly) {
        $selected = $selected | Where-Object { $_.Fast }
    }
    if ($MethodKeys.Count -gt 0) {
        $set = @{}
        foreach ($key in $MethodKeys) { $set[$key] = $true }
        $selected = $selected | Where-Object { $set.ContainsKey($_.Key) }
    }
    return @($selected)
}

function Get-CaseTaskOrder {
    param(
        [object[]]$SelectedMethods,
        [switch]$SamaOnly,
        [switch]$IncludeZOrder,
        [switch]$ZOrderOnly
    )
    if ($ZOrderOnly) {
        if ($IncludeZOrder) { return @("zorder") }
        return @()
    }
    $available = @{}
    $defaultOrder = @("SAMA")
    if (!$SamaOnly) {
        foreach ($m in $SelectedMethods) {
            $available[$m.Key] = $true
            $defaultOrder += $m.Key
        }
    }
    if ($IncludeZOrder) {
        $available["zorder"] = $true
        $defaultOrder += "zorder"
    }
    $available["SAMA"] = $true

    if ($MethodOrder.Count -gt 0) {
        $preferred = @($MethodOrder)
    } elseif ($ExecutionOrder -eq "expected_fast_first") {
        $preferred = @("SAMA", "m8", "m7", "zorder", "m4", "m3", "m2", "m1", "m0", "m6", "m5")
    } else {
        $preferred = $defaultOrder
    }

    $seen = @{}
    $ordered = @()
    foreach ($key in $preferred) {
        if ($available.ContainsKey($key) -and !$seen.ContainsKey($key)) {
            $ordered += $key
            $seen[$key] = $true
        }
    }
    foreach ($key in $defaultOrder) {
        if (!$seen.ContainsKey($key)) {
            $ordered += $key
            $seen[$key] = $true
        }
    }
    return @($ordered)
}

function Get-ZOrderExe {
    $candidates = @(
        (Join-Path $ZOrderDir "bin\KDEZKern.exe"),
        (Join-Path $ZOrderDir "bin\KDEZKern")
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return ""
}

function Ensure-Tools {
    if (!(Test-Path $SamaExe)) {
        throw "Missing $SamaExe. Build kdv_experiment.exe first."
    }
    if (!(Test-Path $SlamExe)) {
        throw "Missing $SlamExe. Build SLAM main.exe first."
    }
    if (!(Test-Path $RqsExe)) {
        throw "Missing $RqsExe. Build RQS main.exe first."
    }
    if (!(Test-Path $HeaderInput)) {
        Invoke-SamaPrepare $Dataset $HeaderInput "$HeaderInput.log" | Out-Null
    }
    Copy-Item $HeaderInput $SlamInput -Force
    Copy-Item $HeaderInput $RqsInput -Force
}

function Get-SlamDerivedRuntime {
    param([hashtable]$Method)
    if ($Method.Id -eq 3 -or $Method.Id -eq 4) {
        return @{ Dir = $RqsDir; Exe = $RqsExe }
    }
    return @{ Dir = $SlamDir; Exe = $SlamExe }
}

function Get-DatasetBounds {
    $xmin = [double]::PositiveInfinity
    $xmax = [double]::NegativeInfinity
    $ymin = [double]::PositiveInfinity
    $ymax = [double]::NegativeInfinity
    $reader = [System.IO.StreamReader]::new($DatasetPath.Path)
    try {
        while (($line = $reader.ReadLine()) -ne $null) {
            $line = $line.Trim()
            if ($line.Length -eq 0) { continue }
            $parts = $line -split '\s+'
            if ($parts.Count -lt 2) { continue }
            $x = [double]$parts[0]
            $y = [double]$parts[1]
            if ($x -lt $xmin) { $xmin = $x }
            if ($x -gt $xmax) { $xmax = $x }
            if ($y -lt $ymin) { $ymin = $y }
            if ($y -gt $ymax) { $ymax = $y }
        }
    }
    finally {
        $reader.Close()
    }
    return @{ XMin = $xmin; XMax = $xmax; YMin = $ymin; YMax = $ymax }
}

function New-CenteredRegion {
    param([hashtable]$Bounds, [double]$Ratio)
    $cx = ($Bounds.XMin + $Bounds.XMax) / 2.0
    $cy = ($Bounds.YMin + $Bounds.YMax) / 2.0
    $halfW = ($Bounds.XMax - $Bounds.XMin) * $Ratio / 2.0
    $halfH = ($Bounds.YMax - $Bounds.YMin) * $Ratio / 2.0
    return @{ XMin = $cx - $halfW; XMax = $cx + $halfW; YMin = $cy - $halfH; YMax = $cy + $halfH }
}

function New-PanRegions {
    param([hashtable]$Bounds)
    $w = ($Bounds.XMax - $Bounds.XMin) * 0.5
    $h = ($Bounds.YMax - $Bounds.YMin) * 0.5
    $positions = @(
        @{ X = 0.0; Y = 0.0 },
        @{ X = 0.5; Y = 0.0 },
        @{ X = 0.0; Y = 0.5 },
        @{ X = 0.5; Y = 0.5 },
        @{ X = 0.25; Y = 0.25 }
    )
    $regions = @()
    foreach ($p in $positions) {
        $x0 = $Bounds.XMin + ($Bounds.XMax - $Bounds.XMin - $w) * $p.X
        $y0 = $Bounds.YMin + ($Bounds.YMax - $Bounds.YMin - $h) * $p.Y
        $regions += @{ XMin = $x0; XMax = $x0 + $w; YMin = $y0; YMax = $y0 + $h }
    }
    return $regions
}

function Run-ProcessWithTimeout {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [int]$Timeout,
        [string]$StdoutPath
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($MsysUcrtBin -ne "" -and (Test-Path $MsysUcrtBin)) {
        $psi.Environment["PATH"] = "$MsysUcrtBin;$($psi.Environment["PATH"])"
    }
    $psi.Arguments = ($Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join " "
    $proc = [System.Diagnostics.Process]::Start($psi)
    $maxWorkingSet = 0L
    $deadline = if ($Timeout -gt 0) { [DateTime]::UtcNow.AddSeconds($Timeout) } else { [DateTime]::MaxValue }
    $ok = $true
    while (!$proc.HasExited) {
        try {
            $proc.Refresh()
            if ($proc.WorkingSet64 -gt $maxWorkingSet) { $maxWorkingSet = $proc.WorkingSet64 }
        } catch {}
        if ([DateTime]::UtcNow -ge $deadline) {
            $ok = $false
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (!$ok) {
        $proc.Kill()
        $proc.WaitForExit()
        try {
            $proc.Refresh()
            if ($proc.WorkingSet64 -gt $maxWorkingSet) { $maxWorkingSet = $proc.WorkingSet64 }
        } catch {}
        $peakMb = if ($maxWorkingSet -gt 0) { [math]::Round($maxWorkingSet / 1MB, 3) } else { "" }
        "TIMEOUT after ${Timeout}s" | Set-Content $StdoutPath
        return @{ Status = "timeout"; Output = "TIMEOUT"; ExitCode = -1; PeakMemoryMB = $peakMb }
    }
    $proc.WaitForExit()
    try {
        $proc.Refresh()
        if ($proc.WorkingSet64 -gt $maxWorkingSet) { $maxWorkingSet = $proc.WorkingSet64 }
    } catch {}
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $peakMb = if ($maxWorkingSet -gt 0) { [math]::Round($maxWorkingSet / 1MB, 3) } else { "" }
    ($stdout + $stderr) | Set-Content $StdoutPath
    if ($proc.ExitCode -ne 0) {
        return @{ Status = "error"; Output = $stdout + $stderr; ExitCode = $proc.ExitCode; PeakMemoryMB = $peakMb }
    }
    return @{ Status = "completed"; Output = $stdout + $stderr; ExitCode = 0; PeakMemoryMB = $peakMb }
}

function Invoke-SamaPrepare {
    param([string]$InputPath, [string]$OutputPath, [string]$LogPath)
    $result = Run-ProcessWithTimeout -FilePath $SamaExe -Arguments @("prepare", $InputPath, $OutputPath) -WorkingDirectory $Repo -Timeout 0 -StdoutPath $LogPath
    if ($result.Status -ne "completed") {
        throw "prepare failed for $InputPath; see $LogPath"
    }
    return $result.Output
}

function Parse-Seconds {
    param([string]$Text, [string]$Pattern)
    $m = [regex]::Match($Text, $Pattern)
    if ($m.Success) { return [double]$m.Groups[1].Value }
    return $null
}

function Parse-Count {
    param([string]$Text)
    $m = [regex]::Match($Text, "points=([0-9]+)")
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

function Parse-LogField {
    param([string]$Text, [string]$Name)
    $m = [regex]::Match($Text, "$Name=([-+0-9.eE]+)")
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function ConvertTo-SafeName {
    param([string]$Text)
    return (($Text -replace '[^A-Za-z0-9_.-]+', '_').Trim('_'))
}

function Should-KeepOutput {
    param(
        [string]$GroupDir,
        [string]$Method,
        [switch]$ForceKeep
    )
    if ($ForceKeep) { return $true }
    if ($OutputRetention -eq "all") { return $true }
    if ($OutputRetention -eq "none") { return $false }
    $groupName = Split-Path $GroupDir -Leaf
    $family = if ($Method -like "SAMA*") { "SAMA" } else { "SLAM" }
    $cacheKey = "$groupName|$family"
    if (-not $RepresentativeOutputCache.ContainsKey($cacheKey)) {
        $RepresentativeOutputCache[$cacheKey] = $true
        return $true
    }
    return $false
}

function Remove-IfExists {
    param([string]$Path)
    if ($Path -and $Path -ne "-" -and (Test-Path $Path)) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Import-RuntimeRows {
    param([string]$Path)
    if ($Resume -and (Test-Path $Path)) {
        return @(Import-Csv $Path)
    }
    return @()
}

function Get-ExistingRuntimeRow {
    param([object[]]$Rows, [string]$CaseName, [string]$Method)
    return @($Rows | Where-Object { $_.case -eq $CaseName -and $_.method -eq $Method } | Select-Object -Last 1)[0]
}

function Should-SkipRuntimeRow {
    param([object[]]$Rows, [string]$CaseName, [string]$Method)
    $existing = Get-ExistingRuntimeRow $Rows $CaseName $Method
    return ($null -ne $existing -and ($existing.status -eq "completed" -or $existing.status -eq "skipped"))
}

function Upsert-RuntimeRow {
    param([object[]]$Rows, $Row)
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($existing in @($Rows)) {
        if ($null -eq $existing) { continue }
        if (-not ($existing.case -eq $Row.case -and $existing.method -eq $Row.method)) {
            $items.Add($existing)
        }
    }
    if ($null -ne $Row) {
        $items.Add($Row)
    }
    return @($items.ToArray())
}

function Merge-RuntimeRow {
    param([ref]$Rows, $Row)
    $Rows.Value = @(Upsert-RuntimeRow $Rows.Value $Row)
}

function New-Row {
    param(
        [string]$CaseName,
        [string]$Method,
        [string]$Status,
        $Seconds,
        [int]$Rows,
        [int]$Cols,
        [double]$BandwidthRatio,
        [int]$Kernel,
        [string]$Output,
        [string]$Log,
        [string]$Note = "",
        [int]$SampleSize = 0,
        $SamplingSeconds = "",
        $EvalSeconds = "",
        $PeakMemoryMB = "",
        $BuildSeconds = "",
        $SolveSeconds = "",
        $TreeNodes = "",
        $FullNodes = "",
        $EmptyNodes = "",
        $BoundaryNodes = "",
        $BoundaryPoints = "",
        $RootFullLeafNodes = "",
        $RootEmptyLeafNodes = "",
        $RootBoundaryLeafNodes = "",
        $RootFullPoints = "",
        $RootEmptyPoints = "",
        $RootBoundaryPoints = "",
        $SplitTiles = "",
        $EvaluatedTiles = "",
        $TerminalTiles = "",
        $TerminalBoundaryLeafRefs = "",
        $AvgTerminalBoundaryLeafNodes = "",
        $MaxTerminalBoundaryLeafNodes = "",
        $PointPixelTests = "",
        $FullWorkAggregated = "",
        $BoundaryWorkScanned = "",
        $EmptyWorkPruned = "",
        $TotalPotentialWork = ""
    )
    return [PSCustomObject]@{
        case = $CaseName
        method = $Method
        status = $Status
        seconds = $(if ($null -eq $Seconds) { "" } else { $Seconds })
        rows = $Rows
        cols = $Cols
        bandwidth_ratio = $BandwidthRatio
        kernel = $Kernel
        sample_size = $SampleSize
        sampling_seconds = $SamplingSeconds
        eval_seconds = $EvalSeconds
        peak_memory_mb = $PeakMemoryMB
        build_seconds = $BuildSeconds
        solve_seconds = $SolveSeconds
        tree_nodes = $TreeNodes
        full_nodes = $FullNodes
        empty_nodes = $EmptyNodes
        boundary_nodes = $BoundaryNodes
        boundary_points_seen = $BoundaryPoints
        root_full_leaf_nodes = $RootFullLeafNodes
        root_empty_leaf_nodes = $RootEmptyLeafNodes
        root_boundary_leaf_nodes = $RootBoundaryLeafNodes
        root_full_points = $RootFullPoints
        root_empty_points = $RootEmptyPoints
        root_boundary_points = $RootBoundaryPoints
        split_tiles = $SplitTiles
        evaluated_tiles = $EvaluatedTiles
        terminal_tiles = $TerminalTiles
        terminal_boundary_leaf_refs = $TerminalBoundaryLeafRefs
        avg_terminal_boundary_leaf_nodes = $AvgTerminalBoundaryLeafNodes
        max_terminal_boundary_leaf_nodes = $MaxTerminalBoundaryLeafNodes
        point_pixel_tests = $PointPixelTests
        full_work_aggregated = $FullWorkAggregated
        boundary_work_scanned = $BoundaryWorkScanned
        empty_work_pruned = $EmptyWorkPruned
        total_potential_work = $TotalPotentialWork
        output = $Output
        log = $Log
        note = $Note
    }
}

function Run-SamaCase {
    param(
        [string]$GroupDir,
        [string]$CaseName,
        [int]$Rows,
        [int]$Cols,
        [double]$BandwidthRatio,
        [int]$Kernel,
        [hashtable]$Region = $null,
        [string]$InputDataset = $Dataset,
        [string]$MethodLabel = "SAMA",
        [int]$Variant = 0,
        [hashtable]$ParamOverride = @{},
        [switch]$ForceKeepOutput,
        [switch]$CollectWork
    )
    $params = $SamaDefaults.Clone()
    foreach ($key in $ParamOverride.Keys) {
        $params[$key] = $ParamOverride[$key]
    }
    $suffix = ConvertTo-SafeName $MethodLabel
    $keepOutput = Should-KeepOutput $GroupDir $MethodLabel -ForceKeep:$ForceKeepOutput
    $outTxt = if ($keepOutput) { Join-Path $GroupDir "${CaseName}_${suffix}.txt" } else { "-" }
    $outPpm = if ($keepOutput) { Join-Path $GroupDir "${CaseName}_${suffix}.ppm" } else { "-" }
    $log = Join-Path $GroupDir "${CaseName}_${suffix}.log"
    $args = @(
        "sbd", $InputDataset, $outTxt, $outPpm,
        "$Rows", "$Cols", "$BandwidthRatio",
        "$($params.MinTile)", "$($params.Leaf)", "$($params.Work)", "$Kernel", "$Variant"
    )
    if ($CollectWork) {
        $args += "--collect-work"
    }
    if ($null -ne $Region) {
        $args += @("$($Region.XMin)", "$($Region.XMax)", "$($Region.YMin)", "$($Region.YMax)")
    }
    $result = Run-ProcessWithTimeout -FilePath $SamaExe -Arguments $args -WorkingDirectory $Repo -Timeout $TimeoutSeconds -StdoutPath $log
    $time = Parse-Seconds $result.Output "seconds=([0-9.]+)"
    $note = "variant=$Variant; min_tile=$($params.MinTile); leaf=$($params.Leaf); work=$($params.Work); collect_work=$($CollectWork.IsPresent); output_retention=$OutputRetention"
    return New-Row $CaseName $MethodLabel $result.Status $time $Rows $Cols $BandwidthRatio $Kernel $outTxt $log $note 0 "" "" $result.PeakMemoryMB `
        (Parse-LogField $result.Output "build_seconds") `
        (Parse-LogField $result.Output "solve_seconds") `
        (Parse-LogField $result.Output "tree_nodes") `
        (Parse-LogField $result.Output "full_nodes") `
        (Parse-LogField $result.Output "empty_nodes") `
        (Parse-LogField $result.Output "boundary_nodes") `
        (Parse-LogField $result.Output "boundary_points_seen") `
        (Parse-LogField $result.Output "root_full_leaf_nodes") `
        (Parse-LogField $result.Output "root_empty_leaf_nodes") `
        (Parse-LogField $result.Output "root_boundary_leaf_nodes") `
        (Parse-LogField $result.Output "root_full_points") `
        (Parse-LogField $result.Output "root_empty_points") `
        (Parse-LogField $result.Output "root_boundary_points") `
        (Parse-LogField $result.Output "split_tiles") `
        (Parse-LogField $result.Output "evaluated_tiles") `
        (Parse-LogField $result.Output "terminal_tiles") `
        (Parse-LogField $result.Output "terminal_boundary_leaf_refs") `
        (Parse-LogField $result.Output "avg_terminal_boundary_leaf_nodes") `
        (Parse-LogField $result.Output "max_terminal_boundary_leaf_nodes") `
        (Parse-LogField $result.Output "point_pixel_tests") `
        (Parse-LogField $result.Output "full_work_aggregated") `
        (Parse-LogField $result.Output "boundary_work_scanned") `
        (Parse-LogField $result.Output "empty_work_pruned") `
        (Parse-LogField $result.Output "total_potential_work")
}

function Run-SlamCase {
    param(
        [string]$GroupDir,
        [string]$CaseName,
        [int]$Rows,
        [int]$Cols,
        [double]$BandwidthRatio,
        [int]$Kernel,
        [hashtable]$Method,
        [string]$InputLocal = "crime_slam_input.txt",
        [string]$OutputSuffix = "",
        [hashtable]$Region = $null,
        [switch]$ForceKeepOutput
    )
    if ($Method.Kernels -notcontains $Kernel) {
        return New-Row $CaseName $Method.Label "skipped" $null $Rows $Cols $BandwidthRatio $Kernel "" "" "kernel_not_supported_by_released_QUAD_path"
    }

    $suffix = if ($OutputSuffix -eq "") { $Method.Key } else { "$($Method.Key)_$OutputSuffix" }
    $keepOutput = Should-KeepOutput $GroupDir $Method.Label -ForceKeep:$ForceKeepOutput
    $outTxtLocal = if ($keepOutput) { "results_${CaseName}_${suffix}.txt" } else { "-" }
    $runtime = Get-SlamDerivedRuntime $Method
    $methodDir = $runtime.Dir
    $methodExe = $runtime.Exe
    $outTxt = if ($keepOutput) { Join-Path $methodDir $outTxtLocal } else { "-" }
    $log = Join-Path $GroupDir "${CaseName}_${suffix}.log"
    $args = @(
        $InputLocal, $outTxtLocal, "$BandwidthRatio", "$($Method.Id)",
        "$Rows", "$Cols", "$Kernel", "0.05"
    )
    if ($null -ne $Region) {
        $args += @("$($Region.XMin)", "$($Region.XMax)", "$($Region.YMin)", "$($Region.YMax)")
    }
    $result = Run-ProcessWithTimeout -FilePath $methodExe -Arguments $args -WorkingDirectory $methodDir -Timeout $TimeoutSeconds -StdoutPath $log
    $time = Parse-Seconds $result.Output "method\s+\d+:([0-9.]+)"
    $copied = if ($keepOutput) { Join-Path $GroupDir "${CaseName}_${suffix}.txt" } else { "-" }
    if ($keepOutput -and (Test-Path $outTxt)) {
        Copy-Item $outTxt $copied -Force
        Remove-IfExists $outTxt
    }
    return New-Row $CaseName $Method.Label $result.Status $time $Rows $Cols $BandwidthRatio $Kernel $copied $log "" 0 "" "" $result.PeakMemoryMB
}

function Run-ZOrderCase {
    param(
        [string]$GroupDir,
        [string]$CaseName,
        [int]$Rows,
        [int]$Cols,
        [double]$BandwidthRatio,
        [int]$Kernel
    )
    $zOrderLabel = "Z-order"
    if ($NoZOrder) {
        return New-Row $CaseName $zOrderLabel "skipped" $null $Rows $Cols $BandwidthRatio $Kernel "" "" "disabled_by_NoZOrder"
    }

    $zExe = Get-ZOrderExe
    if ($zExe -eq "") {
        return New-Row $CaseName $zOrderLabel "skipped" $null $Rows $Cols $BandwidthRatio $Kernel "" "" "missing_KDEZKern_executable"
    }

    $cacheKey = "$GroupDir|$ZOrderEpsilon"
    if (-not $ZOrderCache.ContainsKey($cacheKey)) {
        $epsLabel = ("{0:g}" -f $ZOrderEpsilon).Replace(".", "p")
        $sampleRaw = Join-Path $GroupDir "zorder_cache_eps${epsLabel}_sample.txt"
        $sampleHeader = Join-Path $GroupDir "zorder_cache_eps${epsLabel}_sample_header.txt"
        $sampleLocal = "zorder_cache_eps${epsLabel}_sample_header.txt"
        $sampleLocalPath = Join-Path $SlamDir $sampleLocal
        $sampleLocalPathRqs = Join-Path $RqsDir $sampleLocal
        $sampleLog = Join-Path $GroupDir "zorder_cache_eps${epsLabel}_sample.log"
        $prepareLog = Join-Path $GroupDir "zorder_cache_eps${epsLabel}_prepare.log"

        $sampleResult = Run-ProcessWithTimeout -FilePath $zExe -Arguments @($Dataset, $sampleRaw, "$ZOrderEpsilon") -WorkingDirectory $Repo -Timeout $TimeoutSeconds -StdoutPath $sampleLog
        if ($sampleResult.Status -ne "completed") {
            return New-Row $CaseName $zOrderLabel $sampleResult.Status $null $Rows $Cols $BandwidthRatio $Kernel "" $sampleLog "sampling_failed"
        }
        $samplingSeconds = Parse-Seconds $sampleResult.Output "time spend\s+([0-9.]+)"

        $prepareOut = Invoke-SamaPrepare $sampleRaw $sampleHeader $prepareLog
        $sampleSize = Parse-Count $prepareOut
        Copy-Item $sampleHeader $sampleLocalPath -Force
        Copy-Item $sampleHeader $sampleLocalPathRqs -Force

        $ZOrderCache[$cacheKey] = @{
            InputLocal = $sampleLocal
            SampleSize = $sampleSize
            SamplingSeconds = $samplingSeconds
            SampleLog = $sampleLog
            PrepareLog = $prepareLog
        }
    }
    $cached = $ZOrderCache[$cacheKey]

    $evalId = if ($ZOrderEvalMethod -eq "SCAN") { 0 } else { 4 }
    $evalKey = if ($ZOrderEvalMethod -eq "SCAN") { "zorder_scan" } else { "zorder_rqsball" }
    $evalSuffix = if ($ZOrderEvalMethod -eq "SCAN") { "scan_eval" } else { "rqsball_eval" }
    $method = @{ Key = $evalKey; Label = $zOrderLabel; Id = $evalId; Kernels = @(0, 1, 2); Fast = $true }
    $eval = Run-SlamCase $GroupDir $CaseName $Rows $Cols $BandwidthRatio $Kernel $method $cached.InputLocal $evalSuffix
    $evalSeconds = if ($eval.seconds -eq "") { $null } else { [double]$eval.seconds }
    $total = if ($null -ne $cached.SamplingSeconds -and $null -ne $evalSeconds) { $cached.SamplingSeconds + $evalSeconds } else { $null }
    return New-Row $CaseName $zOrderLabel $eval.status $total $Rows $Cols $BandwidthRatio $Kernel $eval.output $eval.log "epsilon=$ZOrderEpsilon; eval_method=$ZOrderEvalMethod; sample_log=$($cached.SampleLog)" $cached.SampleSize $cached.SamplingSeconds $evalSeconds $eval.peak_memory_mb
}

function Save-Rows {
    param([object[]]$Rows, [string]$Path)
    $clean = @($Rows | Where-Object { $null -ne $_ })
    if ($clean.Count -eq 0) {
        Set-Content -Path $Path -Value "" -Encoding UTF8
        return
    }
    $clean | Export-Csv -NoTypeInformation -Encoding UTF8 $Path
}

function Read-DatasetPointLines {
    param([string]$Path)
    $points = [System.Collections.Generic.List[string]]::new()
    $reader = [System.IO.StreamReader]::new($Path)
    try {
        $firstLine = $reader.ReadLine()
        if ($null -eq $firstLine) { return ,$points }
        $firstParts = $firstLine.Trim() -split '\s+'
        if ($firstParts.Count -eq 1 -and $firstParts[0] -match '^[0-9]+$') {
            $secondLine = $reader.ReadLine()
            if ($null -ne $secondLine -and $secondLine.Trim() -ne "2") {
                $secondParts = $secondLine.Trim() -split '\s+'
                if ($secondParts.Count -ge 2) {
                    $points.Add("$($secondParts[0]) $($secondParts[1])")
                }
            }
        }
        elseif ($firstParts.Count -ge 2) {
            $points.Add("$($firstParts[0]) $($firstParts[1])")
        }
        while (($line = $reader.ReadLine()) -ne $null) {
            $parts = $line.Trim() -split '\s+'
            if ($parts.Count -ge 2) {
                $points.Add("$($parts[0]) $($parts[1])")
            }
        }
    }
    finally {
        $reader.Close()
    }
    return ,$points
}

function Get-SampledDataset {
    param([double]$Fraction)
    $fractionLabel = ("{0:g}" -f $Fraction).Replace(".", "p")
    if ($DatasetSampleCache.ContainsKey($fractionLabel)) {
        return $DatasetSampleCache[$fractionLabel]
    }

    if ($Fraction -ge 0.999999) {
        $points = Read-DatasetPointLines $DatasetPath.Path
        $full = @{
            Raw = $DatasetPath.Path
            Header = $HeaderInput
            Local = "crime_slam_input.txt"
            SampleSize = $points.Count
            Fraction = $Fraction
        }
        $DatasetSampleCache[$fractionLabel] = $full
        return $full
    }

    $sampleDir = Join-Path $OutRoot "_samples"
    New-Item -ItemType Directory -Force $sampleDir | Out-Null
    $raw = Join-Path $sampleDir "sample_f${fractionLabel}.txt"
    $header = Join-Path $sampleDir "sample_f${fractionLabel}_header.txt"
    $local = "sample_${DatasetTag}_${RunTag}_f${fractionLabel}_header.txt"
    $localPath = Join-Path $SlamDir $local
    $localPathRqs = Join-Path $RqsDir $local

    if (!(Test-Path $raw)) {
        $allPoints = Read-DatasetPointLines $DatasetPath.Path
        $target = [Math]::Max(1, [int][Math]::Floor($allPoints.Count * $Fraction))
        $reservoir = [System.Collections.Generic.List[string]]::new()
        $rng = [System.Random]::new(20240229 + [int]($Fraction * 1000000))
        for ($i = 0; $i -lt $allPoints.Count; $i++) {
            if ($reservoir.Count -lt $target) {
                $reservoir.Add($allPoints[$i])
            }
            else {
                $j = $rng.Next($i + 1)
                if ($j -lt $target) {
                    $reservoir[$j] = $allPoints[$i]
                }
            }
        }
        [System.IO.File]::WriteAllLines($raw, $reservoir)
    }
    $prepareOut = Invoke-SamaPrepare $raw $header "$header.log"
    $sampleSize = Parse-Count $prepareOut
    Copy-Item $header $localPath -Force
    Copy-Item $header $localPathRqs -Force

    $sample = @{
        Raw = $raw
        Header = $header
        Local = $local
        SampleSize = $sampleSize
        Fraction = $Fraction
    }
    $DatasetSampleCache[$fractionLabel] = $sample
    return $sample
}

function Add-SampleMetadata {
    param($Row, [hashtable]$Sample, [double]$Fraction)
    $Row.sample_size = $Sample.SampleSize
    $prefix = "fraction=$Fraction"
    $Row.note = if ($Row.note -eq "") { $prefix } else { "$prefix; $($Row.note)" }
    return $Row
}

function Run-CaseMatrix {
    param(
        [string]$DirName,
        [object[]]$Resolutions,
        [double[]]$BandwidthRatios,
        [int[]]$KernelIds,
        [switch]$FastOnly,
        [switch]$AllMethods,
        [switch]$SamaOnly,
        [switch]$IncludeZOrder,
        [object[]]$Regions = @($null)
    )
    $dir = Join-Path $OutRoot $DirName
    New-Item -ItemType Directory -Force $dir | Out-Null
    $csvPath = Join-Path $dir "runtime.csv"
    $rowsOut = Import-RuntimeRows $csvPath
    $selectedMethods = Get-SelectedMethods -FastOnly:$FastOnly -AllMethods:$AllMethods
    $selectedByKey = @{}
    foreach ($m in $selectedMethods) { $selectedByKey[$m.Key] = $m }
    $taskOrder = Get-CaseTaskOrder $selectedMethods -SamaOnly:$SamaOnly -IncludeZOrder:$IncludeZOrder -ZOrderOnly:$ZOrderOnly

    foreach ($kernel in $KernelIds) {
        foreach ($res in $Resolutions) {
            foreach ($ratio in $BandwidthRatios) {
                $ratioLabel = ("{0:g}" -f $ratio).Replace(".", "p")
                foreach ($regionEntry in $Regions) {
                    $regionName = if ($null -eq $regionEntry) { "" } else { "_$($regionEntry.Name)" }
                    $region = if ($null -eq $regionEntry) { $null } else { $regionEntry.Region }
                    $case = "${DirName}${regionName}_r$($res.Rows)_c$($res.Cols)_k${kernel}_b${ratioLabel}"
                    foreach ($task in $taskOrder) {
                        if ($task -eq "SAMA") {
                            if (!(Should-SkipRuntimeRow $rowsOut $case "SAMA")) {
                                $rowsOut = Upsert-RuntimeRow $rowsOut (Run-SamaCase $dir $case $res.Rows $res.Cols $ratio $kernel $region -CollectWork:($DirName -eq "mechanism"))
                                Save-Rows $rowsOut $csvPath
                            }
                        } elseif ($task -eq "zorder") {
                            if (!(Should-SkipRuntimeRow $rowsOut $case "Z-order")) {
                                $rowsOut = Upsert-RuntimeRow $rowsOut (Run-ZOrderCase $dir $case $res.Rows $res.Cols $ratio $kernel)
                                Save-Rows $rowsOut $csvPath
                            }
                        } else {
                            $m = $selectedByKey[$task]
                            if ($null -ne $m -and !(Should-SkipRuntimeRow $rowsOut $case $m.Label)) {
                                $rowsOut = Upsert-RuntimeRow $rowsOut (Run-SlamCase $dir $case $res.Rows $res.Cols $ratio $kernel $m -Region $region)
                                Save-Rows $rowsOut $csvPath
                            }
                        }
                    }
                    Save-Rows $rowsOut $csvPath
                }
            }
        }
    }
}

function Run-DatasetFractionMatrix {
    param(
        [string]$DirName,
        [double[]]$Fractions = @(0.25, 0.5, 0.75, 1.0),
        [int[]]$KernelIds = @($Kernels.Epanechnikov)
    )
    $dir = Join-Path $OutRoot $DirName
    New-Item -ItemType Directory -Force $dir | Out-Null
    $csvPath = Join-Path $dir "runtime.csv"
    $rowsOut = Import-RuntimeRows $csvPath
    $selectedMethods = Get-SelectedMethods
    foreach ($kernel in $KernelIds) {
        foreach ($fraction in $Fractions) {
            $sample = Get-SampledDataset $fraction
            $fractionLabel = ("{0:g}" -f $fraction).Replace(".", "p")
            $case = "${DirName}_f${fractionLabel}_r1280_c960_k${kernel}_b1"
            if (!(Should-SkipRuntimeRow $rowsOut $case "SAMA")) {
                $samaRow = Run-SamaCase $dir $case 1280 960 1.0 $kernel -InputDataset $sample.Raw
                $rowsOut = Upsert-RuntimeRow $rowsOut (Add-SampleMetadata $samaRow $sample $fraction)
            }
            foreach ($m in $selectedMethods) {
                if (!(Should-SkipRuntimeRow $rowsOut $case $m.Label)) {
                    $row = Run-SlamCase $dir $case 1280 960 1.0 $kernel $m -InputLocal $sample.Local
                    $rowsOut = Upsert-RuntimeRow $rowsOut (Add-SampleMetadata $row $sample $fraction)
                }
            }
            Save-Rows $rowsOut $csvPath
        }
    }
}

function Run-CompareValues {
    param(
        [string]$Dir,
        [string]$CaseName,
        [string]$LeftMethod,
        [string]$LeftPath,
        [string]$RightMethod,
        [string]$RightPath,
        [int]$Rows,
        [int]$Cols
    )
    $safeLeft = ConvertTo-SafeName $LeftMethod
    $safeRight = ConvertTo-SafeName $RightMethod
    $leftPpm = Join-Path $Dir "${CaseName}_${safeLeft}_cmp.ppm"
    $rightPpm = Join-Path $Dir "${CaseName}_${safeRight}_cmp.ppm"
    $diffPpm = Join-Path $Dir "${CaseName}_${safeLeft}_vs_${safeRight}_diff.ppm"
    $viewer = Join-Path $Dir "${CaseName}_${safeLeft}_vs_${safeRight}_view.html"
    $log = Join-Path $Dir "${CaseName}_${safeLeft}_vs_${safeRight}_compare.log"
    $title = "${CaseName}: ${LeftMethod} vs ${RightMethod}"
    $result = Run-ProcessWithTimeout -FilePath $SamaExe -Arguments @("compare", $LeftPath, $RightPath, "$Rows", "$Cols", $leftPpm, $rightPpm, $diffPpm, $viewer, $title) -WorkingDirectory $Repo -Timeout 0 -StdoutPath $log
    return [PSCustomObject]@{
        case = $CaseName
        left_method = $LeftMethod
        right_method = $RightMethod
        status = $result.Status
        rmse = (Parse-LogField $result.Output "rmse")
        mae = (Parse-LogField $result.Output "mae")
        max_abs = (Parse-LogField $result.Output "max_abs")
        shared_min = (Parse-LogField $result.Output "shared_min")
        shared_max = (Parse-LogField $result.Output "shared_max")
        viewer = $viewer
        log = $log
    }
}

function Run-Default {
    $rows = if ($CustomRows -gt 0) { $CustomRows } else { 1280 }
    $cols = if ($CustomCols -gt 0) { $CustomCols } else { 960 }
    Run-CaseMatrix "default" @(@{ Rows = $rows; Cols = $cols }) @(1.0) @($Kernels.Epanechnikov) -AllMethods:$AllMethods -IncludeZOrder:($WithZOrder -and !$NoZOrder)
}

function Run-Resolution {
    $resolutions = @(
        @{ Rows = 320; Cols = 240 },
        @{ Rows = 640; Cols = 480 },
        @{ Rows = 1280; Cols = 960 },
        @{ Rows = 2560; Cols = 1920 }
    )
    Run-CaseMatrix "resolution" $resolutions @(1.0) @($Kernels.Epanechnikov)
}

function Run-Bandwidth {
    Run-CaseMatrix "bandwidth" @(@{ Rows = 1280; Cols = 960 }) @(0.25, 0.5, 1.0, 2.0, 4.0) @($Kernels.Epanechnikov)
}

function Run-ZoomPan {
    $bounds = Get-DatasetBounds
    $regions = @()
    foreach ($ratio in @(0.25, 0.5, 0.75, 1.0)) {
        $name = "zoom_$(("{0:g}" -f $ratio).Replace('.', 'p'))"
        $regions += @{ Name = $name; Region = (New-CenteredRegion $bounds $ratio) }
    }
    $pan = New-PanRegions $bounds
    for ($i = 0; $i -lt $pan.Count; $i++) {
        $regions += @{ Name = "pan_$($i + 1)"; Region = $pan[$i] }
    }
    Run-CaseMatrix "zoom_pan" @(@{ Rows = 1280; Cols = 960 }) @(1.0) @($Kernels.Epanechnikov) -Regions $regions
}

function Run-Kernel {
    Run-CaseMatrix "kernels" @(@{ Rows = 320; Cols = 240 }, @{ Rows = 640; Cols = 480 }, @{ Rows = 1280; Cols = 960 }) @(1.0) @($Kernels.Uniform, $Kernels.Epanechnikov, $Kernels.Quartic)
}

function Run-Quick {
    Run-CaseMatrix "quick" @(@{ Rows = 320; Cols = 240 }, @{ Rows = 640; Cols = 480 }) @(0.5, 1.0) @($Kernels.Uniform, $Kernels.Epanechnikov, $Kernels.Quartic) -FastOnly
}

function Run-BaselineScreen {
    $oldTimeout = $script:TimeoutSeconds
    $script:TimeoutSeconds = $BaselineTimeoutSeconds
    try {
        Run-CaseMatrix "baseline_screen" @(@{ Rows = 1280; Cols = 960 }) @(1.0) @($Kernels.Epanechnikov) -AllMethods
    }
    finally {
        $script:TimeoutSeconds = $oldTimeout
    }
}

function Run-DefaultAllMethods {
    $oldTimeout = $script:TimeoutSeconds
    $script:TimeoutSeconds = $BaselineTimeoutSeconds
    try {
        Run-CaseMatrix "default_all_methods" @(@{ Rows = 1280; Cols = 960 }) @(1.0) @($Kernels.Epanechnikov) -AllMethods -IncludeZOrder:(!$NoZOrder)
    }
    finally {
        $script:TimeoutSeconds = $oldTimeout
    }
}

function Run-DatasetSize {
    Run-DatasetFractionMatrix "dataset_size" @(0.25, 0.5, 0.75, 1.0) @($Kernels.Epanechnikov)
}

function Run-Memory {
    Run-DatasetFractionMatrix "memory" @(0.25, 0.5, 0.75, 1.0) @($Kernels.Epanechnikov)
}

function Run-KernelDatasetSize {
    Run-DatasetFractionMatrix "kernel_dataset_size" @(0.25, 0.5, 0.75, 1.0) @($Kernels.Uniform, $Kernels.Quartic)
}

function Run-Mechanism {
    $resolutions = @(
        @{ Rows = 320; Cols = 240 },
        @{ Rows = 640; Cols = 480 },
        @{ Rows = 1280; Cols = 960 },
        @{ Rows = 2560; Cols = 1920 }
    )
    Run-CaseMatrix "mechanism" $resolutions @(0.25, 0.5, 1.0, 2.0, 4.0) @($Kernels.Epanechnikov) -SamaOnly
}

function Run-ParameterSensitivity {
    $dir = Join-Path $OutRoot "parameter_sensitivity"
    New-Item -ItemType Directory -Force $dir | Out-Null
    $csvPath = Join-Path $dir "runtime.csv"
    $rowsOut = Import-RuntimeRows $csvPath
    $configs = @(
        @{ Label = "default"; Params = @{} },
        @{ Label = "min_tile_4"; Params = @{ MinTile = 4 } },
        @{ Label = "min_tile_16"; Params = @{ MinTile = 16 } },
        @{ Label = "leaf_32"; Params = @{ Leaf = 32 } },
        @{ Label = "leaf_128"; Params = @{ Leaf = 128 } },
        @{ Label = "work_50000"; Params = @{ Work = 50000 } },
        @{ Label = "work_800000"; Params = @{ Work = 800000 } }
    )
    foreach ($cfg in $configs) {
        $case = "parameter_sensitivity_$($cfg.Label)_r1280_c960_k1_b1"
        $methodLabel = "SAMA-$($cfg.Label)"
        if (!(Should-SkipRuntimeRow $rowsOut $case $methodLabel)) {
            $rowsOut = Upsert-RuntimeRow $rowsOut (Run-SamaCase $dir $case 1280 960 1.0 $Kernels.Epanechnikov -MethodLabel $methodLabel -ParamOverride $cfg.Params)
        }
        Save-Rows $rowsOut $csvPath
    }
}

function Run-Ablation {
    $dir = Join-Path $OutRoot "ablation"
    New-Item -ItemType Directory -Force $dir | Out-Null
    $csvPath = Join-Path $dir "runtime.csv"
    $rowsOut = Import-RuntimeRows $csvPath
    $rowsOut = @($rowsOut | Where-Object { $_.method -ne "SAMA-no-tile-split" })
    $case = "ablation_r1280_c960_k1_b1"
    if (!(Should-SkipRuntimeRow $rowsOut $case "SAMA-full")) {
        $rowsOut = Upsert-RuntimeRow $rowsOut (Run-SamaCase $dir $case 1280 960 1.0 $Kernels.Epanechnikov -MethodLabel "SAMA-full" -Variant 0)
    }
    if (!(Should-SkipRuntimeRow $rowsOut $case "SAMA-no-full-cover")) {
        $rowsOut = Upsert-RuntimeRow $rowsOut (Run-SamaCase $dir $case 1280 960 1.0 $Kernels.Epanechnikov -MethodLabel "SAMA-no-full-cover" -Variant 1)
    }
    $method = @($Methods | Where-Object { $_.Key -eq "m8" })[0]
    if (!(Should-SkipRuntimeRow $rowsOut $case $method.Label)) {
        $rowsOut = Upsert-RuntimeRow $rowsOut (Run-SlamCase $dir $case 1280 960 1.0 $Kernels.Epanechnikov $method)
    }
    Save-Rows $rowsOut $csvPath
}

function Run-Correctness {
    $dir = Join-Path $OutRoot "correctness"
    New-Item -ItemType Directory -Force $dir | Out-Null
    $csvPath = Join-Path $dir "runtime.csv"
    $rowsOut = Import-RuntimeRows $csvPath
    $accuracyRows = @()
    $sample = Get-SampledDataset 0.01
    $scan = @($Methods | Where-Object { $_.Key -eq "m0" })[0]
    $rao = @($Methods | Where-Object { $_.Key -eq "m8" })[0]
    foreach ($kernel in @($Kernels.Uniform, $Kernels.Epanechnikov, $Kernels.Quartic)) {
        $case = "correctness_f0p01_r160_c120_k${kernel}_b1"
        if (Should-SkipRuntimeRow $rowsOut $case "SAMA") {
            $sama = Get-ExistingRuntimeRow $rowsOut $case "SAMA"
        } else {
            $sama = Add-SampleMetadata (Run-SamaCase $dir $case 160 120 1.0 $kernel -InputDataset $sample.Raw -ForceKeepOutput) $sample 0.01
            $rowsOut = Upsert-RuntimeRow $rowsOut $sama
        }
        if (Should-SkipRuntimeRow $rowsOut $case "SCAN") {
            $scanRow = Get-ExistingRuntimeRow $rowsOut $case "SCAN"
        } else {
            $scanRow = Add-SampleMetadata (Run-SlamCase $dir $case 160 120 1.0 $kernel $scan -InputLocal $sample.Local -ForceKeepOutput) $sample 0.01
            $rowsOut = Upsert-RuntimeRow $rowsOut $scanRow
        }
        if (Should-SkipRuntimeRow $rowsOut $case "SLAM_BUCKET_RAO") {
            $raoRow = Get-ExistingRuntimeRow $rowsOut $case "SLAM_BUCKET_RAO"
        } else {
            $raoRow = Add-SampleMetadata (Run-SlamCase $dir $case 160 120 1.0 $kernel $rao -InputLocal $sample.Local -ForceKeepOutput) $sample 0.01
            $rowsOut = Upsert-RuntimeRow $rowsOut $raoRow
        }
        Save-Rows $rowsOut $csvPath
        if ($sama.status -eq "completed" -and $scanRow.status -eq "completed" -and (Test-Path $sama.output) -and (Test-Path $scanRow.output)) {
            $accuracyRows += Run-CompareValues $dir $case "SAMA" $sama.output "SCAN" $scanRow.output 160 120
        }
        if ($raoRow.status -eq "completed" -and $scanRow.status -eq "completed" -and (Test-Path $raoRow.output) -and (Test-Path $scanRow.output)) {
            $accuracyRows += Run-CompareValues $dir $case "SLAM_BUCKET_RAO" $raoRow.output "SCAN" $scanRow.output 160 120
        }
        if ($accuracyRows.Count -gt 0) {
            $accuracyRows | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $dir "accuracy.csv")
        }
    }
}

New-Item -ItemType Directory -Force $OutRoot | Out-Null
Ensure-Tools

foreach ($group in $Groups) {
    switch ($group) {
        "default" { Run-Default }
        "resolution" { Run-Resolution }
        "bandwidth" { Run-Bandwidth }
        "zoom_pan" { Run-ZoomPan }
        "kernels" { Run-Kernel }
        "quick" { Run-Quick }
        "baseline_screen" { Run-BaselineScreen }
        "default_all_methods" { Run-DefaultAllMethods }
        "dataset_size" { Run-DatasetSize }
        "memory" { Run-Memory }
        "kernel_dataset_size" { Run-KernelDatasetSize }
        "mechanism" { Run-Mechanism }
        "parameter_sensitivity" { Run-ParameterSensitivity }
        "ablation" { Run-Ablation }
        "correctness" { Run-Correctness }
        default { throw "Unknown group: $group" }
    }
}

Write-Host "Done. Results written under $OutRoot"
