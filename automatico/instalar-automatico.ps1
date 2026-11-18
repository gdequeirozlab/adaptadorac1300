# instalar-automatico.ps1
# Copia o vigia para C:\ProgramData\AicWifiBT e cria a tarefa agendada
# "AIC WiFi6 BT - troca de modo", que roda como SYSTEM na inicializacao do Windows.

$ErrorActionPreference = 'Stop'
$origem = Split-Path -Parent $MyInvocation.MyCommand.Path
$destino = Join-Path $env:ProgramData 'AicWifiBT'
$nome = 'AIC WiFi6 BT - troca de modo'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Abra como administrador (use o instalar-automatico.bat)." -ForegroundColor Red
    Read-Host "Enter para sair"; exit 1
}

# O servico da pix-link manda o comando que deixa o adaptador so com Wi-Fi: mantem desativado.
if (Get-Service AicWifiService -ErrorAction SilentlyContinue) {
    Stop-Service AicWifiService -Force -ErrorAction SilentlyContinue
    Set-Service AicWifiService -StartupType Disabled
    Write-Host "Servico AicWifiService da pix-link desativado."
}

New-Item -ItemType Directory -Force $destino | Out-Null
Copy-Item (Join-Path $origem 'aic-switch-watcher.ps1') $destino -Force
Write-Host "Vigia copiado para $destino"

if (Get-ScheduledTask -TaskName $nome -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $nome -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $nome -Confirm:$false
}

$acao = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destino\aic-switch-watcher.ps1`""
$gatilho = New-ScheduledTaskTrigger -AtStartup
$conta = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$config = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $nome -Action $acao -Trigger $gatilho -Principal $conta -Settings $config `
    -Description 'Troca o adaptador Wi-Fi 6 + BT (AIC 88M80) do modo disco para Wi-Fi + Bluetooth.' | Out-Null
Start-ScheduledTask -TaskName $nome

Write-Host ""
Write-Host "Pronto! A tarefa '$nome' foi criada e ja esta rodando." -ForegroundColor Green
Write-Host "Ela liga o Wi-Fi + Bluetooth sozinha ao iniciar o Windows e sempre que o adaptador for plugado."
Write-Host "Registro do que ela faz: $destino\log.txt"
Read-Host "Enter para sair"
