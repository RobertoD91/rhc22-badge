# Tasmota su RHC22 Badge

Questo documento descrive come far girare **Tasmota** (in alternativa al firmware ESP-IDF/LVGL
ufficiale di questo repo) sul badge RomHack Camp 2022, riusando tutto l'hardware presente sul
PCB. Le informazioni sui GPIO e sui registri sono estratte dal firmware ufficiale
(`main/badge/led.c`, `main/badge/led.h`, `main/badge/ui.h`, `sdkconfig.rhc22-badge`, driver LVGL
`lvgl_esp32_drivers/lvgl_tft/st7789.c`) e dal `README.md`; i codici componente e il
comportamento di Tasmota dalla documentazione ufficiale (pagine *Components*, *Displays*,
*Universal Display Driver*, *Berry*, *BUILDS*) e dai binari pubblicati su `ota.tasmota.com`.

**Stato (settembre 2026)**: la stessa configurazione (stessa MCU, stesso display e driver, stesso
`display.ini`) è stata **verificata sul badge WHY2025/EMF2026** con una build TasmoCompiler
(vedi *Build custom*); su RHC22 non è ancora stata provata sull'hardware. Le differenze attese
sono solo i LED (AW9523B invece di WS2812, quindi solo via Berry) e GPIO5 libero.

> **Attenzione concettuale**: questa è una board custom da conferenza (MCU ESP32-C3 + display +
> LED + I2C expander), non un dispositivo "smart plug/switch" tipico di Tasmota. Flashare Tasmota
> **sostituisce interamente** il firmware ufficiale: radar BLE, Snake, sync schedule via Wi-Fi,
> web UI del badge, ecc. andranno persi. Per tornare al firmware originale:
> `pio run -e rhc22-badge -t upload` seguito da `pio run -e rhc22-badge -t uploadfs` (procedura
> del README, riscrive bootloader, tabella partizioni e filesystem).

## Hardware e mappa GPIO (ESP32-C3)

| GPIO | Funzione sul PCB | Note |
|---|---|---|
| 0 | I2C **SCL** | bus a 400 kHz verso **due** AW9523B (`0x5A`, `0x5B`): 7 LED RGB + backlight |
| 1 | I2C **SDA** | idem |
| 2 | SPI **MISO** (SDO del display) | configurato dal firmware; Tasmota non ne ha bisogno (display solo in scrittura) |
| 3 | Display **RESET** | ST7789 |
| 4 | Display **DC** (data/command) | ST7789 |
| 5 | **libero** | su questa revisione i LED **non** sono WS2812 (nessun `LED_RMT_TX_GPIO` in `led.h`): GPIO5 è inutilizzato → ci va `Option A3` (vedi template) |
| 6 | SPI **CLK** | ST7789, SPI hardware |
| 7 | SPI **MOSI** | ST7789 |
| 8 | **Button1** = pulsante DOWN | `ui.h`: `BUTTON_1 0x08 // DOWN`; attivo basso, pull-up interno |
| 9 | **Button2** = pulsante UP | `ui.h`: `BUTTON_2 0x09 // UP`. ⚠️ **strapping boot-mode** ESP32-C3: tenuto premuto al reset → Joint Download Boot (già così anche col firmware ufficiale) |
| 10 | SPI **CS** display | `CONFIG_LV_DISP_SPI_CS=10` |
| 11–17 | non disponibili | riservati alla flash SPI integrata nel modulo |
| 18/19 | USB D-/D+ | USB-Serial/JTAG nativo: il `platformio.ini` prevede `upload_port = /dev/ttyACM*` / `/dev/cu.usbmodem*`, nomi tipici di quella periferica (non di un bridge USB-UART esterno) |
| 20/21 | UART0 RX/TX | console seriale di fallback |

Display: **ST7789**, 2.4", **240×320**, SPI hardware a 16 bit/pixel (`COLMOD 0x55`). Il firmware
lo usa in **portrait con `MADCTL = 0xC0`** (`CONFIG_LV_DISPLAY_ORIENTATION=0` →
`{0xC0,0x00,0x60,0xA0}[0]` nel driver `st7789.c`) e **senza inversione colori**
(`CONFIG_LV_INVERT_COLORS` non impostato → `INVOFF`). Servono per il `display.ini` più sotto.

Backlight: **non è su un GPIO** dell'ESP32-C3 (`CONFIG_LV_ENABLE_BACKLIGHT_CONTROL` non
impostato). È pilotata dai pin `P1_0..P1_3` dell'AW9523B `0x5A` in modalità LED, registri DIM
`0x20..0x23` (`set_screen_led_backlight()` in `led.c`).

LED RGB frontali (7): **via I2C**, 21 canali a corrente costante distribuiti sui due AW9523B
(tabelle `addr[]`/`reg[]` in `led.c`; mappa completa nella sezione Berry). Nessuna catena
WS2812 su questa revisione (a differenza del badge WHY2025/EMF2026).

Alimentazione: 2× batterie AA (README); nessun GPIO da configurare.

## Quale binario Tasmota — il punto critico è il display

- Il binario precompilato **`tasmota32c3.bin` non contiene nessun driver display**: nella tabella
  ufficiale delle build `USE_DISPLAY` / `USE_UNIVERSAL_DISPLAY` sono presenti solo nelle varianti
  `-display` e `-lvgl`, e queste **esistono solo per ESP32 classico** (`tasmota32-display.bin`,
  `tasmota32-lvgl.bin`). Su `ota.tasmota.com` per il C3 ci sono solo `tasmota32c3.bin`,
  `tasmota32c3.factory.bin` e `tasmota32c3ser-safeboot.bin`. **Per usare il display serve una
  build personalizzata** (vedi *Build custom* più sotto). Nella cartella *unofficial* di
  `github.com/tasmota/install` (branch `firmware`) esiste `tasmota32c3-lvgl.factory.bin`, che
  include uDisplay ma è compilato `USE_DISPLAY_LVGL_ONLY`: niente `DisplayText`, schermo
  pilotabile solo da Berry/LVGL e pesante su un C3 senza PSRAM. Piano B, non piano A.
- Con il binario stock funzionano comunque: Wi-Fi/MQTT/web UI, i **due pulsanti**, il bus
  **I2C** (`I2CScan`) e **Berry** — quindi anche i **7 LED RGB e la backlight** via script,
  che su questa board è l'unica strada in ogni caso.
- I driver display specifici per TFT SPI (fra cui l'ST7789 legacy, `DisplayModel 12`) **sono
  stati rimossi** dal sorgente Tasmota (in v15.6.0 non esiste più `xdsp_12_ST7789.ino`): resta
  solo lo **Universal Display Driver** (`DisplayModel 17`, descrittore `display.ini`). La
  configurazione sotto usa quello.
- Console: nelle release attuali `tasmota32c3.bin` usa la **console USB (HWCDC)** sul
  connettore USB con fallback su UART0 (GPIO20/21) quando l'USB non è collegato; la vecchia
  variante separata `tasmota32c3cdc` non è più pubblicata.

## Cosa è supportato **nativamente** da Tasmota

| Hardware | Componente Tasmota | Richiede | Come si abilita |
|---|---|---|---|
| Button1 / Button2 (DOWN / UP) | `Button` | binario stock | Template: `Button1` (32) su GPIO8, `Button2` (33) su GPIO9. Senza nessun dispositivo `Power` da soli non fanno nulla di utile: `SetOption73 1` li trasforma in eventi per regole/Berry, vedi *Pulsanti* |
| Bus I2C | `I2CScan`, accesso da Berry | binario stock | Template: `I2C SCL` (608) su GPIO0, `I2C SDA` (640) su GPIO1 |
| Display ST7789 240×320 | Universal Display Driver (`DisplayModel 17`) + `display.ini` | **build custom** con `USE_DISPLAY` + `USE_UNIVERSAL_DISPLAY` | Template: `SPI CLK/MOSI/MISO/CS/DC` + `Display Rst` + `Option A3`; comandi `DisplayText`, `DisplayRotate`, ecc. |

## Cosa **non** è supportato nativamente

- **I 7 LED RGB frontali**: sono sui due AW9523B e Tasmota **non ha un driver per l'AW9523B**;
  non essendoci una catena WS2812 non c'è nemmeno un componente `WS2812` da assegnare →
  **nessun controllo LED nativo** (`Color`, `Scheme`, `Power` non li toccano). Solo Berry.
- **Backlight del display**: idem, via AW9523B. Alla partenza il chip resta nello stato di reset
  (tutti i pin in modalità GPIO, non LED): finché uno script non lo programma via I2C la
  retroilluminazione non è sotto controllo → il display può risultare **buio anche se Tasmota lo
  sta pilotando correttamente**.
- **Radar/BLE** (ricerca badge vicini), **Snake**, **sync schedule**, **web UI del badge**:
  logica applicativa, non replicabile con Tasmota stock.
- Attenzione: alcuni driver sensore inclusi in `tasmota32` condividono gli indirizzi
  `0x5A`/`0x5B` (es. CCS811, MLX90614). Se dopo il boot compare un sensore "fantasma" a quegli
  indirizzi, disabilitare il driver corrispondente con `I2CDriver<n> 0` (indici nella pagina
  *I2CDEVICES* della documentazione).

## Cosa è raggiungibile tramite **scripting Berry**

Berry è incluso in `tasmota32c3.bin`. L'accesso I2C **non** passa da un modulo `i2c`: si usano
gli oggetti `tasmota.wire1` / `tasmota.wire2` (bus 1 = i pin `I2C SCL/SDA` del template) oppure
`tasmota.wire_scan(addr)`, che cerca il chip sui bus configurati e restituisce il `wire` giusto o
`nil`. Metodi: `wire.write(addr, reg, val, size)`, `wire.read(addr, reg, size)`,
`wire.write_bytes(addr, reg, bytes)`, `wire.read_bytes(addr, reg, size)`, `wire.scan()`,
`wire.detect(addr)`. Un driver si registra con `tasmota.add_driver(istanza)`, un comando console
con `tasmota.add_cmd(nome, funzione)`. Gli script vanno nel filesystem (LittleFS) e si caricano
da `autoexec.be`.

### Registri AW9523B usati dal firmware (`led_init()`)

| Chip | Registro | Valore | Significato |
|---|---|---|---|
| `0x5A`, `0x5B` | `0x11` (GCR) | `0x03` | limite corrente LED = 1/4 Imax; **non** è il "LED mode" |
| `0x5A` | `0x12` | `0x80` | P0_0..P0_6 in LED mode (bit=0 → LED, bit=1 → GPIO; reset = `0xFF`), P0_7 GPIO |
| `0x5A` | `0x13` | `0x80` | P1_0..P1_6 LED (include backlight P1_0..P1_3), P1_7 GPIO |
| `0x5B` | `0x12` | `0x00` | tutta P0 in LED mode |
| `0x5B` | `0x13` | `0x08` | P1 in LED mode tranne P1_3 |

Senza queste scritture i registri DIM (`0x20..0x2F`) non hanno alcun effetto. Mappa dei 7 LED
(`reg[id*3 + RED/GREEN/BLUE]`, con `enum LED_COLOR { RED, GREEN, BLUE }` in `led.h`; `id 0` =
LED centrale, `id 6` = LED in alto):

| id | chip | R | G | B |
|---|---|---|---|---|
| 0 | `0x5B` | `0x2D` | `0x2E` | `0x2F` |
| 1 | `0x5A` | `0x2A` | `0x29` | `0x28` |
| 2 | `0x5B` | `0x24` | `0x25` | `0x26` |
| 3 | `0x5B` | `0x2A` | `0x2B` | `0x2C` |
| 4 | `0x5B` | `0x27` | `0x28` | `0x29` |
| 5 | `0x5B` | `0x22` | `0x21` | `0x20` |
| 6 | `0x5A` | `0x2E` | `0x2D` | `0x2C` |

Backlight: `0x5A`, `0x20..0x23`. Script **non testato sull'hardware**, ma allineato riga per
riga a `led.c`:

```berry
# aw9523_leds.be — 7 LED RGB + backlight via due AW9523B, tabelle riprese da main/badge/led.c
import string

class RHC22_Leds
  var w5a, w5b, addr_tab, reg_tab
  def init()
    self.addr_tab = [0x5B, 0x5A, 0x5B, 0x5B, 0x5B, 0x5B, 0x5A]   # addr[id]
    self.reg_tab  = [                                            # reg[id*3 + R/G/B]
      [0x2D, 0x2E, 0x2F], [0x2A, 0x29, 0x28], [0x24, 0x25, 0x26],
      [0x2A, 0x2B, 0x2C], [0x27, 0x28, 0x29], [0x22, 0x21, 0x20],
      [0x2E, 0x2D, 0x2C]
    ]
    self.w5a = tasmota.wire_scan(0x5A)
    self.w5b = tasmota.wire_scan(0x5B)
    if self.w5a == nil || self.w5b == nil
      print("AW9523: chip 0x5A/0x5B non trovati")
      return
    end
    # identico a led_init()
    self.w5a.write(0x5A, 0x11, 0x03, 1)
    self.w5b.write(0x5B, 0x11, 0x03, 1)
    self.w5a.write(0x5A, 0x12, 0x80, 1)
    self.w5a.write(0x5A, 0x13, 0x80, 1)
    self.w5b.write(0x5B, 0x12, 0x00, 1)
    self.w5b.write(0x5B, 0x13, 0x08, 1)
  end
  def backlight(level)                     # 0..255, equivale a set_screen_led_backlight()
    if self.w5a == nil return end
    for reg: [0x20, 0x21, 0x22, 0x23]
      self.w5a.write(0x5A, reg, level, 1)
    end
  end
  def set_led(id, r, g, b)                 # id 0..6, valori 0..255
    if self.w5a == nil return end
    var addr = self.addr_tab[id]
    var w = (addr == 0x5A) ? self.w5a : self.w5b
    var regs = self.reg_tab[id]
    w.write(addr, regs[0], r, 1)
    w.write(addr, regs[1], g, 1)
    w.write(addr, regs[2], b, 1)
  end
  def all(r, g, b)
    for id: 0..6
      self.set_led(id, r, g, b)
    end
  end
end

var leds = RHC22_Leds()
leds.backlight(180)
leds.all(0, 0, 0)

# AwBacklight 0..255
tasmota.add_cmd('AwBacklight', def (cmd, idx, payload)
  leds.backlight(int(payload))
  tasmota.resp_cmnd_done()
end)

# AwLed <id>,<r>,<g>,<b>   es. AwLed 0,232,11,96  (MAGENTA_SAIYAN)
tasmota.add_cmd('AwLed', def (cmd, idx, payload)
  var p = string.split(payload, ',')
  leds.set_led(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
  tasmota.resp_cmnd_done()
end)
```

Su questa base si possono ricostruire in Berry le animazioni del firmware (`flash()`,
`set_completed()`) usando `tasmota.set_timer` o un driver con `every_100ms`.

## Configurazione Tasmota

Codici componente **Tasmota32/ESP32** (pagina *Components*, tabella ESP32 — quelli della tabella
ESP8266 sono diversi per i componenti display): `I2C SCL1=608`, `I2C SDA1=640`, `SPI MISO1=672`,
`SPI MOSI1=704`, `SPI CLK1=736`, `SPI CS1=768`, `SPI DC1=800`, `Display Rst=1024`, `Button1=32`,
`Button2=33`, `Option A3=6210`.

Per ESP32-C3 l'array `GPIO` del template ha **22 elementi**, indice = numero GPIO (0…21);
gli indici 11–17 (flash) restano a 0 (stesso schema del template ufficiale "SuperMini ESP32-C3").

### Template (Universal Display Driver)

```json
{"NAME":"RHC22 Badge","GPIO":[608,640,672,1024,800,6210,736,704,32,33,768,0,0,0,0,0,0,0,0,0,0,0],"FLAG":0,"BASE":1}
```

Indice per indice: 0 `I2C SCL`, 1 `I2C SDA`, 2 `SPI MISO`, 3 `Display Rst`, 4 `SPI DC`,
5 `Option A3`, 6 `SPI CLK`, 7 `SPI MOSI`, 8 `Button1`, 9 `Button2`, 10 `SPI CS`.

`Option A3` è il **marcatore virtuale** che attiva lo Universal Display Driver: va su un GPIO
libero e non configura fisicamente il pin. Qui GPIO5 è realmente libero, quindi si può tenere
anche `SPI MISO` su GPIO2.

### `display.ini` (da caricare nel filesystem: *Consoles → Manage File system*)

Descrittore uDisplay ricavato dalla sequenza di init del driver LVGL `st7789.c` usato dal
firmware (stessi comandi e parametri; `36,1,C0` = portrait del badge; `20,0` = `INVOFF`).
Formato `:I`: `comando, numero argomenti (hex), argomenti…`; il nibble alto del contatore
aggiunge una pausa (`8x` = 150 ms).

```ini
:H,ST7789,240,320,16,SPI,1,*,*,*,*,*,*,*,40
:S,2,1,1,0,40,20
:I
CF,3,00,83,30
ED,4,64,03,12,81
E8,3,85,01,79
CB,5,39,2C,00,34,02
F7,1,20
EA,2,00,00
C0,1,26
C1,1,11
C5,2,35,3E
C7,1,BE
36,1,C0
3A,1,55
20,0
B1,2,00,1B
F2,1,08
26,1,01
E0,0E,D0,00,02,07,0A,28,32,44,42,06,0E,12,14,17
E1,0E,D0,00,02,07,0A,28,31,54,47,0E,1C,17,1B,1E
2A,4,00,00,00,EF
2B,4,00,00,01,3F
B7,1,07
B6,4,0A,82,27,00
11,80
29,80
:o,28
:O,29
:A,2A,2B,2C
:R,36
:0,C0,00,00,00
:1,A0,00,00,01
:2,00,00,00,02
:3,60,00,00,03
:i,20,21
#
```

Gli `*` nella riga `:H` prendono i pin dal template (`SPI CS`, `SPI CLK`, `SPI MOSI`, `SPI DC`,
`Backlight` → non assegnato, `Display Rst`, `SPI MISO`). `40` = 40 MHz: se l'immagine è corrotta
provare `20`. Le righe `:0..:3` sono le 4 rotazioni di `DisplayRotate 0..3` (0°, 90° orario,
180°, 270°: la stessa tabella `C0/A0/00/60` del driver Adafruit per ST7789 240×320), con `:0`
uguale all'orientamento del firmware ufficiale; se rosso e blu risultano scambiati aggiungere
`0x08` (BGR) ai quattro valori MADCTL.

### Risoluzione e orientamento

Le dimensioni in `:H` (`240,320`) descrivono il pannello **nella rotazione 0** e devono essere
coerenti con il MADCTL della riga `:0`: il bit `MV` (`0x20`) scambia righe e colonne del
controller, quindi i valori senza `MV` (`C0`, `00`) sono portrait 240×320 e quelli con `MV`
(`60`, `A0`) sono landscape 320×240. Due configurazioni valide:

- **portrait nativo** (quella sopra): `:H,ST7789,240,320,…` e `:0,C0,…`; per lavorare in
  orizzontale basta `DisplayRotate 1` o `3`: uDisplay passa da solo a 320×240 e usa il MADCTL
  di `:1`/`:3`;
- **landscape nativo**: `:H,ST7789,320,240,…` con `:0,A0,00,00,00` (oppure `60` se risulta
  capovolto) e le altre tre righe ruotate di conseguenza (`:1,00`, `:2,60`, `:3,C0`).

Sintomo tipico di incoerenza (segnalato sul badge WHY2025/EMF2026 dopo un cambio di
risoluzione): la parte **destra** dello schermo resta vuota e non si aggiorna. Succede portando
`:H` a `320,240` e lasciando `:0,C0`: il controller è ancora in modalità 240 colonne e scarta
tutto ciò che cade oltre la colonna 239. Correggere il MADCTL (o tornare a `240,320` +
`DisplayRotate`), poi `Restart 1`; il comando `Display` (senza parametri) riporta `Model`,
`Width`, `Height` e `Rotate` effettivi, utile per confermare che cosa ha caricato uDisplay.

Per la dimensione del testo non si tocca la risoluzione: `DisplaySize 1..4` oppure `[sN]` dentro
`DisplayText`; `DisplayFont` per i font alternativi.

### Comandi di setup (console)

```
Backlog Template {"NAME":"RHC22 Badge","GPIO":[608,640,672,1024,800,6210,736,704,32,33,768,0,0,0,0,0,0,0,0,0,0,0],"FLAG":0,"BASE":1}; Module 0
```

Dopo il riavvio, caricare `display.ini` (e gli script Berry + `autoexec.be`) nel filesystem, poi:

```
Backlog DisplayModel 17; DisplayMode 0; DisplayRotate 0; SetOption73 1; SetOption1 1
Restart 1
DisplayText [z][x20y20s2]Ciao dal badge
I2CScan
AwLed 0,232,11,96
```

`I2CScan` deve mostrare `0x5A` e `0x5B`. `DisplayModel` deve rispondere `17`: se risponde
"Unknown command" la build non contiene il display.

### Pulsanti

Tasmota associa `Button<n>` a `Power<n>`; su questa board non c'è nessun dispositivo `Power`
(niente relè, niente WS2812), quindi da soli i pulsanti non fanno nulla di utile.
`SetOption73 1` li scollega dai relè: a ogni pressione Tasmota pubblica su MQTT
`{"Button<x>":{"Action":"SINGLE"}}` (azioni `SINGLE`/`DOUBLE`/`TRIPLE`/`QUAD`/`PENTA`/`HOLD`) ma
**il trigger per regole e Berry è `Button<x>#State`** con valori numerici: `10` = singola,
`11` = doppia, `12` = tripla, `3` = tenuto (doc *Rules*, esempio `ON button1#state=10 DO …`). Un
trigger `Button<x>#Action=SINGLE` **non scatta**. `SetOption1 1` evita che pressioni multiple
entrino in WifiConfig/Reset; `SetOption32 10` porta il tempo di "tenuto" da 4 s a 1 s
(`Backlog SetOption73 1; SetOption1 1; SetOption32 10`). Gli eventi si usano in regole o, più
comodo qui, in Berry per pilotare LED e backlight con lo script sopra (da aggiungere in coda a
`aw9523_leds.be`):

```berry
tasmota.add_rule("Button2#State=10", def () leds.all(232, 11, 96) end)   # UP singolo: LED magenta
tasmota.add_rule("Button1#State=10", def () leds.all(0, 0, 0) end)       # DOWN singolo: LED spenti
tasmota.add_rule("Button2#State=3", def () leds.backlight(255) end)      # UP tenuto
tasmota.add_rule("Button1#State=3", def () leds.backlight(0) end)        # DOWN tenuto
```

Diagnosi: premendo un tasto in console deve comparire `{"Button2":{"Action":"SINGLE"}}` e
`SetOption73` deve rispondere `ON`.

`autoexec.be` minimo:

```berry
load("aw9523_leds.be")
```

### Build custom (necessaria per il display)

**Via TasmoCompiler** (strada verificata sul badge WHY2025/EMF2026, nessuna toolchain locale):

```
docker run --rm --name tasmocompiler -p 3000:3000 benzino77/tasmocompiler
```

poi su `http://localhost:3000`: board **ESP32-C3**, versione *release*; nelle *Features* spuntare
`USE_DISPLAY` e `USE_UNIVERSAL_DISPLAY` (più `USE_DISPLAY_MODES1TO5` se servono i DisplayMode
1–5); `USE_I2C`/`USE_SPI` sono inclusi di default; **non** spuntare `USE_LVGL` né
`USE_DISPLAY_LVGL_ONLY`. Nessun *Custom parameter* obbligatorio. In output si ottengono
`firmware.factory.bin` (immagine completa, per il primo flash via cavo) e `firmware.bin`
(immagine OTA, per gli aggiornamenti dal web UI), oltre a `platformio_override.ini` e
`user_config_override.h` generati.

**Via PlatformIO** (equivalente): clonare Tasmota, creare `tasmota/user_config_override.h` dal
file `.sample` con

```c
#define USE_DISPLAY
#define USE_UNIVERSAL_DISPLAY
#define USE_DISPLAY_MODES1TO5   // opzionale
```

e `pio run -e tasmota32c3` → `build_output/firmware/tasmota32c3.factory.bin` e
`tasmota32c3.bin`. Sono le stesse opzioni che `-DFIRMWARE_DISPLAYS` attiva nella variante
`tasmota32-display` per ESP32 classico.

### Flash

Primo flash (immagine *factory*, da offset `0x0`) con esptool:

```
esptool.py --chip esp32c3 --port /dev/ttyACM0 write_flash 0x0 firmware.factory.bin
```

Sul badge WHY2025 la stessa immagine scritta con un web flasher da browser ha prodotto un
**boot loop**, mentre con esptool funziona: usare esptool (con `--erase-all` la prima volta, se
il dubbio è lo stato precedente della flash). Se la porta non entra da sola in download mode:
tenere premuto il pulsante **UP** (GPIO9) mentre si alimenta/resetta il badge, poi rilasciarlo.

Aggiornamenti successivi: **OTA dal web UI** (*Firmware Upgrade → Upload file* con
`firmware.bin`), senza cavo e conservando template, Wi-Fi e filesystem (`display.ini`, script
Berry).

### Driver legacy `DisplayModel 12`: non più disponibile

In Tasmota v15.6.0 i driver display specifici per TFT SPI (`xdsp_12_ST7789`, `xdsp_04_ili9341`,
…) **non esistono più** nel sorgente: `#define USE_DISPLAY_ST7789` non abilita nulla e i
componenti `ST7789 CS/DC` del template restano senza driver. L'unica strada è lo Universal
Display Driver descritto sopra.

### Verifiche consigliate

- Controllare da GUI (*Configurazione → Configura template*) che gli indici 4, 5, 10 risultino
  `SPI DC`, `Option A3`, `SPI CS` e non componenti ESP8266 (codici diversi).
- Prima del display, verificare con `I2CScan` che entrambi gli AW9523B rispondano, poi che lo
  script Berry accenda backlight e LED: senza di esso schermo nero e LED spenti anche se
  `DisplayText` funziona.
- GPIO9 come pulsante è sicuro (stesso schema del firmware ufficiale). Lo strapping viene
  campionato al reset, prima che Tasmota parta: il livello alto lo garantisce l'hardware del
  badge, non il pull-up software del componente `Button`. Per il download mode servono GPIO9
  basso **e GPIO8 alto**: tenere premuto solo il pulsante UP, non entrambi.
