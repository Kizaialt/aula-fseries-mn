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
$roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs", "$UserLocalAppData\Programs") |
         Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

$found = @()
foreach ($r in $roots) {
    $found += Get-ChildItem $r -Filter 'OemDrv.exe' -Recurse -File -Depth 4 -ErrorAction SilentlyContinue
}
$found = $found | Sort-Object FullName -Unique

if ($found.Count -eq 0) {
    Say ''
    Say '  Драйвер олдсонгүй.' Red
    Say '  Суулгагчийг дуусгасан эсэхээ шалгаад дахин оролдоно уу.' Yellow
    Read-Host '  Enter'; exit 1
}

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
        [IO.File]::WriteAllText($langIni, "[OPT]`r`nLangIndex=$($index - 1)", [Text.Encoding]::ASCII)
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
