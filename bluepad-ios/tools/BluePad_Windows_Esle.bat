@echo off
chcp 65001 >nul
echo ============================================================
echo   BluePad - Windows 10/11 Tek Tikla Bluetooth HID Eslestirme
echo ============================================================
echo.
echo iPhone'da BluePad uygulamasini on planda (ekran acik) tutun.
echo.
if not exist "%~dp0bluepad_pair_windows.ps1" (
    echo HATA: Ayni klasorde bluepad_pair_windows.ps1 dosyasi bulunamadi!
    echo Lutfen GitHub'daki tools/bluepad_pair_windows.ps1 dosyasini da bu .bat ile ayni klasore koyun.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bluepad_pair_windows.ps1" -ScanSeconds 20
echo.
pause
