# desinstalar-automatico.ps1
# Remove a tarefa agendada e a pasta C:\ProgramData\AicWifiBT.

$nome = 'AIC WiFi6 BT - troca de modo'
if (Get-ScheduledTask -TaskName $nome -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $nome -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $nome -Confirm:$false
    Write-Host "Tarefa removida."
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*aic-switch-watcher.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Remove-Item (Join-Path $env:ProgramData 'AicWifiBT') -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Pasta C:\ProgramData\AicWifiBT removida."
Read-Host "Enter para sair"
