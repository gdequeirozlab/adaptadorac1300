@echo off
:: Abre o ativar-wifi6-bt.ps1 (mesma pasta) como administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ativar-wifi6-bt.ps1"
