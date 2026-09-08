# Tasmota su RHC22 Badge

Questa guida descrive come far girare **Tasmota** (in alternativa al firmware ESP-IDF/LVGL
ufficiale di questo repo) sul badge RomHack Camp 2022, riusando tutto l'hardware presente sul
PCB. Le informazioni sui GPIO e sui registri sono estratte dal firmware ufficiale
(`main/badge/led.c`, `main/badge/led.h`, `main/badge/ui.h`, `sdkconfig.rhc22-badge`, driver LVGL
`lvgl_esp32_drivers/lvgl_tft/st7789.c`) e dal `README.md` del repo; i codici componente e il
comportamento di Tasmota dalla documentazione ufficiale (pagine *Components*, *Displays*,
*Universal Display Driver*, *Berry*, *BUILDS*, *I2CDEVICES*) e dai binari pubblicati su
`ota.tasmota.com`.

**Stato (settembre 2026): verificato sul badge RHC22.** Con una build TasmoCompiler (vedi *Build
custom*) funzionano display via Universal Display Driver, LED RGB e retroilluminazione via
Berry/AW9523B, pulsanti con le regole `Button<x>#State` e la schermata di boot.

> **Attenzione concettuale**: questa è una board custom da conferenza (MCU ESP32-C3 + display +
> LED + I2C expander), non un dispositivo "smart plug/switch" tipico di Tasmota. Flashare Tasmota
> **sostituisce interamente** il firmware ufficiale: radar BLE, Snake, sync schedule via Wi-Fi,
> web UI del badge, ecc. andranno persi. Per tornare al firmware originale:
> `pio run -e rhc22-badge -t upload` seguito da `pio run -e rhc22-badge -t uploadfs` (procedura
> del README del repo, riscrive bootloader, tabella partizioni e filesystem).

## File in questa cartella

| File | Dove va | Cosa fa |
|---|---|---|
| [`display.ini`](display.ini) | filesystem del badge | descrittore uDisplay dell'ST7789 (320×240, init identica al firmware LVGL); **verificato** |
| [`autoexec.be`](autoexec.be) | filesystem del badge | eseguito a ogni boot: carica `aw9523_leds.be` e, all'arrivo della rete, disegna una schermata con IP, SSID, MAC, versione e heap libero; **verificato** |
| [`aw9523_leds.be`](aw9523_leds.be) | filesystem del badge | programma i due AW9523B come `led_init()` del firmware, accende la backlight, aggiunge i comandi `AwBacklight 0..255` e `AwLed id,r,g,b` e le regole dei pulsanti; **verificato** |
| `README.md` | — | questa guida |

I file si caricano da *Consoles → Manage File system* del web UI di Tasmota. Sopravvivono agli
aggiornamenti OTA e a `Reset 1`; spariscono solo con un flash completo (`--erase-all`).

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
| 8 | **Button1** = pulsante DOWN | `ui.h`: `BUTTON_1 0x08 // DOWN`; attivo basso, pull-up interno. **Strapping**: per il download mode deve restare alto (pulsante rilasciato) |
| 9 | **Button2** = pulsante UP | `ui.h`: `BUTTON_2 0x09 // UP`. ⚠️ **strapping boot-mode** ESP32-C3: tenuto premuto al reset, con GPIO8 alto → Joint Download Boot (già così anche col firmware ufficiale) |
| 10 | SPI **CS** display | `CONFIG_LV_DISP_SPI_CS=10` |
| 11–17 | non disponibili | riservati alla flash SPI integrata nel modulo |
| 18/19 | USB D-/D+ | USB-Serial/JTAG nativo: il `platformio.ini` prevede `upload_port = /dev/ttyACM*` / `/dev/cu.usbmodem*`, nomi tipici di quella periferica (non di un bridge USB-UART esterno) |
| 20/21 | UART0 RX/TX | console seriale di fallback |

Display: **ST7789**, 2.4", pannello 240×320 ma **pilotato dal firmware come 320×240**
(`CONFIG_LV_HOR_RES_MAX=320`, `CONFIG_LV_VER_RES_MAX=240`) con **`MADCTL = 0xC0`**
(`CONFIG_LV_DISPLAY_ORIENTATION=0`, chiamato `PORTRAIT` nel driver → `{0xC0,0x00,0x60,0xA0}[0]`
in `st7789.c`), 16 bit/pixel (`COLMOD 0x55`), **senza inversione colori** (`CONFIG_LV_INVERT_COLORS`
non impostato → `INVOFF`). Quindi la rotazione 0 di Tasmota è un raster **320 di larghezza ×
240 di altezza** con MADCTL `C0`: è ciò che fissa la riga `:H` di `display.ini`.

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
| Display ST7789 (320×240 in rotazione 0) | Universal Display Driver (`DisplayModel 17`) + `display.ini` | **build custom** con `USE_DISPLAY` + `USE_UNIVERSAL_DISPLAY` | Template: `SPI CLK/MOSI/MISO/CS/DC` + `Display Rst` + `Option A3`; comandi `DisplayText`, `DisplayRotate`, ecc. |

## Cosa **non** è supportato nativamente

- **I 7 LED RGB frontali**: sono sui due AW9523B e Tasmota **non ha un driver per l'AW9523B**;
  non essendoci una catena WS2812 non c'è nemmeno un componente `WS2812` da assegnare →
  **nessun controllo LED nativo** (`Color`, `Scheme`, `Power` non li toccano). Solo Berry, con
  `aw9523_leds.be`.
- **Backlight del display**: idem, via AW9523B. Alla partenza il chip resta nello stato di reset
  (tutti i pin in modalità GPIO, non LED): finché uno script non lo programma via I2C la
  retroilluminazione non è sotto controllo → il display può risultare **buio anche se Tasmota lo
  sta pilotando correttamente**.
- **Radar/BLE** (ricerca badge vicini), **Snake**, **sync schedule**, **web UI del badge**:
  logica applicativa, non replicabile con Tasmota stock.
- **Driver I2C "fantasma"** (verificato sul badge): il driver MLX90614 (indice 32, indirizzo
  `0x5A`) scambia l'AW9523B per un termometro a infrarossi e riempie la console di
  `mlx checksum error`. Disabilitarlo con `I2CDriver32 0` (impostazione persistente). Allo stesso
  indirizzo rispondono anche i driver CCS811 (indice 24, `0x5A/0x5B`) e MPR121 (indice 23,
  `0x5A..0x5D`): se la build li include e compaiono, `I2CDriver24 0` / `I2CDriver23 0`. Indici
  nella pagina *I2CDEVICES* della documentazione.

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

Sono gli stessi valori scritti da [`aw9523_leds.be`](aw9523_leds.be) all'avvio:

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

Backlight: `0x5A`, `0x20..0x23`. Lo script espone l'oggetto `leds` anche nella console Berry
(`leds.all(r, g, b)`, `leds.set_led(id, r, g, b)`, `leds.backlight(0..255)`), i comandi
`AwBacklight 0..255` e `AwLed id,r,g,b` (es. `AwLed 0,232,11,96` = `MAGENTA_SAIYAN` sul LED
centrale) e le regole dei pulsanti descritte sotto. Dopo un semplice `Restart` i chip conservano
i registri; dopo uno spegnimento completo no, per questo `autoexec.be` lo carica a ogni boot. Su
questa base si possono ricostruire in Berry le animazioni del firmware (`flash()`,
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

### `display.ini`

Il file [`display.ini`](display.ini) (identico a quello del badge WHY2025/EMF2026: stesso
pannello, stesso `sdkconfig` LVGL) è il descrittore uDisplay ricavato dalla sequenza di init del
driver LVGL `st7789.c` usato dal firmware (stessi comandi e parametri; `36,1,C0` = orientamento
del badge; `20,0` = `INVOFF`). Struttura:

- `:H,ST7789,320,240,16,SPI,1,*,*,*,*,*,*,*,40`: nome, **320×240** (le dimensioni LVGL del
  firmware), 16 bit/pixel, SPI hardware 1, pin presi dal template (`*` = `SPI CS`, `SPI CLK`,
  `SPI MOSI`, `SPI DC`, `Backlight` → non assegnato, `Display Rst`, `SPI MISO`), 40 MHz (se
  l'immagine è corrotta provare `20`);
- `:I` … : sequenza di init, formato `comando, numero argomenti (hex), argomenti…`; il nibble
  alto del contatore aggiunge una pausa (`8x` = 150 ms);
- `:0..:3`: MADCTL delle 4 rotazioni di `DisplayRotate 0..3` (0°, 90° orario, 180°, 270°,
  tabella `C0/A0/00/60`): `:0` è l'orientamento del firmware (320×240), `:1`/`:3` danno
  240×320; se rosso e blu risultano scambiati aggiungere `0x08` (BGR) ai quattro valori;
- `:i,20,21`: opcode di inversione off/on per `DisplayInvert`.

### Risoluzione e orientamento

Le dimensioni in `:H` descrivono il raster **nella rotazione 0** e devono corrispondere a ciò che
il pannello indirizza con il MADCTL della riga `:0`. Il riferimento è il firmware ufficiale:
LVGL a **320×240** con `MADCTL 0xC0` (identico sui badge RHC22 e WHY2025/EMF2026). Quindi:

- `:H,ST7789,320,240,…` + `:0,C0,…` = rotazione 0 identica al firmware (**configurazione
  verificata su entrambi i badge**);
- `DisplayRotate 1` o `3` → uDisplay passa a 240×320 e usa i MADCTL con bit `MV` (`A0`, `60`);
  `DisplayRotate 2` = 320×240 capovolto (`00`);
- **sbagliato**: `:H,ST7789,240,320,…` con `C0` (la prima versione di questa guida). uDisplay
  limita x a 239 mentre il pannello ne indirizza 320: la fascia **destra** dello schermo (80
  colonne) non viene mai disegnata né aggiornata. È il sintomo osservato sul badge WHY2025.

Controlli rapidi dopo ogni modifica al file (serve `Restart 1`):

```
Display
DisplayText [B63488z]
DisplayText [B0z][x10y10s2]Test
```

`Display` riporta `Model 17`, `Width 320`, `Height 240` e `Rotate` effettivi; `[B63488z]` riempie
di rosso **tutta** l'area logica (se resta una fascia nera, il file caricato non è questo);
`[B0z]` torna al nero. Non partire dall'esempio `ST7789_display.ini` di Tasmota: è per pannelli
240×240 con offset `50` (80 px) nelle rotazioni.

Per la dimensione del testo non si tocca la risoluzione: `DisplaySize 1..4` oppure `[sN]` dentro
`DisplayText`; `DisplayFont` per i font alternativi.

**Storico (2024)**: un tentativo con Tasmota 14.2.0.4 usava già uDisplay (`DisplayModel 17`,
`SPI CS`/`SPI DC` su GPIO10/GPIO4) ma con il `display.ini` d'esempio di Tasmota per pannelli
**240×240** (`DisplayWidth`/`DisplayHeight` = 240, offset `50` nelle rotazioni): il risultato era
la classica **banda nera**, cioè le 80 colonne non indirizzate. Inoltre il template non aveva
I2C (`Option A3` era su GPIO0, GPIO1 vuoto), quindi i due AW9523B erano irraggiungibili: niente
LED e nessun controllo della backlight. Il template e il `display.ini` di questa guida risolvono
entrambe le cose.

### Comandi di setup (console)

Inserire i comandi **uno per riga** nella console e leggere la risposta di ciascuno: il campo di
input è a riga singola, un blocco incollato su più righe viene fuso in una sola.

```
Backlog Template {"NAME":"RHC22 Badge","GPIO":[608,640,672,1024,800,6210,736,704,32,33,768,0,0,0,0,0,0,0,0,0,0,0],"FLAG":0,"BASE":1}; Module 0
```

Dopo il riavvio, caricare nel filesystem i tre file di questa cartella (`display.ini`,
`aw9523_leds.be`, `autoexec.be`), poi:

```
Backlog DisplayModel 17; DisplayMode 0; DisplayRotate 0; SetOption73 1; SetOption1 1; SetOption32 10; I2CDriver32 0
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
`11` = doppia, `12` = tripla, `3` = tenuto (doc *Rules*, esempio `ON button1#state=10 DO …`;
**verificato su entrambi i badge**). Un trigger `Button<x>#Action=SINGLE` **non scatta**.
`SetOption1 1` evita che pressioni multiple entrino in WifiConfig/Reset; `SetOption32 10` porta il
tempo di "tenuto" da 4 s a 1 s.

Le regole stanno in `aw9523_leds.be` (`tasmota.add_rule`, nessuna `Rule1` da inserire in
console): UP singolo → tutti i LED magenta, DOWN singolo → LED spenti, UP tenuto → backlight al
massimo, DOWN tenuto → backlight spenta. Controlli: premendo un tasto in console deve comparire
`{"Button2":{"Action":"SINGLE"}}` e `SetOption73` deve rispondere `ON`.

### Riepilogo di tutte le impostazioni applicate

Tutto ciò che è stato impostato per arrivare alla configurazione verificata, con il motivo. Le
voci "console" sono salvate nelle impostazioni Tasmota in flash (persistono al riavvio e all'OTA;
`Reset 1` le azzera), i file stanno nel filesystem.

| Dove | Impostazione | Cosa fa | Perché |
|---|---|---|---|
| build | `USE_DISPLAY`, `USE_UNIVERSAL_DISPLAY`, (`USE_DISPLAY_MODES1TO5`) | compila il driver display universale (e i DisplayMode 1–5) | il binario stock per C3 non ha alcun driver display |
| console | `Template {…}` + `Module 0` | assegna i componenti ai GPIO e attiva il template | mappa hardware del badge (I2C, SPI, pulsanti) |
| template | `Option A3` su GPIO5 | marcatore virtuale che avvia uDisplay | richiesto da uDisplay; GPIO5 è libero su questa board |
| filesystem | `display.ini` | descrittore ST7789 320×240 con l'init del firmware | il pannello va indirizzato come 320×240 con MADCTL `C0` (era la "banda nera" del 2024) |
| console | `DisplayModel 17` | seleziona lo Universal Display Driver | unico driver TFT rimasto in Tasmota |
| console | `DisplayMode 0` | schermo pilotato solo da `DisplayText`/script | niente layout automatici sopra la schermata di boot |
| console | `DisplayRotate 0` | orientamento del firmware ufficiale | |
| console | `SetOption73 1` | pulsanti scollegati da `Power`, eventi `Button<x>#State` | non c'è nessun `Power` da comandare |
| console | `SetOption1 1` | niente WifiConfig/Reset da pressioni multiple | evitare reset accidentali dai pulsanti |
| console | `SetOption32 10` | pressione "tenuta" = 1 s (default 4 s) | uso pratico dell'hold |
| console | `I2CDriver32 0` | disabilita il driver MLX90614 | interrogava l'AW9523B a `0x5A` (`mlx checksum error`) |
| filesystem | `aw9523_leds.be` | init dei due AW9523B come `led_init()`, backlight a 180, LED spenti, comandi `AwBacklight`/`AwLed`, regole dei pulsanti | LED e backlight sono solo su I2C |
| filesystem | `autoexec.be` | `load("aw9523_leds.be")` + schermata di boot alla connessione | eseguito a ogni avvio; gli AW9523B perdono i registri allo spegnimento |
| flash | `firmware.factory.bin` con esptool a `0x0`; poi OTA con `firmware.bin` | primo flash e aggiornamenti | il web flasher da browser ha dato boot loop (sul WHY2025) |

### Build custom (necessaria per il display)

**Via TasmoCompiler** (strada verificata su entrambi i badge, nessuna toolchain locale):

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
  `DisplayText` funziona. Se al boot la console dice `AW9523: chip 0x5A/0x5B non trovati`,
  l'I2C non era pronto quando è partito `autoexec.be`: rimandare il `load` con
  `tasmota.set_timer(1000, def () load("aw9523_leds.be") end)`.
- GPIO9 come pulsante è sicuro (stesso schema del firmware ufficiale). Lo strapping viene
  campionato al reset, prima che Tasmota parta: il livello alto lo garantisce l'hardware del
  badge, non il pull-up software del componente `Button`. Per il download mode servono GPIO9
  basso **e GPIO8 alto**: tenere premuto solo il pulsante UP, non entrambi.
