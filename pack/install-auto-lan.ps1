# AULA драйверыг монгол хэлтэйгээр суулгах — нэг товшилтоор
# (DeviceDriver.exe хэрэглэдэг загварууд: F75 MAX, F98 Pro, F106 Pro, F108 Pro …)
#
#   1. AULA-гийн ЖИНХЭНЭ драйверыг суулгана (өөрчлөөгүй, эх файл)
#   2. language\1104.lan монгол файлыг нэмнэ
#   3. config.xml дотор монгол хэлийг бүртгэж, анхны хэл болгоно
#
# Драйверын программ (DeviceDriver.exe, mui.dll) огт өөрчлөгдөхгүй.

[CmdletBinding()]
param([switch]$Applied)

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
$LCID = '1104'

# ---------------------------------------------------------------- step 1
if (-not $Applied) {
    Head 'AULA — Монгол хэлтэй драйвер суулгах'
    Say ''
    Say '  1. AULA-гийн жинхэнэ драйверыг суулгана' Gray
    Say '  2. Монгол хэлний файлыг нэмнэ' Gray
    Say '  3. Драйверыг монголоор нээгдэхээр тохируулна' Gray
    Say ''

    # Already installed? Then do not make the customer click through AULA's
    # wizard a second time just to add a language.
    $runInstaller = $true
    $already = @(Find-Driver 'DeviceDriver.exe')
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

        Say "  Суулгагчийг нээж байна: $($setup.Name)" White
        Say '  Гарч ирэх цонхон дээр Next / Install дарж дуусгана уу.' Yellow
        Say ''
        try { Start-Process -FilePath $setup.FullName -Wait }
        catch { Say "  Суулгагчийг ажиллуулж чадсангүй: $($_.Exception.Message)" Red; Read-Host '  Enter'; exit 1 }
        Say '  Суулгагч дууслаа.' Green
    }
}

# ---------------------------------------------------------------- elevate
$admin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
    Say ''
    Say '  Администратор эрх хэрэгтэй...' Yellow
    Start-Process powershell -Verb RunAs -Wait -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Applied'
    )
    exit
}

# ---------------------------------------------------------------- step 2+3
Head 'Монгол хэл нэмж байна'

$srcLan = Get-ChildItem (Join-Path $here 'lang') -Filter "$LCID.lan" -File -Recurse -ErrorAction SilentlyContinue |
          Select-Object -First 1
if (-not $srcLan) { Say "  АЛДАА: lang\$LCID.lan алга." Red; Read-Host '  Enter'; exit 1 }

Say '  Суулгасан драйверыг хайж байна...' Gray
$exes = @(Find-Driver 'DeviceDriver.exe')
if ($exes.Count -eq 0) { $exes = @(Ask-DriverFolder 'DeviceDriver.exe') }
if ($exes.Count -eq 0) {
    Say ''; Say '  Драйвер олдсонгүй.' Red
    Say '  Суулгагчийг дуусгасан эсэхээ шалгаад дахин оролдоно уу.' Yellow
    Read-Host '  Enter'; exit 1
}
$found = @($exes | ForEach-Object { Get-Item -LiteralPath $_ })

$done = 0; $auto = 0
foreach ($drv in $found) {
    $app = Split-Path -Parent $drv.FullName
    $langDir = Join-Path $app 'language'
    $cfg = Join-Path $app 'config.xml'
    if (-not (Test-Path $langDir)) { continue }

    Say ''
    Say "  $app" Green
    $before = @(Get-ChildItem $langDir -Filter '*.lan' -File | ForEach-Object { $_.BaseName })
    Say ("   Одоогийн хэлүүд: " + ($before -join ', ')) DarkGray

    Copy-Item $srcLan.FullName (Join-Path $langDir "$LCID.lan") -Force
    Say "   + language\$LCID.lan" Gray
    $done++

    # config.xml-ийг ЗАСНА (солихгүй) — ингэснээр AULA драйвераа шинэчлэхэд
    # бидний хуучин хуулбар дарж бичихгүй
    if (Test-Path $cfg) {
        # Keep the vendor's encoding exactly: five of the six models ship config.xml
        # WITHOUT a BOM, and nothing says DeviceDriver.exe tolerates one.
        $cfgBytes = [IO.File]::ReadAllBytes($cfg)
        $hadBom = ($cfgBytes.Length -ge 3 -and $cfgBytes[0] -eq 0xEF -and $cfgBytes[1] -eq 0xBB -and $cfgBytes[2] -eq 0xBF)
        $text = [IO.File]::ReadAllText($cfg, [Text.UTF8Encoding]::new($false))
        if ($text -notmatch '<language\.info') {
            Say '   ! config.xml дотор language.info алга — хэлээ гараар сонгоно уу' Yellow
            continue
        }
        Copy-Item $cfg "$cfg.bak" -Force
        if ($text -notmatch ('value="' + $LCID + '"')) {
            $text = [regex]::Replace($text, '(<language\.info[^>]*>)', "`$1`r`n`t`t<lan value=`"$LCID`" />", 1)
        }
        if ($text -match 'default_lan="\d+"') {
            $text = [regex]::Replace($text, 'default_lan="\d+"', "default_lan=`"$LCID`"", 1)
        } else {
            $text = [regex]::Replace($text, '(<language\.info)', "`$1 default_lan=`"$LCID`"", 1)
        }
        [IO.File]::WriteAllText($cfg, $text, [Text.UTF8Encoding]::new($hadBom))
        Say '   + config.xml: монгол хэл бүртгэгдэж, анхны хэл боллоо' Gray
        $auto++
    } else {
        Say '   ! config.xml олдсонгүй — хэлээ драйвер дотроос сонгоно уу' Yellow
    }
}

Say ''
if ($done -gt 0) {
    Head 'Бэлэн боллоо'
    Say ''
    if ($auto -gt 0) {
        Say '  Драйверыг нээхэд шууд МОНГОЛ хэл дээр гарч ирнэ.' Green
    } else {
        Say '  Драйверыг нээгээд Settings -> Language -> Монгол сонгоно уу.' Yellow
    }
    Say '  Хэлээ солихыг хүсвэл: Settings -> Language' Gray
} else {
    Say '  Драйвер олдсон ч language хавтас алга байна.' Yellow
}
Say ''
Read-Host '  Хаахын тулд Enter дарна уу' | Out-Null
