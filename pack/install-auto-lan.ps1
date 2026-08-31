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
$roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs") |
         Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$found = @()
foreach ($r in $roots) {
    $found += Get-ChildItem $r -Filter 'DeviceDriver.exe' -Recurse -File -Depth 4 -ErrorAction SilentlyContinue
}
$found = $found | Sort-Object FullName -Unique

if ($found.Count -eq 0) {
    Say ''; Say '  Драйвер олдсонгүй.' Red
    Say '  Суулгагчийг дуусгасан эсэхээ шалгаад дахин оролдоно уу.' Yellow
    Read-Host '  Enter'; exit 1
}

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
        [IO.File]::WriteAllText($cfg, $text, [Text.UTF8Encoding]::new($true))
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
