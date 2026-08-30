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
$roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs") |
         Where-Object { $_ -and (Test-Path $_) }

$found = @()
foreach ($r in $roots) {
    $found += Get-ChildItem $r -Filter 'OemDrv.exe' -Recurse -File -Depth 4 -ErrorAction SilentlyContinue
}
$found = $found | Sort-Object FullName -Unique

if ($found.Count -eq 0) {
    Say ''
    Say '  Драйвер олдсонгүй.' Red
    Say '  Эхлээд AULA-гийн жинхэнэ драйверыг суулгаад дараа нь энэ багцыг ажиллуулна уу.' Yellow
    Say '  Эсвэл OemDrv.exe байгаа хавтсыг доор оруулна уу (хоосон орхивол гарна):' Gray
    $manual = Read-Host '  Зам'
    if (-not $manual -or -not (Test-Path (Join-Path $manual 'OemDrv.exe'))) { exit 1 }
    $found = @(Get-Item (Join-Path $manual 'OemDrv.exe'))
}

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
        [IO.File]::WriteAllText($cfg, ($new -join "`r`n") + "`r`n", [Text.Encoding]::Unicode)
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
