@echo off
chcp 65001 >nul
title Peaklab - Монгол хэл суулгагч
cd /d "%~dp0"

rem Opened from INSIDE the zip? Windows then copies only this one file to a temp folder.
if not exist "install-auto.ps1" goto :notextracted

echo.
echo   Peaklab - Монгол хэл суулгагч
echo   ---------------------------------
echo   Суулгагч нээгдэж байна, түр хүлээнэ үү...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-auto.ps1"
if errorlevel 1 goto :failed
exit /b 0

:failed
echo.
echo   Суулгах явцад алдаа гарлаа.
echo   Дээр бичигдсэн мессежийг Peaklab-д илгээнэ үү.
echo.
pause
exit /b 1

:notextracted
echo.
echo   Суулгагч файл олдсонгүй: та zip файлаа задлаагүй байна.
echo.
echo   Ингэж хийнэ үү:
echo     1. zip файл дээр хулганы баруун товчийг дарна
echo     2. "Extract All..." (Бүгдийг задлах) гэж сонгоод "Extract" дарна
echo     3. Гарч ирсэн хавтас доторх "Install_Suulgah.bat" дээр дахин хоёр товшино
echo.
pause
exit /b 1
