# Adaptador USB Wi‑Fi 6 + Bluetooth (AIC 88M80 / `1111:1111`) no Windows

Scripts para fazer funcionar **Wi‑Fi e Bluetooth ao mesmo tempo** nos adaptadores USB "AX900 Wi‑Fi 6 + BT 5.3/5.4" genéricos que usam o chip **AIC8800D80 (88M80)**, vendidos com várias marcas (ex.: pix-link). Testado no Windows 11.

> Repositório feito por um usuário, sem ligação com a AIC, a pix-link ou outros fabricantes. Use por sua conta e risco.

## Este é o seu adaptador?

Ele é, se:

- ao plugar, aparece uma unidade **"USB driver"** (como um pendrive/CD) com um instalador `...Wifi6_install.exe`;
- no Gerenciador de Dispositivos, em **Controladores USB → Dispositivo de Armazenamento em Massa USB → Detalhes → IDs de hardware**, aparece **`USB\VID_1111&PID_1111`**;
- depois do instalador do fabricante, o Wi‑Fi funciona (aparece como `AIC8800D80 USB WiFi`, ID `A69C:8D83`), mas **o Bluetooth nunca aparece**.

## Por que o Bluetooth não aparece

O adaptador começa no modo "disco" (`1111:1111`) e precisa receber comandos SCSI do fabricante para virar placa de rede:

| Comandos enviados | Modo resultante | O que funciona |
|---|---|---|
| só `FD 00…00 F2` (é o que o serviço `AicWifiService` do fabricante faz) | `A69C:8D83` | só Wi‑Fi |
| `FD 00…00 F3` (consulta, responde `88M80`) **e depois** `FD 00…00 F2` | `A69C:8D80` → carregador de firmware → **`A69C:8D81`** | **Wi‑Fi + Bluetooth** |

No modo `8D80`, o driver **AIC Load Fw** (`aicloadfw`) envia o firmware e o adaptador volta como `8D81`, um dispositivo composto com:

- `MI_00` → **Generic Bluetooth Adapter** (driver do próprio Windows)
- `MI_02` → Wi‑Fi (`aicusbwifi`)

Importante: só funcionou com o carregador **`aicloadfw` 9.49.15.696, que vem no instalador da pix-link**. Outros carregadores testados (BrosTrend 12.60.30.224 e 5.33.14.703) deixaram o adaptador parado no `8D80`.

## Passo 1: pegar os drivers

Os drivers são de terceiros e **não estão neste repositório**. Você precisa extraí-los do instalador da pix-link:

1. Peça ao vendedor ou à pix-link o instalador `pix-link Wifi6_install.exe` **que contém o arquivo `aicloadfw`**. A versão que vem dentro da unidade "USB driver" de alguns adaptadores **não** tem o carregador, só o driver de Wi‑Fi.
2. Abra o `.exe` com o **[7-Zip](https://www.7-zip.org/)** (botão direito → 7-Zip → Abrir arquivo). É um instalador NSIS, e o 7-Zip abre normalmente.
3. Dentro da pasta `driversfiles\win10_x64\` dele:
   - copie `aicloadfw.Inf`, `aicloadfw.Sys` e `aicloadfw.cat` para **`ativar\drivers\loadfw\`**;
   - copie `aicusbwifi.Inf`, `aicusbwifi.Sys` e `aicusbwifi.cat` para **`ativar\drivers\wifi\`**.

## Passo 2: ativar (uma vez)

1. Se você já rodou o instalador do fabricante, desative o serviço dele, que força o modo só Wi‑Fi. No PowerShell como administrador:
   ```powershell
   Stop-Service AicWifiService -Force -ErrorAction SilentlyContinue
   Set-Service AicWifiService -StartupType Disabled -ErrorAction SilentlyContinue
   ```
2. Tire o adaptador da USB, espere 5 s e plugue de novo. A unidade **"USB driver"** tem que aparecer.
3. Rode **`ativar\ativar-wifi6-bt.bat`** e aceite o pedido de administrador. O script:
   - remove carregadores `aicloadfw` antigos e instala o da pasta `drivers\loadfw` e o driver de Wi‑Fi;
   - manda **F3** (que deve responder `38-38-4D-38-30` = "88M80") e depois **F2**;
   - mostra no final os dispositivos AIC e Bluetooth encontrados.

Deu certo se aparecerem `USB\VID_A69C&PID_8D81&MI_00` (Bluetooth) e `...&MI_02` (Wi‑Fi).

## Passo 3: deixar automático (recomendado)

O adaptador **volta para o modo "USB driver" sempre que o PC liga ou que ele é desplugado**. Para não precisar rodar o script toda vez:

- rode **`automatico\instalar-automatico.bat`** (como administrador).

Ele cria a tarefa agendada **"AIC WiFi6 BT - troca de modo"**, que roda como SYSTEM desde a inicialização do Windows. A cada 5 s, ela procura a unidade do adaptador, confirma que ela responde `88M80` (assim nunca mexe num pendrive comum) e manda o F2. O registro do que ela faz fica em `C:\ProgramData\AicWifiBT\log.txt`.

Para remover: **`automatico\desinstalar-automatico.bat`**.

## Como conferir

- **Configurações → Bluetooth e dispositivos**: aparece a chave do Bluetooth e o botão "Adicionar dispositivo".
- Ou no PowerShell:
  ```powershell
  Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_(A69C|1111)' -or $_.Class -eq 'Bluetooth' } |
    Format-Table Status, Class, FriendlyName, InstanceId -AutoSize
  ```

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| Fica em `8D83` (só Wi‑Fi) | O serviço `AicWifiService` mandou só o F2 antes do script. Desative o serviço (Passo 2.1) e replugue. |
| Fica parado em `8D80` ("AIC Load Fw Driver") | Carregador errado (versão diferente da 9.49.15.696). Rode o script de novo para trocar. |
| Script diz "Faltam os arquivos de driver" | Faltou o Passo 1. |
| Bluetooth aparece como "não funcionando" | O Windows só usa um adaptador Bluetooth por vez. Desative o Bluetooth interno do PC. |

## Créditos e referências

- A sequência F3 → F2 para os adaptadores `1111:1111` (88M80) foi documentada pela comunidade Linux, por exemplo em [shenmintao/aic8800d80](https://github.com/shenmintao/aic8800d80) e [LimitedIO/aicswitch](https://github.com/LimitedIO/aicswitch). Estes scripts fazem o mesmo no Windows via `IOCTL_SCSI_PASS_THROUGH`.

## Licença

Os scripts deste repositório estão sob a licença MIT (veja `LICENSE`). Os drivers citados pertencem aos respectivos fabricantes e não são distribuídos aqui.
