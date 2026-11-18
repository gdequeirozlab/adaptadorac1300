# ativar-wifi6-bt.ps1
# Adaptador Wi-Fi 6 + BT (chip AIC8800D80, modo disco 1111:1111).
# 1) Instala o carregador de firmware (aicloadfw 9.49, da propria pix-link) e o driver Wi-Fi (aicusbwifi, da pix-link).
# 2) Manda os comandos SCSI do fabricante FD..F3 (consulta) e depois FD..F2 (troca de modo).
#    Com os dois, o adaptador 1111:1111 (88M80) vira A69C:8D80 -> o aicloadfw carrega o firmware -> ele volta como
#    A69C:8D81 (Wi-Fi + Bluetooth). O Bluetooth usa o driver generico do Windows.
# Rode como administrador (use o .bat).

param([string]$Letra)
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Abra como administrador (use o ativar-wifi6-bt.bat)." -ForegroundColor Red
    Read-Host "Enter para sair"; exit 1
}

# Os drivers (de terceiros) nao vem neste repositorio: veja o README para extrai-los do instalador da pix-link.
$faltando = @("$base\drivers\loadfw\aicloadfw.Inf", "$base\drivers\wifi\aicusbwifi.Inf") | Where-Object { -not (Test-Path $_) }
if ($faltando) {
    Write-Host "Faltam os arquivos de driver:" -ForegroundColor Red
    $faltando | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host "Siga a secao 'Passo 1: pegar os drivers' do README." -ForegroundColor Yellow
    Read-Host "Enter para sair"; exit 1
}

# O servico da pix-link (se estiver instalado) manda outro comando que deixa o adaptador so com Wi-Fi.
$svc = Get-Service -Name AicWifiService -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "Desativando o servico AicWifiService da pix-link (ele liga o modo so Wi-Fi)..."
    Stop-Service AicWifiService -Force -ErrorAction SilentlyContinue
    Set-Service AicWifiService -StartupType Disabled
}

Write-Host "Removendo carregadores de firmware antigos (BrosTrend etc.)..."
$blocos = (pnputil /enum-drivers | Out-String) -split "(?:\r?\n){2,}"
foreach ($bloco in $blocos) {
    if ($bloco -match 'aicloadfw' -and $bloco -match '(oem\d+\.inf)') {
        pnputil /delete-driver $Matches[1] /uninstall /force | Out-Host
    }
}
Write-Host "Instalando drivers (carregador de firmware da pix-link + Wi-Fi)..."
pnputil /add-driver "$base\drivers\loadfw\aicloadfw.Inf" /install | Out-Host
pnputil /add-driver "$base\drivers\wifi\aicusbwifi.Inf" /install | Out-Host

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class AicSwitch {
    [StructLayout(LayoutKind.Sequential)]
    public struct SCSI_PASS_THROUGH {
        public ushort Length;
        public byte ScsiStatus, PathId, TargetId, Lun, CdbLength, SenseInfoLength, DataIn;
        public uint DataTransferLength;
        public uint TimeOutValue;
        public UIntPtr DataBufferOffset;
        public uint SenseInfoOffset;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)] public byte[] Cdb;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct SPT_BUF {
        public SCSI_PASS_THROUGH Spt;
        public uint Filler;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public byte[] Sense;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)] public byte[] Data;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle h, uint code, ref SPT_BUF inBuf, int inSize,
        ref SPT_BUF outBuf, int outSize, out int ret, IntPtr ov);

    // Envia CDB de 16 bytes FD 00 .. 00 <ultimo>. dataIn > 0 = le esse numero de bytes do dispositivo.
    public static string Send(string drive, byte last, int dataIn) {
        var h = CreateFile(@"\\.\" + drive + ":", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid) return "Falha ao abrir a unidade (erro " + Marshal.GetLastWin32Error() + ")";
        using (h) {
            var s = new SPT_BUF();
            s.Sense = new byte[32];
            s.Data = new byte[64];
            s.Spt.Cdb = new byte[16];
            s.Spt.Cdb[0] = 0xFD;
            s.Spt.Cdb[15] = last;
            s.Spt.Length = (ushort)Marshal.SizeOf(typeof(SCSI_PASS_THROUGH));
            s.Spt.CdbLength = 16;
            s.Spt.SenseInfoLength = 24;
            s.Spt.DataIn = (byte)(dataIn > 0 ? 1 : 0);
            s.Spt.DataTransferLength = (uint)dataIn;
            s.Spt.DataBufferOffset = (UIntPtr)(uint)Marshal.OffsetOf(typeof(SPT_BUF), "Data");
            s.Spt.TimeOutValue = 20;
            s.Spt.SenseInfoOffset = (uint)Marshal.OffsetOf(typeof(SPT_BUF), "Sense");
            int size = Marshal.SizeOf(typeof(SPT_BUF));
            int ret;
            bool ok = DeviceIoControl(h, 0x4D004, ref s, size, ref s, size, out ret, IntPtr.Zero);
            if (!ok) {
                int e = Marshal.GetLastWin32Error();
                if (e == 55 || e == 121 || e == 1167 || e == 0x48F) return "OK (o dispositivo se desconectou para trocar de modo)";
                return "Erro do Windows " + e;
            }
            string resp = "";
            if (dataIn > 0) resp = " resposta: " + BitConverter.ToString(s.Data, 0, dataIn);
            return "OK (status SCSI " + s.Spt.ScsiStatus + ")" + resp;
        }
    }
}
"@

if (-not $Letra) {
    $candidatas = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2,5 }
    $achada = $candidatas | Where-Object {
        Get-ChildItem ($_.DeviceID + '\') -Filter '*install*.exe' -ErrorAction SilentlyContinue
    } | Select-Object -First 1
    if ($achada) {
        $Letra = $achada.DeviceID.TrimEnd(':')
        Write-Host "Unidade do adaptador encontrada: $Letra`: ($($achada.VolumeName))"
    } else {
        Write-Host ""
        Write-Host "Nao achei a unidade 'USB driver'. Se o adaptador ja esta como Wi-Fi (8D83)," -ForegroundColor Yellow
        Write-Host "tire ele da USB, espere 5 s, plugue de novo e rode este script outra vez." -ForegroundColor Yellow
        Write-Host "Unidades removiveis / CD encontradas:"
        $candidatas | ForEach-Object { Write-Host "  $($_.DeviceID)  $($_.VolumeName)" }
        $Letra = (Read-Host "Digite a letra da unidade 'USB driver' (ou Enter para sair)").Trim().TrimEnd(':')
        if (-not $Letra) { exit 0 }
    }
}

Write-Host "Enviando comando F3 (consulta) para $Letra`: ..."
Write-Host ([AicSwitch]::Send($Letra, 0xF3, 5))
Start-Sleep -Milliseconds 500
Write-Host "Enviando comando F2 (troca de modo) para $Letra`: ..."
Write-Host ([AicSwitch]::Send($Letra, 0xF2, 0))

Write-Host "Aguardando o adaptador carregar o firmware..."
for ($i = 0; $i -lt 6; $i++) {
    Start-Sleep -Seconds 3
    pnputil /scan-devices | Out-Null
}

Write-Host ""
Write-Host "Dispositivos AIC presentes agora:" -ForegroundColor Cyan
Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_(A69C|1111)' } |
    Format-Table Status, Class, FriendlyName, InstanceId -AutoSize
Write-Host "Bluetooth:" -ForegroundColor Cyan
Get-PnpDevice -PresentOnly -Class Bluetooth -ErrorAction SilentlyContinue |
    Format-Table Status, FriendlyName, InstanceId -AutoSize

Read-Host "Enter para sair"
