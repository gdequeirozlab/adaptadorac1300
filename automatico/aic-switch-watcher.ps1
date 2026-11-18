# aic-switch-watcher.ps1
# Roda em segundo plano (tarefa agendada, conta SYSTEM).
# A cada 5 segundos procura o adaptador Wi-Fi 6 + BT (chip AIC 88M80) no modo "USB driver"
# (ID USB 1111:1111). Quando acha, confere que ele responde "88M80" ao comando F3
# e entao manda o F2, que o coloca no modo Wi-Fi + Bluetooth (A69C:8D80 -> 8D81).

$ErrorActionPreference = 'Continue'
$pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $pasta 'log.txt'

function Log($msg) {
    $linha = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg
    try {
        if ((Test-Path $log) -and (Get-Item $log).Length -gt 512KB) { Move-Item $log "$log.old" -Force }
        Add-Content -Path $log -Value $linha
    } catch {}
}

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

    // Envia CDB FD 00..00 <last>. Retorna os bytes lidos (dataIn > 0), vazio se nao leu, ou null em erro.
    public static byte[] Send(string drive, byte last, int dataIn, out string erro) {
        erro = null;
        var h = CreateFile(@"\\.\" + drive + ":", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid) { erro = "abrir unidade: erro " + Marshal.GetLastWin32Error(); return null; }
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
            if (!DeviceIoControl(h, 0x4D004, ref s, size, ref s, size, out ret, IntPtr.Zero)) {
                int e = Marshal.GetLastWin32Error();
                // ao trocar de modo o dispositivo some no meio do comando: conta como sucesso
                if (e == 55 || e == 121 || e == 1167 || e == 0x48F) return new byte[0];
                erro = "DeviceIoControl: erro " + e; return null;
            }
            var r = new byte[dataIn];
            Array.Copy(s.Data, r, dataIn);
            return r;
        }
    }
}
"@

Log "Vigia iniciado."
$tentativas = @{}

while ($true) {
    try {
        $emModoDisco = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -like 'USB\VID_1111&PID_1111*' }

        if ($emModoDisco) {
            $unidades = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveType -in 2,5 } |
                Where-Object {
                    # so a unidade virtual do adaptador: tem o instalador do driver Wi-Fi 6 na raiz
                    Get-ChildItem ($_.DeviceID + '\') -Filter '*install*.exe' -ErrorAction SilentlyContinue
                }
            foreach ($u in $unidades) {
                $letra = $u.DeviceID.TrimEnd(':')
                # evita insistir sem parar na mesma unidade se ela nao responder
                $chave = "$letra|$($u.VolumeSerialNumber)"
                if ($tentativas[$chave] -ge 3) { continue }

                $erro = $null
                $resp = [AicSwitch]::Send($letra, 0xF3, 5, [ref]$erro)
                if ($resp -eq $null -or $resp.Length -lt 5) { continue }
                $texto = [Text.Encoding]::ASCII.GetString($resp)
                if ($texto -ne '88M80') { $tentativas[$chave] = 99; continue }   # nao e o adaptador: nunca mais mexe nela

                Log "Adaptador encontrado em $letra`: (resposta F3 = $texto). Enviando F2..."
                Start-Sleep -Milliseconds 500
                $r2 = [AicSwitch]::Send($letra, 0xF2, 0, [ref]$erro)
                if ($r2 -eq $null) { Log "F2 falhou: $erro" } else { Log "F2 enviado. Aguardando Wi-Fi + Bluetooth (8D80 -> 8D81)." }
                $tentativas[$chave] = [int]$tentativas[$chave] + 1
                Start-Sleep -Seconds 10
                pnputil /scan-devices | Out-Null
            }
        } else {
            if ($tentativas.Count) { $tentativas = @{} }
        }
    } catch {
        Log "Erro: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 5
}
