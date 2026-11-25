@echo off
chcp 65001 >nul
echo ============================================================
echo   BluePad - Windows 10/11 Tek Tikla Bluetooth HID Eslestirme
echo ============================================================
echo.
echo iPhone'da BluePad uygulamasini on planda (ekran acik) tutun.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bluepad_pair_windows.ps1" -ScanSeconds 20
echo.
pause
