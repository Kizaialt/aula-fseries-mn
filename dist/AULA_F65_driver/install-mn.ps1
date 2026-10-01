# AULA F-цувралын драйверт монгол хэл нэмэх
#
# Энэ скрипт драйверын файлыг ӨӨРЧЛӨХГҮЙ. Зөвхөн:
#   1. app\Text\mn\text.xml  файлыг хуулна
#   2. app\Cfg.ini дотор  Lang<N>=Монгол,mn  мөр нэмнэ
# Драйверын OemDrv.exe хэвээрээ, AULA-гийн жинхэнэ файл байна.
#
# Ажиллуулах:  install-mn.bat  дээр хоёр товшино уу (администратор эрх асууна)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

#region peaklab-common  (identical in every install script; tools/qa checks it)
# Any error stops here with the message on screen. Without this the window
# closes the instant the script fails and the customer never sees why.
trap {
    Write-Host ''
    Write-Host ('  АЛДАА: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('  ' + ($_.InvocationInfo.PositionMessage -replace '\s+', ' ')) -ForegroundColor DarkGray
    Write-Host ''
    Read-Host '  Хаахын тулд Enter дарна уу' | Out-Null
    exit 1
}

# Where is the driver installed? Customers install to D: as often as C:, so
# ask Windows first (installers record InstallLocation and their uninstaller),
# then fall back to every fixed drive. $ExeName may contain a wildcard.
function Find-Driver([string]$ExeName) {
    $dirs = @()
    $keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($e in @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue)) {
        if ($e.InstallLocation) { $dirs += [string]$e.InstallLocation }
        if ($e.UninstallString -and ($e.UninstallString -match '^\s*"?([^"]+?\.exe)')) {
            $dirs += (Split-Path -Parent $Matches[1])
        }
    }
    $hits = @()
    foreach ($d in ($dirs | Where-Object { $_ } | Sort-Object -Unique)) {
        # Some installers (Google Drive) record InstallLocation as the path of
        # an .exe, and Get-ChildItem given a FILE ignores -Filter and returns it.
        if (Test-Path -LiteralPath $d -PathType Leaf) { $d = Split-Path -Parent $d }
        if (Test-Path -LiteralPath $d -PathType Container) {
            $hits += @(Get-ChildItem -LiteralPath $d -Filter $ExeName -File -ErrorAction SilentlyContinue |
                       ForEach-Object { $_.FullName })
        }
    }
    if ($hits.Count -eq 0) {
        $bases = @("$env:LOCALAPPDATA\Programs")
        foreach ($drv in [IO.DriveInfo]::GetDrives()) {
            if ($drv.DriveType -eq 'Fixed' -and $drv.IsReady) {
                foreach ($sub in 'Program Files', 'Program Files (x86)', 'Programs') {
                    $bases += (Join-Path $drv.RootDirectory.FullName $sub)
                }
            }
        }
        foreach ($b in ($bases | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
            $hits += @(Get-ChildItem -LiteralPath $b -Filter $ExeName -Recurse -File -Depth 4 -ErrorAction SilentlyContinue |
                       ForEach-Object { $_.FullName })
        }
    }
    return @($hits | Sort-Object -Unique)
}

# Last resort: let the customer point at the folder themselves.
function Ask-DriverFolder([string]$ExeName) {
    Write-Host ''
    Write-Host '  Драйверыг автоматаар олсонгүй.' -ForegroundColor Yellow
    Write-Host "  $ExeName байгаа хавтсыг энд бичээд Enter дарна уу." -ForegroundColor Gray
    Write-Host '  Жишээ:  D:\Program Files (x86)\AULA\F65' -ForegroundColor DarkGray
    for ($i = 0; $i -lt 3; $i++) {
        $p = ([string](Read-Host '  Зам')).Trim().Trim('"')
        if (-not $p) { return @() }
        if (Test-Path -LiteralPath $p -PathType Container) {
            $f = Get-ChildItem -LiteralPath $p -Filter $ExeName -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { return @($f.FullName) }
        }
        Write-Host "  $ExeName энэ хавтсанд алга. Дахин оролдоно уу." -ForegroundColor Red
    }
    return @()
}
#endregion peaklab-common

function Say($msg, $color = 'White') { Write-Host $msg -ForegroundColor $color }

Say ''
Say '  AULA F-цуврал — Монгол хэлний багц' Cyan
Say '  ==================================' Cyan
Say ''

# --- админ эрхтэй эсэхийг шалгах -------------------------------------------
$admin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
    Say '  Администратор эрх шаардлагатай. Дахин ажиллуулж байна...' Yellow
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    )
    exit
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcXml = Join-Path $here 'text.xml'
if (-not (Test-Path $srcXml)) { Say "  АЛДАА: text.xml олдсонгүй ($here)" Red; Read-Host '  Enter'; exit 1 }

# --- суулгасан драйверыг олох ----------------------------------------------
Say '  Драйверыг хайж байна...' Gray
$exes = @(Find-Driver 'OemDrv.exe')
if ($exes.Count -eq 0) { $exes = @(Ask-DriverFolder 'OemDrv.exe') }
if ($exes.Count -eq 0) {
    Say ''
    Say '  Драйвер олдсонгүй.' Red
    Say '  Эхлээд AULA-гийн жинхэнэ драйверыг суулгаад дараа нь энэ багцыг ажиллуулна уу.' Yellow
    Read-Host '  Enter'; exit 1
}
$found = @($exes | ForEach-Object { Get-Item -LiteralPath $_ })

$patched = 0
foreach ($drv in $found) {
    $app = Split-Path -Parent $drv.FullName
    $cfg = Join-Path $app 'Cfg.ini'
    if (-not (Test-Path $cfg)) { continue }

    $title = ''
    try {
        $cfgText = [IO.File]::ReadAllText($cfg, [Text.Encoding]::Unicode)
        if ($cfgText -match '(?m)^Title=(.*)$') { $title = $Matches[1].Trim() }
    } catch { continue }

    Say ''
    Say "  Олдлоо: $title" Green
    Say "          $app" Gray

    # 1) орчуулгын файлыг хуулах
    $dstDir = Join-Path $app 'Text\mn'
    New-Item -ItemType Directory -Force $dstDir | Out-Null
    Copy-Item $srcXml (Join-Path $dstDir 'text.xml') -Force
    Say '   + Text\mn\text.xml' Gray

    # 2) Cfg.ini дотор хэлний мөр нэмэх (аль хэдийн байвал алгасна)
    if ($cfgText -match '(?m)^Lang\d+=.*,mn\s*$') {
        Say '   = Cfg.ini дотор монгол хэл аль хэдийн бүртгэлтэй' Gray
    } else {
        Copy-Item $cfg "$cfg.bak" -Force
        $nums = [regex]::Matches($cfgText, '(?m)^Lang(\d+)=') | ForEach-Object { [int]$_.Groups[1].Value }
        $next = if ($nums) { ($nums | Measure-Object -Maximum).Maximum + 1 } else { 1 }
        $lines = $cfgText -replace "`r`n", "`n" -split "`n"
        $lastLang = ($lines | Select-String -Pattern '^Lang\d+=' | Select-Object -Last 1).LineNumber
        $entry = "Lang$next=" + [char]0x041C + [char]0x043E + [char]0x043D + [char]0x0433 + [char]0x043E + [char]0x043B + ',mn'
        $new = @()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $new += $lines[$i]
            if ($i -eq ($lastLang - 1)) { $new += $entry }
        }
        # No extra "`r`n": see install-auto.ps1 - joining already reproduces the file's own ending.
        [IO.File]::WriteAllText($cfg, ($new -join "`r`n"), [Text.Encoding]::Unicode)
        Say "   + Cfg.ini: $entry  (нөөц: Cfg.ini.bak)" Gray
    }
    $patched++
}

Say ''
if ($patched -gt 0) {
    Say "  Бэлэн боллоо ($patched драйвер)." Green
    Say '  Драйверыг нээгээд Config -> Language хэсгээс "Монгол" сонгоно уу.' White
} else {
    Say '  Юу ч өөрчлөгдсөнгүй.' Yellow
}
Say ''
Read-Host '  Хаахын тулд Enter дарна уу' | Out-Null
