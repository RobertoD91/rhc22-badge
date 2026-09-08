# aw9523_leds.be - RHC22: 7 LED RGB + backlight display via due AW9523B (0x5A, 0x5B)
# Tabelle riprese da main/badge/led.c (enum LED_COLOR { RED, GREEN, BLUE }).
import string
import global

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
      print("AW9523: chip 0x5A/0x5B non trovati (I2C non pronto o template senza I2C)")
      return
    end
    # identico a led_init() del firmware ufficiale
    self.w5a.write(0x5A, 0x11, 0x03, 1)   # GCR: corrente LED = 1/4 Imax
    self.w5b.write(0x5B, 0x11, 0x03, 1)
    self.w5a.write(0x5A, 0x12, 0x80, 1)   # 0x5A: P0_0..P0_6 e P1_0..P1_6 in LED mode
    self.w5a.write(0x5A, 0x13, 0x80, 1)
    self.w5b.write(0x5B, 0x12, 0x00, 1)   # 0x5B: tutta P0 in LED mode
    self.w5b.write(0x5B, 0x13, 0x08, 1)   # 0x5B: P1 in LED mode tranne P1_3
  end
  def ok()
    return self.w5a != nil && self.w5b != nil
  end
  def backlight(level)                    # 0..255 = set_screen_led_backlight()
    if !self.ok() return end
    for reg: [0x20, 0x21, 0x22, 0x23]
      self.w5a.write(0x5A, reg, level, 1)
    end
  end
  def set_led(id, r, g, b)                # id 0..6 (0 = centrale, 6 = in alto), valori 0..255
    if !self.ok() return end
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
global.leds = leds                        # raggiungibile anche dalla console Berry
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
  if size(p) != 4
    tasmota.resp_cmnd_str("uso: AwLed id,r,g,b")
    return
  end
  leds.set_led(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
  tasmota.resp_cmnd_done()
end)

# Pulsanti (richiede SetOption73 1): trigger Button<x>#State, 10 = singola, 3 = tenuto
tasmota.add_rule("Button2#State=10", def () leds.all(232, 11, 96) end)   # UP: LED magenta
tasmota.add_rule("Button1#State=10", def () leds.all(0, 0, 0) end)       # DOWN: LED spenti
tasmota.add_rule("Button2#State=3", def () leds.backlight(255) end)      # UP tenuto
tasmota.add_rule("Button1#State=3", def () leds.backlight(0) end)        # DOWN tenuto
