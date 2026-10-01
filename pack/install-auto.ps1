# AULA драйверыг монгол хэлтэйгээр суулгах — нэг товшилтоор
#
#   1. AULA-гийн ЖИНХЭНЭ драйверыг суулгана (өөрчлөөгүй, эх файл)
#   2. Монгол хэлний файлыг нэмнэ
#   3. Драйверыг монгол хэл дээр НЭЭГДЭХЭЭР тохируулна
#
# Драйверын программ (OemDrv.exe) огт өөрчлөгдөхгүй.

[CmdletBinding()]
param(
    [string]$UserLocalAppData,   # elevation-ийн дараа хэрэглэгчийн замыг дамжуулна
    [switch]$Applied             # дотоод: суулгагчийг дахин ажиллуулахгүй
)

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

function Say($m, $c = 'White') { Write-Host $m -ForegroundColor $c }
function Head($m) { Say ''; Say "  $m" Cyan; Say ('  ' + ('-' * $m.Length)) DarkGray }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------- step 1
if (-not $Applied) {
    Head 'AULA — Монгол хэлтэй драйвер суулгах'
    Say ''
    Say '  Энэ нь дараах 3 зүйлийг хийнэ:' Gray
    Say '    1. AULA-гийн жинхэнэ драйверыг суулгана' Gray
    Say '    2. Монгол хэлний файлыг нэмнэ' Gray
    Say '    3. Драйверыг монголоор нээгдэхээр тохируулна' Gray
    Say ''

    # Already installed? Then do not make the customer click through AULA's
    # wizard a second time just to add a language.
    $runInstaller = $true
    $already = @(Find-Driver 'OemDrv.exe')
    if ($already.Count -gt 0) {
        Say '  AULA драйвер аль хэдийн суусан байна:' Yellow
        Say ('    ' + (Split-Path -Parent $already[0])) DarkGray
        Say ''
        $ans = ([string](Read-Host '  Зөвхөн монгол хэлийг нэмэх үү?   Enter = Тийм,   2 = драйверыг дахин суулгах')).Trim()
        if ($ans -ne '2') { $runInstaller = $false }
        Say ''
    }

    if ($runInstaller) {
        $setup = Get-ChildItem (Join-Path $here 'driver') -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if (-not $setup) { Say '  АЛДАА: driver хавтас дотор суулгагч алга.' Red; Read-Host '  Enter'; exit 1 }

        Say "  AULA-гийн суулгагчийг нээж байна: $($setup.Name)" White
        Say '  Гарч ирэх цонхон дээр Next / Install дарж дуусгана уу.' Yellow
        Say ''
        try {
            Start-Process -FilePath $setup.FullName -Wait
        } catch {
            Say "  Суулгагчийг ажиллуулж чадсангүй: $($_.Exception.Message)" Red
            Read-Host '  Enter'; exit 1
        }
        Say '  Суулгагч дууслаа.' Green
    }
}

# ---------------------------------------------------------------- elevate
$admin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
    Say ''
    Say '  Монгол хэлний файлыг нэмэхийн тулд администратор эрх хэрэгтэй...' Yellow
    # LOCALAPPDATA-г дамжуулна: өөр админ хэрэглэгчээр өргөвөл зам өөрчлөгдөнө
    Start-Process powershell -Verb RunAs -Wait -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
        '-Applied', '-UserLocalAppData', "`"$env:LOCALAPPDATA`""
    )
    exit
}

if (-not $UserLocalAppData) { $UserLocalAppData = $env:LOCALAPPDATA }

# ---------------------------------------------------------------- step 2+3
Head 'Монгол хэл нэмж байна'

$srcXml = Get-ChildItem (Join-Path $here 'lang') -Filter 'text.xml' -File -Recurse -ErrorAction SilentlyContinue |
          Select-Object -First 1
if (-not $srcXml) { Say '  АЛДАА: lang\text.xml алга.' Red; Read-Host '  Enter'; exit 1 }

Say '  Суулгасан драйверыг хайж байна...' Gray
$exes = @(Find-Driver 'OemDrv.exe')
if ($exes.Count -eq 0) { $exes = @(Ask-DriverFolder 'OemDrv.exe') }
if ($exes.Count -eq 0) {
    Say ''
    Say '  Драйвер олдсонгүй.' Red
    Say '  Суулгагчийг дуусгасан эсэхээ шалгаад дахин оролдоно уу.' Yellow
    Read-Host '  Enter'; exit 1
}
$found = @($exes | ForEach-Object { Get-Item -LiteralPath $_ })

$done = 0
foreach ($drv in $found) {
    $app = Split-Path -Parent $drv.FullName
    $cfg = Join-Path $app 'Cfg.ini'
    if (-not (Test-Path $cfg)) { continue }

    $cfgText = [IO.File]::ReadAllText($cfg, [Text.Encoding]::Unicode)
    $title = if ($cfgText -match '(?m)^Title=(.*)$') { $Matches[1].Trim() } else { 'AULA' }
    $appdir = if ($cfgText -match '(?m)^Appdir=(.*)$') { $Matches[1].Trim() } else { '' }

    Say ''
    Say "  $title" Green
    Say "  $app" DarkGray

    # --- хэлний файл ---
    $dst = Join-Path $app 'Text\mn'
    New-Item -ItemType Directory -Force $dst | Out-Null
    Copy-Item $srcXml.FullName (Join-Path $dst 'text.xml') -Force
    Say '   + Text\mn\text.xml' Gray

    # --- Cfg.ini дотор хэлээ бүртгэх ---
    if ($cfgText -match '(?m)^Lang([0-9]+)=.*,mn\s*$') {
        $index = [int]$Matches[1]
        Say "   = Cfg.ini дотор аль хэдийн бүртгэлтэй (Lang$index)" Gray
    } else {
        Copy-Item $cfg "$cfg.bak" -Force
        $used = [regex]::Matches($cfgText, '(?m)^Lang([0-9]+)=') | ForEach-Object { [int]$_.Groups[1].Value }
        $index = if ($used) { ($used | Measure-Object -Maximum).Maximum + 1 } else { 1 }
        $entry = "Lang$index=" + [char]0x041C+[char]0x043E+[char]0x043D+[char]0x0433+[char]0x043E+[char]0x043B + ',mn'
        $lines = $cfgText -replace "`r`n", "`n" -split "`n"
        $last = ($lines | Select-String -Pattern '^Lang' | Select-Object -Last 1).LineNumber
        $new = @()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $new += $lines[$i]
            if ($i -eq ($last - 1)) { $new += $entry }
        }
        [IO.File]::WriteAllText($cfg, ($new -join "`r`n") + "`r`n", [Text.Encoding]::Unicode)
        Say "   + Cfg.ini: $entry" Gray
    }

    # --- монголоор нээгдэхээр тохируулах ---
    # Драйвер сонгосон хэлээ %LOCALAPPDATA%\<Appdir>\lang.ini дотор
    # 0-оос эхэлсэн дугаараар хадгалдаг. Lang3 -> LangIndex=2
    if ($appdir) {
        $langIni = Join-Path (Join-Path $UserLocalAppData $appdir) 'lang.ini'
        New-Item -ItemType Directory -Force (Split-Path $langIni) | Out-Null
        # the vendor's own lang.ini is "[OPT]CRLFLangIndex=0CRLF" (20 bytes); match it
        [IO.File]::WriteAllText($langIni, "[OPT]`r`nLangIndex=$($index - 1)`r`n", [Text.Encoding]::ASCII)
        Say "   + Монголоор нээгдэхээр тохируулав (LangIndex=$($index - 1))" Gray
    } else {
        Say '   ! Appdir олдсонгүй — драйвер дотроос хэлээ сонгоно уу' Yellow
    }

    $done++
}

Say ''
if ($done -gt 0) {
    Head 'Бэлэн боллоо'
    Say ''
    Say '  Драйверыг нээхэд шууд МОНГОЛ хэл дээр гарч ирнэ.' Green
    Say '  Хэлээ солихыг хүсвэл: Config -> Language' Gray
} else {
    Say '  Драйвер олдсон ч Cfg.ini алга байна.' Yellow
}
Say ''
Read-Host '  Хаахын тулд Enter дарна уу' | Out-Null
