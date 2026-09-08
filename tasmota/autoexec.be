# autoexec.be - RHC22 badge boot info

# LED RGB e retroilluminazione via AW9523B: vanno programmati a ogni avvio.
# Dopo un semplice Restart i chip conservano i registri, dopo uno spegnimento no.
load("aw9523_leds.be")

def version_string()
  var v = tasmota.version()
  return format("%d.%d.%d.%d",
    (v >> 24) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 8)  & 0xFF,
    v & 0xFF)
end

def show_boot_info()
  var ip      = tasmota.wifi("ip")
  var ssid    = tasmota.wifi("ssid")
  var rssi    = tasmota.wifi("rssi")
  var quality = tasmota.wifi("quality")
  var mac     = tasmota.wifi("mac")
  var heap    = tasmota.get_free_heap()
  var arch    = tasmota.arch()
  var ver     = version_string()

  if ip == nil      ip = "-" end
  if ssid == nil    ssid = "-" end
  if rssi == nil    rssi = 0 end
  if quality == nil quality = 0 end
  if mac == nil     mac = "-" end

  tasmota.cmd("DisplayMode 0", true)
  tasmota.cmd("DisplayPower 1", true)

  # pulisci completamente lo schermo
  tasmota.cmd("DisplayText [z]", true)

  # titolo
  tasmota.cmd("DisplayText [x10y10f2s1]RHC22 / Tasmota", true)

  # informazioni
  tasmota.cmd("DisplayText [x10y45f1s1]IP: " + str(ip), true)
  tasmota.cmd("DisplayText [x10y70f1s1]SSID: " + str(ssid), true)

  tasmota.cmd(
    "DisplayText [x10y95f1s1]WiFi: " +
    str(rssi) + " dBm  (" + str(quality) + "%)",
    true
  )

  tasmota.cmd("DisplayText [x10y120f1s1]MAC: " + str(mac), true)
  tasmota.cmd("DisplayText [x10y145f1s1]MCU: " + str(arch), true)
  tasmota.cmd("DisplayText [x10y170f1s1]Tasmota: " + ver, true)

  tasmota.cmd(
    "DisplayText [x10y195f1s1]Free heap: " +
    str(int(heap / 1024)) + " KB",
    true
  )
end

# Aspetta che Wi-Fi/Ethernet abbia realmente un IP.
# Un piccolo ritardo ulteriore evita di correre contro
# l'inizializzazione del display durante il boot.
def network_ready()
  tasmota.set_timer(500, show_boot_info)
end

tasmota.when_network_up(network_ready)
