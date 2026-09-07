# Tasmota su RHC22 Badge

Questo documento descrive come far girare **Tasmota** (in alternativa al firmware ESP-IDF/LVGL
ufficiale di questo repo) sul badge RomHack Camp 2022, riusando tutto l'hardware presente sul
PCB. Le informazioni sui GPIO sono state estratte direttamente dal firmware ufficiale
(`main/badge/led.h`, `main/badge/led.c`, `main/badge/ui.h`, `sdkconfig.rhc22-badge`) e dal
`README.md`, non supposte.

> **Attenzione concettuale**: questa è una board custom da conferenza (MCU ESP32-C3 + display +
> LED + I2C expander), non un dispositivo "smart plug/switch" tipico di Tasmota. Flashare Tasmota
> **sostituisce interamente** il firmware ufficiale: radar BLE, gioco Snake, sync schedule via
> Wi-Fi, ecc. andranno persi. Tasmota può però pilotare nativamente display, bus I2C e pulsanti.

## Hardware e mappa GPIO (ESP32-C3)

| GPIO | Funzione sul PCB | Note |
|---|---|---|
| 0 | I2C **SCL** | bus verso i due AW9523B (driver dei 7 LED RGB + backlight) |
| 1 | I2C **SDA** | idem |
| 2 | SPI **MISO** display | ST7789 |
| 3 | Display **RESET** | ST7789 |
| 4 | Display **DC** (data/command) | ST7789 |
| 5 | non usato dal firmware | su questa revisione i 7 LED RGB **non** sono WS2812: sono pilotati via I2C dai due AW9523B (vedi sotto), quindi GPIO5 risulta libero |
| 6 | SPI **CLK** display | ST7789, SPI hardware (FSPI) |
| 7 | SPI **MOSI** display | ST7789 |
| 8 | **Button1** (pulsante DOWN) | libreria esp32-button, attivo basso, pull-up interno |
| 9 | **Button2** (pulsante UP) | ⚠️ pin di **strapping boot-mode** ESP32-C3 (già usato così anche dal firmware ufficiale) |
| 11–17 | non disponibili | riservati alla flash SPI integrata nel modulo |
| 18/19 | USB D-/D+ | USB-Serial/JTAG nativo, non riassegnabile a funzioni GPIO applicative |
| 20/21 | UART0 RX/TX | console seriale di default |

Display: **ST7789**, 2.4", 240×320 px (stessa risoluzione LVGL del badge WHY2025/EMF2026), bus
SPI **hardware** (HSPI/FSPI) — i pin usati coincidono esattamente con i pin FSPI di default
dell'ESP32-C3.

LED RGB frontali (7): pilotati **via I2C** da due chip **AW9523B** (indirizzi `0x5A` e `0x5B`,
confermati in `led.c`), non da una catena WS2812 come nella revisione WHY2025/EMF2026.

Alimentazione: 2× batterie AA, nessun circuito di carica/step-up dedicato menzionato — nulla da
configurare lato GPIO.

## Cosa è supportato **nativamente** da Tasmota

| Hardware | Componente Tasmota | Come si abilita |
|---|---|---|
| Display ST7789 240×320 | `DisplayModel 12` (driver `USE_DISPLAY_ST7789`, richiede `USE_SPI`) | via Template GPIO (SPI hardware + `ST7789_CS`/`ST7789_DC`/`Display Rst`) |
| Button1 / Button2 | `Button` | via Template GPIO `Button1`/`Button2` su GPIO8/GPIO9 |
| Bus I2C (rilevamento) | `I2CScan` | via Template GPIO `I2C_SCL1`/`I2C_SDA1` — mostra gli indirizzi 0x5A/0x5B (AW9523) ma senza driver dedicato non sono pilotabili |

## Cosa **non** è supportato nativamente

- **I 7 LED RGB frontali**: su questa board sono pilotati interamente via I2C dai due AW9523B, e
  Tasmota **non ha un driver WS2812 da assegnare** (non c'è catena WS2812 su questo hardware) né
  un driver nativo per l'AW9523B stesso → **nessun controllo LED nativo** su questa revisione del
  badge (a differenza del badge WHY2025/EMF2026, che ha in più una catena WS2812 dedicata).
- **AW9523B** (entrambi i chip, LED + backlight): nessun driver Tasmota di serie per questo
  chip (Tasmota supporta altri expander come PCA9535/MCP230xx/PCF8574, ma non l'AW9523).
- **Backlight del display**: pilotata dall'AW9523 via I2C, non da un GPIO diretto → il comando
  standard `Backlight`/dimmer di Tasmota **non si applica**.
- **Radar/BLE** (ricerca badge vicini), **gioco Snake**, **sync schedule via Wi-Fi**: logica
  applicativa del firmware originale, non replicabile con Tasmota stock.

## Cosa è raggiungibile tramite **scripting Berry**

Il bus I2C resta elettricamente disponibile (GPIO0/1) e Berry (il linguaggio di scripting
integrato in Tasmota) espone accesso raw I2C (`i2c.writebytes`/`i2c.readbytes` tramite la classe
`I2C`/`Wire` di Berry) e può registrare un driver custom con `tasmota.add_driver(...)`. Su questa
board lo scripting Berry è l'**unica via per pilotare i LED**, dato che sono su AW9523 e non su
WS2812. È tecnicamente possibile riprodurre in Berry la stessa logica di `led.c` del firmware
ufficiale (stessi indirizzi `0x5A`/`0x5B`, stessi registri: `0x20`–`0x23` per la backlight,
`0x20`–`0x2F` circa per i canali RGB dei singoli LED, con `LED mode` impostato via registro
`0x11`/`0x12`/`0x13`).

Scheletro minimo per accendere un LED RGB (**non testato**, solo punto di partenza — indirizzi e
registri ripresi da `led.c` di questo repo):

```berry
import i2c

class AW9523_RGB
  var wire, addr
  def init(bus, addr)
    self.wire = i2c.wire(bus)
    self.addr = addr
  end
  def set_channel(reg, value)  # value 0-255
    self.wire.write(self.addr, reg, value, 1)
  end
end

# Backlight (chip 0x5A, registri 0x20-0x23)
bl = AW9523_RGB(0, 0x5A)
bl.set_channel(0x20, 180)
bl.set_channel(0x21, 180)
bl.set_channel(0x22, 180)
bl.set_channel(0x23, 180)
```

Non è incluso di serie in Tasmota: va scritto e mantenuto come script `.be` caricato sul
filesystem del dispositivo, replicando la tabella `reg[]`/`addr[]` di `main/badge/led.c` per
mappare ciascuno dei 7 LED al chip e ai registri corretti.

## Configurazione Tasmota

Codici GPIO Tasmota usati (documentazione ufficiale): `I2C_SCL1=608`, `I2C_SDA1=640`,
`SPI_MISO1=672`, `SPI_MOSI1=704`, `SPI_CLK1=736`, `ST7789_CS=6112`, `ST7789_DC=6144`,
`Display_Rst=1024`, `Button1=32`, `Button2=33`. Per ESP32-C3 l'array `GPIO` del template ha 22
elementi, uno per ciascun GPIO0…GPIO21 in ordine diretto. GPIO5 resta a `0` (non usato).

### Template

```json
{"NAME":"RHC22 Badge","GPIO":[608,640,672,1024,6144,0,736,704,32,33,6112,0,0,0,0,0,0,0,0,0,0,0],"FLAG":0,"BASE":1}
```

### Comandi di setup (console, dopo aver flashato `tasmota32c3.bin`)

```
Backlog Template {"NAME":"RHC22 Badge","GPIO":[608,640,672,1024,6144,0,736,704,32,33,6112,0,0,0,0,0,0,0,0,0,0,0],"FLAG":0,"BASE":1}; Module 0
DisplayModel 12
DisplayMode 0
I2CScan
```

`DisplayModel 12` attiva il driver ST7789: verificare l'inquadratura con `DisplayText` — il
driver Tasmota per ST7789 è pensato soprattutto per pannelli piccoli/quadrati, quindi su un
pannello 240×320 potrebbe servire `DisplayRotate` per centrare correttamente l'immagine.

### Verifiche consigliate prima del flash definitivo

- Confermare che la build Tasmota32 in uso includa `USE_DISPLAY_ST7789` (nella maggior parte
  delle build `tasmota32c3.bin` precompilate è già incluso; se si compila da sorgente, abilitarlo
  in `user_config_override.h`).
- Ricontrollare l'assegnazione GPIO anche da GUI (Configurazione → Configura template) per
  conferma visiva prima di salvare.
- GPIO9 come pulsante è sicuro (stesso schema già usato dal firmware ufficiale): a boot resta
  normalmente alto grazie al pull-up interno che Tasmota applica di default sui `Button`.
- Se serve il controllo LED, prevedere fin da subito lo sviluppo del driver Berry per l'AW9523:
  senza di esso i 7 LED RGB restano completamente spenti/non pilotabili.
