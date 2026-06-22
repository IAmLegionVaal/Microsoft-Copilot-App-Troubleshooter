#requires -Version 5.1
<#
.SYNOPSIS
    Microsoft Copilot application repair toolkit.
.DESCRIPTION
    Performs guarded local repairs for the Windows Copilot application, including
    cache rebuild, package reset or re-registration, process restart and DNS repair.
    Every run captures before-and-after evidence and writes a detailed log.
.NOTES
    Created by Dewald Pretorius - L2 IT Support Engineer.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet(
        'Diagnose',
        'RepairAllSafe',
        'RestartApp',
        'ResetCache',
        'ResetAppPackage',
        'ReregisterAppPackage',
        'FlushDns'
    )]
    [string]$Action = 'Diagnose',

    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Copilot_Repair')
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '2.0.1'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupRoot = Join-Path $OutputPath "Backup_$Stamp"
$LogPath = Join-Path $OutputPath "Repair_$Stamp.log"

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8

    switch ($Level) {
        'WARN'    { Write-Host $Message -ForegroundColor Yellow }
        'ERROR'   { Write-Host $Message -ForegroundColor Red }
        'SUCCESS' { Write-Host $Message -ForegroundColor Green }
        default   { Write-Host $Message }
    }
}

function Get-DetectedCopilotPackages {
    return @(
        Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match 'Copilot' -or
            $_.PackageFullName -match 'Copilot' -or
            $_.PackageFamilyName -match 'Copilot' -or
            $_.InstallLocation -match 'Copilot'
        } | Sort-Object Name -Unique
    )
}

function Get-CopilotAppPackages {
    $detected = @(Get-DetectedCopilotPackages)

    return @(
        $detected | Where-Object {
            $_.Name -notmatch '(?i)Provider|Runtime|Framework'
        } | Sort-Object -Property @{
            Expression = {
                if ($_.Name -match '^Microsoft\.Copilot') { 0 }
                elseif ($_.Name -match 'Copilot') { 1 }
                else { 2 }
            }
        }, Name -Unique
    )
}

function Get-CopilotCacheItems {
    $items = @()

    foreach ($package in @(Get-CopilotAppPackages)) {
        if ([string]::IsNullOrWhiteSpace($package.PackageFamilyName)) { continue }

        $packageRoot = Join-Path $env:LOCALAPPDATA "Packages\$($package.PackageFamilyName)"
        $candidatePaths = [ordered]@{
            'LocalCache'         = (Join-Path $packageRoot 'LocalCache')
            'TempState'          = (Join-Path $packageRoot 'TempState')
            'WebView2'           = (Join-Path $packageRoot 'LocalState\EBWebView')
            'WebView2Legacy'     = (Join-Path $packageRoot 'LocalState\WebView2')
            'InternetCache'      = (Join-Path $packageRoot 'AC\INetCache')
        }

        foreach ($entry in $candidatePaths.GetEnumerator()) {
            if (Test-Path -LiteralPath $entry.Value) {
                $items += [pscustomobject]@{
                    PackageName = $package.Name
                    PackageFamilyName = $package.PackageFamilyName
                    Label = $entry.Key
                    Path = $entry.Value
                }
            }
        }
    }

    return $items
}

function Stop-CopilotProcesses {
    $packages = @(Get-CopilotAppPackages)
    $patterns = @('Copilot') + @($packages | ForEach-Object { $_.PackageFamilyName })

    Get-Process -Name 'Copilot' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($PSCmdlet.ShouldProcess("Copilot process $($_.Id)", 'Stop process')) {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            Write-Log "Stopped Copilot process ID $($_.Id)." 'SUCCESS'
        }
    }

    $webViewProcesses = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -ieq 'msedgewebview2.exe' -and $_.CommandLine
        }
    )

    foreach ($process in $webViewProcesses) {
        $belongsToCopilot = $false
        foreach ($pattern in $patterns) {
            if (-not [string]::IsNullOrWhiteSpace($pattern) -and
                $process.CommandLine -match [regex]::Escape($pattern)) {
                $belongsToCopilot = $true
                break
            }
        }

        if ($belongsToCopilot -and
            $PSCmdlet.ShouldProcess("Copilot WebView2 process $($process.ProcessId)", 'Stop process')) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Log "Stopped Copilot WebView2 process ID $($process.ProcessId)." 'SUCCESS'
        }
    }
}

function Move-ItemToBackup {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$PackageFamilyName
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $safePackage = $PackageFamilyName -replace '[^a-zA-Z0-9._-]', '_'
    $safeLabel = $Label -replace '[^a-zA-Z0-9._-]', '_'
    $packageBackup = Join-Path $BackupRoot $safePackage
    $destination = Join-Path $packageBackup $safeLabel

    if ($PSCmdlet.ShouldProcess($Path, "Move to backup: $destination")) {
        New-Item -ItemType Directory -Path $packageBackup -Force | Out-Null
        if (Test-Path -LiteralPath $destination) {
            $destination = "$destination-$Stamp"
        }
        Move-Item -LiteralPath $Path -Destination $destination -Force
        Write-Log "Backed up $Path to $destination." 'SUCCESS'
    }
}

function Get-WebView2Runtime {
    $roots = @(
        "$env:ProgramFiles\Microsoft\EdgeWebView\Application",
        "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application"
    )

    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }

        $runtime = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object {
                $exe = Join-Path $_.FullName 'msedgewebview2.exe'
                if (Test-Path -LiteralPath $exe) {
                    [pscustomobject]@{ Version = $_.Name; Path = $exe }
                }
            } |
            Select-Object -First 1

        if ($runtime) { return $runtime }
    }

    return $null
}

function Save-CopilotSnapshot {
    param([Parameter(Mandatory)][string]$Stage)

    $detectedPackages = @(Get-DetectedCopilotPackages)
    $appPackages = @(Get-CopilotAppPackages)
    $cacheItems = @(Get-CopilotCacheItems)
    $webView = Get-WebView2Runtime

    $endpoints = foreach ($target in @('copilot.microsoft.com','login.microsoftonline.com','www.office.com')) {
        $dns = $false
        $https = $false
        try { [void][System.Net.Dns]::GetHostAddresses($target); $dns = $true } catch {}
        try { $https = Test-NetConnection -ComputerName $target -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue } catch {}
        [pscustomobject]@{ Target = $target; DNS = $dns; HTTPS443 = $https }
    }

    $snapshot = [ordered]@{
        Stage = $Stage
        Generated = (Get-Date).ToString('o')
        ScriptVersion = $ScriptVersion
        Action = $Action
        Computer = $env:COMPUTERNAME
        User = "$env:USERDOMAIN\$env:USERNAME"
        DetectedPackages = @(
            $detectedPackages | Select-Object Name, PackageFullName, PackageFamilyName, Version, Status, InstallLocation
        )
        RepairableAppPackages = @(
            $appPackages | Select-Object Name, PackageFullName, PackageFamilyName, Version, Status, InstallLocation
        )
        CacheItems = @(
            $cacheItems | Select-Object PackageName, PackageFamilyName, Label, Path
        )
        CopilotProcesses = @(
            Get-Process -Name 'Copilot' -ErrorAction SilentlyContinue |
                Select-Object Id, ProcessName, Path, StartTime
        )
        WebView2Runtime = $webView
        StartMenuEntries = @(
            Get-StartApps -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Copilot' }
        )
        Endpoints = $endpoints
    }

    $snapshotPath = Join-Path $OutputPath "Copilot_${Stage}_$Stamp.json"
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $snapshotPath -Encoding UTF8
    Write-Log "Saved $Stage snapshot: $snapshotPath" 'SUCCESS'
}

function Invoke-RestartCopilot {
    Stop-CopilotProcesses

    $entry = Get-StartApps -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Copilot' } |
        Select-Object -First 1

    if ($entry) {
        if ($PSCmdlet.ShouldProcess($entry.Name, 'Start Copilot application')) {
            Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($entry.AppID)"
            Write-Log "Started Copilot using AppID $($entry.AppID)." 'SUCCESS'
        }
        return
    }

    if ($PSCmdlet.ShouldProcess('https://copilot.microsoft.com', 'Open Copilot in the default browser')) {
        Start-Process 'https://copilot.microsoft.com'
        Write-Log 'No Copilot Start menu entry was found; opened Copilot in the default browser.' 'WARN'
    }
}

function Invoke-ResetCopilotCache {
    $items = @(Get-CopilotCacheItems)
    if ($items.Count -eq 0) {
        Write-Log 'No recognised Copilot application cache folders were found.' 'WARN'
        return
    }

    Stop-CopilotProcesses

    foreach ($item in $items) {
        Move-ItemToBackup -Path $item.Path -Label $item.Label -PackageFamilyName $item.PackageFamilyName
    }

    Write-Log 'Copilot cache reset completed. Required cache folders will be recreated.' 'SUCCESS'
}

function Invoke-ReregisterCopilotPackage {
    $packages = @(Get-CopilotAppPackages)
    if ($packages.Count -eq 0) {
        throw 'No repairable Copilot application package was found. Only provider/runtime packages may be installed.'
    }

    Stop-CopilotProcesses

    foreach ($package in $packages) {
        $manifest = Join-Path $package.InstallLocation 'AppxManifest.xml'
        if (-not (Test-Path -LiteralPath $manifest)) {
            Write-Log "Manifest not found for $($package.Name): $manifest" 'WARN'
            continue
        }

        if ($PSCmdlet.ShouldProcess($package.PackageFullName, 'Re-register application package')) {
            Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
            Write-Log "Re-registered Copilot package $($package.Name)." 'SUCCESS'
        }
    }
}

function Invoke-ResetCopilotPackage {
    $packages = @(Get-CopilotAppPackages)
    if ($packages.Count -eq 0) {
        throw 'No repairable Copilot application package was found. Only provider/runtime packages may be installed.'
    }

    Stop-CopilotProcesses

    if (-not (Get-Command Reset-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-Log 'Reset-AppxPackage is unavailable. Falling back to package re-registration.' 'WARN'
        Invoke-ReregisterCopilotPackage
        return
    }

    foreach ($package in $packages) {
        if ($PSCmdlet.ShouldProcess($package.PackageFullName, 'Reset package and local application data')) {
            $package | Reset-AppxPackage -ErrorAction Stop
            Write-Log "Reset Copilot package $($package.Name)." 'SUCCESS'
        }
    }
}

function Invoke-FlushDns {
    if ($PSCmdlet.ShouldProcess('Windows DNS client cache', 'Clear')) {
        if (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) {
            Clear-DnsClientCache
        } else {
            & ipconfig.exe /flushdns | Out-Null
        }
        Write-Log 'DNS resolver cache cleared.' 'SUCCESS'
    }
}

function Invoke-SafeRepairSet {
    Invoke-ResetCopilotCache
    Invoke-FlushDns
    Invoke-ReregisterCopilotPackage
    Invoke-RestartCopilot
}

Write-Log "Copilot Repair Toolkit $ScriptVersion started. Action=$Action"
Save-CopilotSnapshot -Stage 'Before'

$exitCode = 0
try {
    switch ($Action) {
        'Diagnose'             { Write-Log 'Read-only diagnosis completed.' 'SUCCESS' }
        'RepairAllSafe'        { Invoke-SafeRepairSet }
        'RestartApp'           { Invoke-RestartCopilot }
        'ResetCache'           { Invoke-ResetCopilotCache }
        'ResetAppPackage'      { Invoke-ResetCopilotPackage }
        'ReregisterAppPackage' { Invoke-ReregisterCopilotPackage }
        'FlushDns'             { Invoke-FlushDns }
    }
} catch {
    $exitCode = 5
    Write-Log $_.Exception.Message 'ERROR'
} finally {
    try {
        Save-CopilotSnapshot -Stage 'After'
    } catch {
        Write-Log "Final snapshot failed: $($_.Exception.Message)" 'WARN'
    }

    if ($exitCode -eq 0) {
        Write-Log "Completed. Logs and backups: $OutputPath" 'SUCCESS'
    } else {
        Write-Log "Completed with errors. Logs and backups: $OutputPath" 'ERROR'
    }
}

exit $exitCode
