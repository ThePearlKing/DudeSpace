class_name ArcadeCarts
extends RefCounted
## THE SHELF. Cartridges that ship inside every cabinet, written in the
## console's own Lua against the console's own API -- which means they
## are also worked examples: open any of them in the editor and the code
## that makes them go is right there.
##
## They are ROMs (readonly). Copy one to a floppy if you want to take it
## apart.

static var _shelf: Array = []

static func shelf() -> Array:
	if not _shelf.is_empty():
		return _shelf
	_shelf = [_voidwing(), _soulboard(), _neondrift(), _blockparty(),
		_dudedash(), _demo()]
	for c in _shelf:
		c.readonly = true
	return _shelf


# ------------------------------------------------------------------ art
## Sprites are authored here as rows of letters, one letter per pixel,
## so the art lives next to the code that draws it. A dot is the
## transparent index; everything else is a colour out of the palette.
const INK := {
	".": 0, "W": 1, "k": 72, "g": 71, "G": 73,
	"r": 2, "R": 4, "d": 3, "o": 8, "O": 10, "y": 14, "Y": 16,
	"n": 20, "N": 22, "e": 23, "t": 26, "c": 29, "C": 31,
	"s": 32, "S": 34, "b": 38, "B": 40, "i": 41, "v": 44, "V": 46,
	"u": 47, "m": 50, "p": 53, "P": 55, "w": 56, "T": 59, "a": 11,
	"l": 17, "z": 68, "Z": 70,
}

static func paint(c: ArcadeCart, n: int, rows: Array) -> void:
	var ox := ArcadeCart.spr_x(n)
	var oy := ArcadeCart.spr_y(n)
	for y in mini(16, rows.size()):
		var line: String = rows[y]
		for x in mini(16, line.length()):
			var ch := line[x]
			if not INK.has(ch):
				continue
			c.sheet[(oy + y) * ArcadeCart.SHEET_W + ox + x] = int(INK[ch])

## The shared sprite sheet every built-in draws from.
static func _stock_art(c: ArcadeCart) -> void:
	# 0: the VOIDWING itself
	paint(c, 0, [
		"................",
		".......WW.......",
		"......WSSW......",
		"......sSSs......",
		".....sSSSSs.....",
		".....sSbbSs.....",
		"....ssSbbSss....",
		"...sssSbbSsss...",
		"..sbssSbbSssbs..",
		".sbbssSSSSssbbs.",
		".sbb.sssssss.bs.",
		"..b..soooos..b..",
		".....sOOOOs.....",
		"......oyyo......",
		".......yy.......",
		"................"])
	# 1: fighter
	paint(c, 1, [
		"................",
		"................",
		"...pp......pp...",
		"...ppp....ppp...",
		"....pppmmppp....",
		"....pmmmmmmp....",
		"...pmmWWWWmmp...",
		"..pmmWkkkkWmmp..",
		"..pmmWkrrkWmmp..",
		"...pmmWWWWmmp...",
		"....pmmmmmmp....",
		"....ppp..ppp....",
		"...pp......pp...",
		"................",
		"................",
		"................"])
	# 2: hulk
	paint(c, 2, [
		"................",
		"......vvvv......",
		"....vvVVVVvv....",
		"...vVVuuuuVVv...",
		"..vVVuuuuuuVVv..",
		"..vVuuWWWWuuVv..",
		".vVVuWkkkkWuVVv.",
		".vVuuWkrrkWuuVv.",
		".vVuuWWWWWWuuVv.",
		".vVVuuuuuuuuVVv.",
		"..vVVuuuuuuVVv..",
		"..vvVVuuuuVVvv..",
		"...vv.VVVV.vv...",
		"....v.v..v.v....",
		"................",
		"................"])
	# 3: a burst
	paint(c, 3, [
		"................",
		".......y........",
		"...y..yYy..y....",
		"....y.yYy.y.....",
		"..y..yYYYy..y...",
		"...yyYYoYYyy....",
		"....yYoooYy.....",
		"..yyYooRooYyy...",
		"..yyYooRooYyy...",
		"....yYoooYy.....",
		"...yyYYoYYyy....",
		"..y..yYYYy..y...",
		"....y.yYy.y.....",
		"...y..yYy..y....",
		".......y........",
		"................"])
	# 4: the dude, standing
	paint(c, 4, [
		"................",
		".....TTTTT......",
		"....TTTTTTT.....",
		"....TWkTkWT.....",
		"....TTTTTTT.....",
		".....TTTTT......",
		"......TTT.......",
		"...ccCCCCCcc....",
		"..cccCCCCCccc...",
		"..cc.CCCCC.cc...",
		"..c..CCCCC..c...",
		".....bbbbb......",
		".....bb.bb......",
		"....bb...bb.....",
		"...kkk...kkk....",
		"................"])
	# 5: coin
	paint(c, 5, [
		"................",
		"................",
		".....yyyyy......",
		"...yyYYYYYyy....",
		"..yYYYaaaYYYy...",
		"..yYYaaaaaYYy...",
		".yYYaaWWWaaYYy..",
		".yYaaaWWWaaaYy..",
		".yYaaaWWWaaaYy..",
		".yYYaaWWWaaYYy..",
		"..yYYaaaaaYYy...",
		"..yYYYaaaYYYy...",
		"...yyYYYYYyy....",
		".....yyyyy......",
		"................",
		"................"])
	# 6: crate tile
	paint(c, 6, [
		"TTTTTTTTTTTTTTTT",
		"TwwwwwwwwwwwwwwT",
		"TwWwwwwwwwwwwWwT",
		"TwwwTwwwwwwTwwwT",
		"TwwwwTwwwwTwwwwT",
		"TwwwwwTwwTwwwwwT",
		"TwwwwwwTTwwwwwwT",
		"TwwwwwwTTwwwwwwT",
		"TwwwwwTwwTwwwwwT",
		"TwwwwTwwwwTwwwwT",
		"TwwwTwwwwwwTwwwT",
		"TwWwwwwwwwwwwWwT",
		"TwwwwwwwwwwwwwwT",
		"TwwwwwwwwwwwwwwT",
		"TwwwwwwwwwwwwwwT",
		"TTTTTTTTTTTTTTTT"])
	# 7: ground tile
	paint(c, 7, [
		"nnnnnnnnnnnnnnnn",
		"nNnnnNnnnnNnnnnN",
		"wwwwwwwwwwwwwwww",
		"wwTwwwwwTwwwwwww",
		"wwwwwwwwwwwwTwww",
		"wwwwTwwwwwwwwwww",
		"wwwwwwwwwwwwwwww",
		"wwwwwwwTwwwwwwww",
		"wwwwwwwwwwwwwwww",
		"wwTwwwwwwwwTwwww",
		"wwwwwwwwwwwwwwww",
		"wwwwwwwwwwwwwwww",
		"wwwwTwwwwwwwwwww",
		"wwwwwwwwwwwwwwww",
		"wwwwwwwwwwwwwwww",
		"wwwwwwwwwwwwwwww"])
	# 8: a block, for the puzzle
	paint(c, 8, [
		"cccccccccccccccc",
		"cCCCCCCCCCCCCCCc",
		"cCCCCCCCCCCCCCtc",
		"cCCttttttttttttc",
		"cCtttttttttttttc",
		"cCtttttttttttttc",
		"cCtttttttttttttc",
		"cCtttttttttttttc",
		"cCtttttttttttttc",
		"cCtttttttttttttc",
		"cCtttttttttttttc",
		"cCtttttttttttttc",
		"cCtttttttttttttc",
		"cCtttttttttttttc",
		"ctttttttttttttte",
		"cccccccccccccccc"])
	# 9: star / pickup
	paint(c, 9, [
		"................",
		".......W........",
		"......WYW.......",
		"......WYW.......",
		"..W...YYY...W...",
		"...WWYYYYYWW....",
		"....WYYYYYW.....",
		".WWWYYYYYYYWWW..",
		"....WYYYYYW.....",
		"...WWYYYYYWW....",
		"..W..YYYYY..W...",
		"......WYW.......",
		"......WYW.......",
		".......W........",
		"................",
		"................"])

static func _cart(nm: String, author: String, code: String, res_mode: int = 1) -> ArcadeCart:
	var c := ArcadeCart.new()
	c.name = nm
	c.author = author
	c.code = code
	c.res_mode = res_mode
	_stock_art(c)
	c.song = ChipSound.demo_song().to_dict()
	return c

# ---------------------------------------------------------------------
static func _voidwing() -> ArcadeCart:
	return _cart("VOIDWING", "hangar 7", """
-- VOIDWING -- hold the line over the rift.
-- arrows move, Z fires, X drops a pulse (three of them, use them well)

W, H = res()

function _init()
  ship = {x = W/2, y = H - 40, cool = 0, hp = 3, inv = 0, pulses = 3}
  shots, foes, bits, pops = {}, {}, {}, {}
  score, wave, wave_t, shake, over, best = 0, 0, 0, 0, false, dget(0)
  stars = {}
  for i = 1, 70 do
    add_star(rnd(H))
  end
end

function add_star(y)
  local layer = flr(rnd(3)) + 1
  stars[#stars + 1] = {x = rnd(W), y = y, l = layer}
end

function _update()
  if over then
    if btnp(4) then _init() end
    return
  end
  shake = max(0, shake - 1)
  ship.inv = max(0, ship.inv - 1)

  -- stars keep falling whatever else is happening
  for i = 1, #stars do
    local s = stars[i]
    s.y = s.y + s.l * 0.6
    if s.y > H then s.y = 0 s.x = rnd(W) end
  end

  -- flying
  local sp = 2.4
  if btn(0) then ship.x = ship.x - sp end
  if btn(1) then ship.x = ship.x + sp end
  if btn(2) then ship.y = ship.y - sp end
  if btn(3) then ship.y = ship.y + sp end
  ship.x = mid(8, ship.x, W - 8)
  ship.y = mid(20, ship.y, H - 10)

  -- guns
  ship.cool = max(0, ship.cool - 1)
  if btn(4) and ship.cool <= 0 then
    ship.cool = 6
    shots[#shots + 1] = {x = ship.x - 5, y = ship.y - 6, vy = -6}
    shots[#shots + 1] = {x = ship.x + 5, y = ship.y - 6, vy = -6}
    sfx(0)
  end
  if btnp(5) and ship.pulses > 0 then
    ship.pulses = ship.pulses - 1
    shake = 12
    for i = #foes, 1, -1 do
      kill_foe(i, false)
    end
    sfx(2)
  end

  for i = #shots, 1, -1 do
    local s = shots[i]
    s.y = s.y + s.vy
    if s.y < -4 then table.remove(shots, i) end
  end

  -- waves arrive on a timer that tightens as you survive
  wave_t = wave_t - 1
  if wave_t <= 0 then
    wave = wave + 1
    wave_t = max(30, 90 - wave * 3)
    spawn_wave()
  end

  for i = #foes, 1, -1 do
    local f = foes[i]
    f.t = f.t + 1
    f.y = f.y + f.vy
    f.x = f.x + sin(f.t / 18 + f.seed) * f.sway
    if f.y > H + 10 then
      table.remove(foes, i)
    else
      for j = #shots, 1, -1 do
        local s = shots[j]
        if abs(s.x - f.x) < f.r and abs(s.y - f.y) < f.r then
          table.remove(shots, j)
          f.hp = f.hp - 1
          if f.hp <= 0 then kill_foe(i, true) end
          break
        end
      end
      if ship.inv <= 0 and abs(ship.x - f.x) < f.r + 3
          and abs(ship.y - f.y) < f.r + 3 then
        hurt()
      end
    end
  end

  for i = #bits, 1, -1 do
    local b = bits[i]
    b.x = b.x + b.vx
    b.y = b.y + b.vy
    b.vy = b.vy + 0.12
    b.life = b.life - 1
    if b.life <= 0 then table.remove(bits, i) end
  end
  for i = #pops, 1, -1 do
    pops[i].r = pops[i].r + 2
    pops[i].life = pops[i].life - 1
    if pops[i].life <= 0 then table.remove(pops, i) end
  end
end

function spawn_wave()
  local n = 3 + flr(wave / 2)
  if n > 9 then n = 9 end
  local kind = wave % 4
  for i = 1, n do
    local x = (W / (n + 1)) * i
    foes[#foes + 1] = {
      x = x, y = -10 - i * 6, vy = 0.7 + wave * 0.05,
      sway = (kind == 1) and 1.4 or 0.4, seed = rnd(6), t = 0,
      r = (kind == 3) and 9 or 6, hp = (kind == 3) and 3 or 1,
      c = 2 + (wave % 20) * 3
    }
  end
end

function kill_foe(i, scored)
  local f = foes[i]
  if scored then
    score = score + 10 * f.r
  end
  for k = 1, 8 do
    bits[#bits + 1] = {x = f.x, y = f.y, vx = rnd(4) - 2, vy = rnd(3) - 2,
      life = 20 + rnd(10), c = f.c}
  end
  pops[#pops + 1] = {x = f.x, y = f.y, r = 2, life = 8}
  table.remove(foes, i)
  score = score + 10
  sfx(1)
end

function hurt()
  ship.hp = ship.hp - 1
  ship.inv = 90
  shake = 16
  sfx(3)
  if ship.hp <= 0 then
    over = true
    if score > best then best = score dset(0, score) end
  end
end

function _draw()
  local ox, oy = 0, 0
  if shake > 0 then ox = rnd(shake) - shake/2 oy = rnd(shake) - shake/2 end
  camera(flr(ox), flr(oy))
  cls(0)
  -- starfield, three depths, three greys
  for i = 1, #stars do
    local s = stars[i]
    pset(flr(s.x), flr(s.y), s.l == 3 and 1 or (s.l == 2 and 73 or 72))
  end
  -- the rift you are defending
  rectfill(0, H - 6, W, H, 41)
  rectfill(0, H - 4, W, H, 44)

  for i = 1, #foes do
    local f = foes[i]
    local x, y = flr(f.x), flr(f.y)
    -- the hulks are the big ones; everything else flies a fighter
    spr(f.hp > 1 and 2 or 1, x - 8, y - 8)
  end
  for i = 1, #shots do
    local s = shots[i]
    rectfill(flr(s.x), flr(s.y), flr(s.x) + 1, flr(s.y) + 4, 14)
    pset(flr(s.x), flr(s.y) - 1, 1)
  end
  for i = 1, #bits do
    local b = bits[i]
    pset(flr(b.x), flr(b.y), b.c)
  end
  for i = 1, #pops do
    local o = pops[i]
    if o.life > 4 then spr(3, flr(o.x) - 8, flr(o.y) - 8) end
    circ(flr(o.x), flr(o.y), o.r, 1)
  end

  if ship.inv <= 0 or frames() % 6 < 3 then draw_ship() end

  camera(0, 0)
  print("SCORE " .. score, 6, 6, 1)
  print("BEST " .. best, W - 80, 6, 71)
  for i = 1, ship.hp do
    circfill(8 + i * 10, 18, 3, 2)
  end
  for i = 1, ship.pulses do
    rectfill(W - 20 - i * 8, 15, W - 15 - i * 8, 20, 29)
  end
  print("WAVE " .. wave, W/2 - 20, 6, 32)

  if over then
    rectfill(0, H/2 - 30, W, H/2 + 26, 0)
    printc("THE RIFT TAKES IT", W/2, H/2 - 22, 2, 5)
    printc("score " .. score, W/2, H/2 + 2, 1, 1)
    if frames() % 60 < 34 then
      printc("Z TO FLY AGAIN", W/2, H/2 + 14, 14, 0)
    end
  end
end

function draw_ship()
  local x, y = flr(ship.x), flr(ship.y)
  spr(0, x - 8, y - 8)
  -- engine flare, flickering, drawn under the hull
  local f = 3 + flr(rnd(3))
  tri(x - 3, y + 6, x + 3, y + 6, x, y + 6 + f, 8)
  tri(x - 1, y + 6, x + 1, y + 6, x, y + 6 + f + 2, 14)
end
""")


# ---------------------------------------------------------------------
static func _soulboard() -> ArcadeCart:
	return _cart("SOUL BOARD", "a friend of the dudes", """
-- SOUL BOARD -- their turn, then yours. Stay inside the box.
-- arrows move your soul, Z attacks when the bar swings past the middle.

W, H = res()
BX, BY, BW, BH = 0, 0, 190, 120

function _init()
  BX = flr(W/2 - BW/2)
  BY = H - BH - 34
  soul = {x = W/2, y = BY + BH/2, hp = 20, maxhp = 20, iframes = 0}
  foe = {hp = 120, maxhp = 120, shake = 0, mood = 1}
  shots = {}
  phase, ptime, wave = "them", 0, 0
  bar, bar_dir, hits, over = 0, 1, 0, ""
  msg, msg_t = "THEY LOOK AT YOU FUNNY", 90
end

function _update()
  if over ~= "" then
    if btnp(4) then _init() end
    return
  end
  if msg_t > 0 then msg_t = msg_t - 1 end
  foe.shake = max(0, foe.shake - 1)
  soul.iframes = max(0, soul.iframes - 1)

  if phase == "them" then
    update_them()
  else
    update_you()
  end
end

function update_them()
  ptime = ptime + 1
  local sp = 1.5
  if btn(0) then soul.x = soul.x - sp end
  if btn(1) then soul.x = soul.x + sp end
  if btn(2) then soul.y = soul.y - sp end
  if btn(3) then soul.y = soul.y + sp end
  soul.x = mid(BX + 5, soul.x, BX + BW - 5)
  soul.y = mid(BY + 5, soul.y, BY + BH - 5)

  -- three attacks, and they rotate
  local kind = wave % 3
  if kind == 0 and ptime % 14 == 0 then
    -- rain from the top of the board
    for i = 1, 3 do
      local x = BX + 10 + rnd(BW - 20)
      shots[#shots+1] = {x = x, y = BY - 4, vx = 0, vy = 1.1, r = 3, c = 53}
    end
  elseif kind == 1 and ptime % 20 == 0 then
    -- a spiral out of the middle
    for i = 0, 5 do
      local a = ptime * 0.08 + i * 1.05
      shots[#shots+1] = {x = BX + BW/2, y = BY + BH/2,
        vx = cos(a) * 0.95, vy = sin(a) * 0.95, r = 3, c = 44}
    end
  elseif kind == 2 and ptime % 26 == 0 then
    -- a wall with a gap you have to find
    local gap = 20 + rnd(BW - 70)
    for x = 4, BW - 4, 10 do
      if x < gap or x > gap + 34 then
        shots[#shots+1] = {x = BX + x, y = BY - 4, vx = 0, vy = 1.35, r = 3, c = 29}
      end
    end
  end

  for i = #shots, 1, -1 do
    local s = shots[i]
    s.x = s.x + s.vx
    s.y = s.y + s.vy
    if s.x < BX - 8 or s.x > BX + BW + 8 or s.y < BY - 12 or s.y > BY + BH + 8 then
      table.remove(shots, i)
    elseif soul.iframes <= 0 then
      local dx, dy = s.x - soul.x, s.y - soul.y
      if dx*dx + dy*dy < (s.r + 3) * (s.r + 3) then
        soul.hp = soul.hp - 2
        soul.iframes = 40
        sfx(1)
        say("OW")
        if soul.hp <= 0 then over = "lost" end
      end
    end
  end

  if ptime > 380 then
    phase = "you"
    ptime = 0
    shots = {}
    bar, bar_dir = 0, 1
    say("YOUR TURN")
  end
end

function update_you()
  bar = bar + bar_dir * 3.2
  if bar > 100 then bar, bar_dir = 100, -1 end
  if bar < 0 then bar, bar_dir = 0, 1 end
  if btnp(4) then
    -- the closer to the middle, the harder it lands
    local acc = 1 - abs(bar - 50) / 50
    local dmg = flr(4 + acc * acc * 26)
    foe.hp = max(0, foe.hp - dmg)
    foe.shake = 14
    hits = hits + 1
    sfx(2)
    say(acc > 0.9 and "PERFECT  -" .. dmg or "-" .. dmg)
    if foe.hp <= 0 then
      over = "won"
      return
    end
    phase = "them"
    ptime = 0
    wave = wave + 1
    soul.x, soul.y = BX + BW/2, BY + BH/2
  end
end

function say(t)
  msg, msg_t = t, 80
end

function _draw()
  cls(0)
  -- the thing you are fighting: a shape that breathes
  local ox = 0
  if foe.shake > 0 then ox = rnd(foe.shake) - foe.shake/2 end
  local fy = 44 + sin(t() * 1.6) * 3
  camera(flr(ox), 0)
  local r = 26 + sin(t() * 2.2) * 2
  circfill(W/2, flr(fy), flr(r), 47)
  circfill(W/2, flr(fy), flr(r) - 4, 49)
  for i = 0, 7 do
    local a = t() * 0.6 + i * 0.78
    circfill(flr(W/2 + cos(a) * (r + 8)), flr(fy + sin(a) * (r * 0.6 + 6)), 3, 44)
  end
  -- eyes
  circfill(flr(W/2 - 9), flr(fy - 4), 4, 1)
  circfill(flr(W/2 + 9), flr(fy - 4), 4, 1)
  circfill(flr(W/2 - 9 + sin(t()) * 2), flr(fy - 4), 2, 0)
  circfill(flr(W/2 + 9 + sin(t()) * 2), flr(fy - 4), 2, 0)
  camera(0, 0)

  -- their health, along the top
  rectfill(20, 12, W - 20, 20, 69)
  rectfill(20, 12, 20 + flr((W - 40) * foe.hp / foe.maxhp), 20, 2)
  print("THEM", 20, 3, 71)

  -- the board
  rectfill(BX - 3, BY - 3, BX + BW + 3, BY + BH + 3, 1)
  rectfill(BX, BY, BX + BW, BY + BH, 0)
  for i = 1, #shots do
    local s = shots[i]
    circfill(flr(s.x), flr(s.y), s.r, s.c)
    circfill(flr(s.x), flr(s.y), s.r - 2, s.c + 2)
  end
  if soul.iframes % 6 < 3 then draw_soul() end

  -- your health
  print("HP", 20, H - 24, 71)
  rectfill(38, H - 24, 38 + soul.maxhp * 3, H - 17, 69)
  rectfill(38, H - 24, 38 + max(0, soul.hp) * 3, H - 17, 14)
  print(soul.hp .. "/" .. soul.maxhp, 44 + soul.maxhp * 3, H - 24, 1)

  if phase == "you" and over == "" then
    -- the attack swing
    rectfill(BX, BY + BH + 8, BX + BW, BY + BH + 20, 69)
    rectfill(BX + BW/2 - 3, BY + BH + 8, BX + BW/2 + 3, BY + BH + 20, 20)
    local px = BX + 4 + flr((BW - 8) * bar / 100)
    rectfill(px - 2, BY + BH + 6, px + 2, BY + BH + 22, 1)
    print("Z WHEN IT IS IN THE MIDDLE", BX, BY + BH + 24, 32)
  end

  if msg_t > 0 then
    printc(msg, W/2, BY - 16, 1, 1)
  end
  if over ~= "" then
    rectfill(0, H/2 - 20, W, H/2 + 18, 0)
    if over == "won" then
      printc("IT SITS DOWN, IMPRESSED", W/2, H/2 - 12, 20, 5)
    else
      printc("YOU SIT DOWN INSTEAD", W/2, H/2 - 12, 2, 5)
    end
    printc("Z to go again", W/2, H/2 + 6, 1)
  end
end

function draw_soul()
  local x, y = flr(soul.x), flr(soul.y)
  -- a heart, drawn the only honest way: by hand, in pixels
  for i = -3, 3 do
    local h = 3 - abs(i)
    line(x + i, y - 2 - h, x + i, y + 2 - abs(i), 2)
  end
  pset(x - 1, y - 3, 4)
  pset(x + 1, y - 3, 4)
end
""")

# ---------------------------------------------------------------------
static func _neondrift() -> ArcadeCart:
	return _cart("NEON DRIFT", "the dudes", """
-- NEON DRIFT -- three laps, one road, no brakes worth using.
-- left/right steer, Z accelerate, X brake.

W, H = res()
HORIZON = 0
SEGN = 2400            -- segments in one lap: about twelve seconds flat out

function _init()
  HORIZON = flr(H * 0.42)
  -- the track: long straights with real bends between them, built once
  road = {}
  local bends = {{240, 600, 0.9}, {840, 1140, -1.3}, {1320, 1560, 0.6},
                 {1800, 2220, -0.8}}
  for i = 1, SEGN do
    local curve = 0
    for b = 1, #bends do
      local bd = bends[b]
      if i > bd[1] and i < bd[2] then curve = bd[3] end
    end
    road[i] = {curve = curve}
  end
  car = {z = 0, x = 0, speed = 0, lap = 1, best = dget(0), t = 0}
  rivals = {}
  for i = 1, 5 do
    rivals[i] = {z = i * 240 + 120, x = (i % 2 == 0) and 0.4 or -0.4,
      speed = 2.4 + rnd(0.5), c = 2 + (i * 7) % 20 * 3}
  end
  laps_done, done = 0, false
  make_bands()
end

function seg(i)
  return road[(flr(i) % SEGN) + 1]
end

function _update()
  if done then
    if btnp(4) then _init() end
    return
  end
  car.t = car.t + 1/60

  local acc = 0.035
  if btn(4) then car.speed = car.speed + acc end
  if btn(5) then car.speed = car.speed - 0.08 end
  car.speed = car.speed * 0.995
  car.speed = mid(0, car.speed, 4.2)

  local s = seg(car.z)
  local steer = 0.028 * min(1, car.speed)
  if btn(0) then car.x = car.x - steer end
  if btn(1) then car.x = car.x + steer end
  -- the bend pushes you out of it
  car.x = car.x - s.curve * car.speed * 0.004
  car.x = mid(-1.3, car.x, 1.3)
  if abs(car.x) > 1 then
    car.speed = car.speed * 0.93       -- off the road, into the dirt
    if frames() % 4 == 0 then sfx(5) end
  end

  car.z = car.z + car.speed
  if flr(car.z / SEGN) > laps_done then
    laps_done = flr(car.z / SEGN)
    car.lap = laps_done + 1
    sfx(7)
    if car.lap > 3 then
      done = true
      if car.best == 0 or car.t < car.best then
        car.best = car.t
        dset(0, car.t)
      end
    end
  end

  for i = 1, #rivals do
    local r = rivals[i]
    r.z = r.z + r.speed
    r.x = r.x + sin(r.z * 0.05) * 0.004
  end
end

-- Classic road projection: one over distance. The camera sits CAM_H
-- above the tarmac looking down a road ROAD_W wide, and each segment is
-- SEG_L further away than the last.
-- Classic road projection: one over distance. The camera sits CAM_H
-- above the tarmac looking down a road ROAD_W wide, and each segment is
-- SEG_L further away than the last.
CAM_H, CAM_D, SEG_L, ROAD_W = 1500, 0.84, 200, 900
BANDS = 26

function make_bands()
  -- the projection tables are built ONCE and refilled every frame.
  -- Allocating twenty-six tables a frame is the sort of thing that
  -- turns a smooth racer into a slideshow.
  P = {}
  for i = 1, BANDS + 1 do
    P[i] = {y = 0, w = 0, x = 0, band = false}
  end
end

function _draw()
  local w2, h2 = W / 2, flr(H / 2)
  local camd, camh, segl, roadw = CAM_D, CAM_H, SEG_L, ROAD_W
  local cz, cx0 = car.z, car.x
  cls(41)
  -- sky and a striped sun on the horizon
  local sunx, suny = flr(W * 0.72), h2 - 30
  circfill(sunx, suny, 24, 8)
  circfill(sunx, suny, 20, 14)
  for i = 0, 9 do
    rectfill(sunx - 26, suny - 26 + i * 6, sunx + 26, suny - 24 + i * 6, 41)
  end
  rectfill(0, h2, W, H, 65)

  local base = flr(cz)
  local pct = cz - base
  local x, dx = 0, 0
  for i = 1, BANDS do
    local sg = road[((base + i) % SEGN) + 1]
    dx = dx + sg.curve * 2.6
    x = x + dx
    local scale = camd / ((i - pct) * segl)
    local p = P[i]
    p.y = flr(h2 + scale * camh * h2)
    p.w = flr(scale * roadw * w2)
    p.x = flr(w2 + scale * (x - cx0 * roadw) * w2)
    p.band = (flr((base + i) / 3) % 2 == 0)
  end
  for i = BANDS - 1, 1, -1 do
    local far, near = P[i + 1], P[i]
    local fy, ny = far.y, near.y
    if ny - fy >= 1 and fy < H then
      local fw, nw = far.w, near.w
      local fx, nx = far.x, near.x
      if far.band then
        rectfill(0, fy, W, ny, 66)
        quad(fx - fw, fx + fw, fy, nx - nw, nx + nw, ny, 68)
        quad(fx - fw - 6, fx - fw, fy, nx - nw - 9, nx - nw, ny, 2)
        quad(fx + fw, fx + fw + 6, fy, nx + nw, nx + nw + 9, ny, 2)
        if fw > 4 then
          quad(fx - 2, fx + 2, fy, nx - 3, nx + 3, ny, 1)
        end
      else
        quad(fx - fw, fx + fw, fy, nx - nw, nx + nw, ny, 69)
        quad(fx - fw - 6, fx - fw, fy, nx - nw - 9, nx - nw, ny, 1)
        quad(fx + fw, fx + fw + 6, fy, nx + nw, nx + nw + 9, ny, 1)
      end
    end
  end

  for i = 1, #rivals do
    local r = rivals[i]
    local dz = (r.z - cz) % SEGN
    if dz > 1 and dz < BANDS then
      local pp = P[flr(dz)]
      if pp and pp.y < H and pp.w > 2 then
        local sz = max(2, flr(pp.w * 0.22))
        local sx = flr(pp.x + r.x * pp.w * 0.7)
        rectfill(sx - sz, pp.y - sz, sx + sz, pp.y, r.c)
        rectfill(sx - sz, pp.y - sz, sx + sz, pp.y - sz + max(1, flr(sz / 3)),
          r.c + 2)
      end
    end
  end

  draw_car()

  print("LAP " .. min(car.lap, 3) .. "/3", 8, 8, 1)
  print("TIME " .. flr(car.t * 10) / 10, 8, 20, 14)
  if car.best > 0 then print("BEST " .. flr(car.best * 10) / 10, 8, 32, 71) end
  local sp = flr(car.speed * 62)
  print(sp .. " KPH", W - 70, 8, sp > 200 and 2 or 1)
  rectfill(W - 70, 20, W - 70 + flr(car.speed * 16), 26, 20)
  rect(W - 71, 19, W - 3, 27, 71)

  if done then
    rectfill(0, h2 - 24, W, h2 + 20, 0)
    printc("THREE LAPS, DONE", w2, h2 - 16, 14, 5)
    printc("time " .. flr(car.t * 10) / 10 .. "s  -  Z to run it again",
      w2, h2 + 4, 1)
  end
end

-- a trapezoid, as the two triangles the console gives us
function quad(x1a, x1b, y1, x2a, x2b, y2, c)
  tri(x1a, y1, x1b, y1, x2b, y2, c)
  tri(x1a, y1, x2b, y2, x2a, y2, c)
end

function draw_car()
  local cx, cy = flr(W/2), H - 34
  local lean = flr(car.x * 6)
  -- shadow, body, glass, lights, and a wobble that grows with speed
  local wob = flr(sin(t() * 18) * car.speed * 0.4)
  rectfill(cx - 30, cy + 12, cx + 30, cy + 16, 0)
  rectfill(cx - 28 + lean, cy - 6 + wob, cx + 28 + lean, cy + 12 + wob, 2)
  rectfill(cx - 22 + lean, cy - 14 + wob, cx + 22 + lean, cy - 4 + wob, 4)
  rectfill(cx - 16 + lean, cy - 12 + wob, cx + 16 + lean, cy - 6 + wob, 32)
  rectfill(cx - 30 + lean, cy + 2 + wob, cx - 24 + lean, cy + 10 + wob, 0)
  rectfill(cx + 24 + lean, cy + 2 + wob, cx + 30 + lean, cy + 10 + wob, 0)
  if car.speed > 2.5 then
    for i = 1, 3 do
      pset(cx - 30 + lean - i * 4, cy + 8 + wob + rnd(3), 8)
      pset(cx + 30 + lean + i * 4, cy + 8 + wob + rnd(3), 8)
    end
  end
end
""")

# ---------------------------------------------------------------------
static func _blockparty() -> ArcadeCart:
	return _cart("BLOCK PARTY", "the dudes", """
-- BLOCK PARTY -- clear lines, chain them, keep the floor away.
-- arrows move and drop, Z rotates, X slams.

W, H = res()
CW, CH = 10, 18
CELL = 12
OX, OY = 0, 0

SHAPES = {
  {{0,0},{1,0},{2,0},{3,0}},
  {{0,0},{1,0},{0,1},{1,1}},
  {{0,0},{1,0},{2,0},{1,1}},
  {{0,0},{1,0},{1,1},{2,1}},
  {{1,0},{2,0},{0,1},{1,1}},
  {{0,0},{0,1},{1,1},{2,1}},
  {{2,0},{0,1},{1,1},{2,1}},
}
COLS = {29, 14, 47, 8, 20, 2, 35}

function _init()
  OX = flr(W/2 - CW*CELL/2)
  OY = flr(H/2 - CH*CELL/2) + 6
  grid = {}
  for y = 1, CH do
    grid[y] = {}
    for x = 1, CW do grid[y][x] = 0 end
  end
  score, lines_done, level, over = 0, 0, 1, false
  best = dget(0)
  fall, fall_t = 30, 0
  flash, flash_t, chain = {}, 0, 0
  new_piece()
end

function new_piece()
  local n = flr(rnd(7)) + 1
  piece = {n = n, cells = {}, x = 4, y = 1, rot = 0}
  for i, c in ipairs(SHAPES[n]) do
    piece.cells[i] = {c[1], c[2]}
  end
  if hits(piece.x, piece.y, piece.cells) then
    over = true
    if score > best then best = score dset(0, score) end
  end
end

function hits(px, py, cells)
  for i, c in ipairs(cells) do
    local x, y = px + c[1], py + c[2]
    if x < 1 or x > CW or y > CH then return true end
    if y >= 1 and grid[y][x] ~= 0 then return true end
  end
  return false
end

function rotate()
  local out = {}
  for i, c in ipairs(piece.cells) do
    out[i] = {-c[2], c[1]}
  end
  -- pull it back inside the well if the spin pushed it out
  for kick = 0, 2 do
    for s = -1, 1, 2 do
      if not hits(piece.x + kick * s, piece.y, out) then
        piece.cells = out
        piece.x = piece.x + kick * s
        sfx(0)
        return
      end
    end
  end
end

function lock_piece()
  for i, c in ipairs(piece.cells) do
    local x, y = piece.x + c[1], piece.y + c[2]
    if y >= 1 then grid[y][x] = piece.n end
  end
  local cleared = 0
  for y = CH, 1, -1 do
    local full = true
    for x = 1, CW do
      if grid[y][x] == 0 then full = false break end
    end
    if full then
      cleared = cleared + 1
      flash[#flash + 1] = y
      for yy = y, 2, -1 do
        for x = 1, CW do grid[yy][x] = grid[yy-1][x] end
      end
      for x = 1, CW do grid[1][x] = 0 end
      y = y + 1
    end
  end
  if cleared > 0 then
    chain = chain + 1
    flash_t = 12
    lines_done = lines_done + cleared
    score = score + (cleared * cleared) * 100 * chain
    level = 1 + flr(lines_done / 8)
    fall = max(6, 30 - level * 2)
    sfx(1)
  else
    chain = 0
    sfx(2)
  end
  new_piece()
end

function _update()
  if over then
    if btnp(4) then _init() end
    return
  end
  flash_t = max(0, flash_t - 1)
  if flash_t == 0 then flash = {} end

  if btnp(0) and not hits(piece.x - 1, piece.y, piece.cells) then
    piece.x = piece.x - 1
  end
  if btnp(1) and not hits(piece.x + 1, piece.y, piece.cells) then
    piece.x = piece.x + 1
  end
  if btnp(4) then rotate() end
  if btnp(5) then
    while not hits(piece.x, piece.y + 1, piece.cells) do
      piece.y = piece.y + 1
      score = score + 2
    end
    lock_piece()
    return
  end

  fall_t = fall_t + (btn(3) and 4 or 1)
  if fall_t >= fall then
    fall_t = 0
    if hits(piece.x, piece.y + 1, piece.cells) then
      lock_piece()
    else
      piece.y = piece.y + 1
    end
  end
end

function cell(x, y, n, ghost)
  local px, py = OX + (x-1) * CELL, OY + (y-1) * CELL
  local c = COLS[n]
  if ghost then
    rect(px, py, px + CELL - 2, py + CELL - 2, c + 1)
    return
  end
  rectfill(px, py, px + CELL - 2, py + CELL - 2, c)
  rectfill(px + 1, py + 1, px + CELL - 4, py + 2, c + 2)
  rectfill(px + CELL - 4, py + 2, px + CELL - 2, py + CELL - 2, c + 1)
end

function _draw()
  cls(69)
  -- well
  rectfill(OX - 4, OY - 4, OX + CW*CELL + 2, OY + CH*CELL + 2, 0)
  rect(OX - 4, OY - 4, OX + CW*CELL + 2, OY + CH*CELL + 2, 32)
  for y = 1, CH do
    for x = 1, CW do
      if grid[y][x] ~= 0 then cell(x, y, grid[y][x], false) end
    end
  end
  for i = 1, #flash do
    local y = flash[i]
    rectfill(OX, OY + (y-1)*CELL, OX + CW*CELL - 2, OY + y*CELL - 2, 1)
  end
  if not over then
    -- ghost first, then the live piece over it
    local gy = piece.y
    while not hits(piece.x, gy + 1, piece.cells) do gy = gy + 1 end
    for i, c in ipairs(piece.cells) do
      cell(piece.x + c[1], gy + c[2], piece.n, true)
    end
    for i, c in ipairs(piece.cells) do
      if piece.y + c[2] >= 1 then
        cell(piece.x + c[1], piece.y + c[2], piece.n, false)
      end
    end
  end
  printc("BLOCK PARTY", W/2, 6, 1, 2)
  print("SCORE", 12, 30, 71)
  print(score, 12, 42, 14, 1)
  print("LINES", 12, 62, 71)
  print(lines_done, 12, 74, 1)
  print("LEVEL", 12, 94, 71)
  print(level, 12, 106, 29)
  print("BEST", 12, 126, 71)
  print(best, 12, 138, 8)
  if chain > 1 then
    print("CHAIN x" .. chain, W - 90, 40, 2, 1)
  end
  if over then
    rectfill(OX - 4, OY + 60, OX + CW*CELL + 2, OY + 110, 0)
    printc("FLOOR REACHED", OX + CW*CELL/2, OY + 68, 2, 1)
    printc("Z AGAIN", OX + CW*CELL/2, OY + 88, 14, 0)
  end
end
""")

# ---------------------------------------------------------------------
static func _dudedash() -> ArcadeCart:
	return _cart("DUDE DASH", "the dudes", """
-- DUDE DASH -- a runner with weight. build speed, keep it.
-- Z jumps (hold for height), X dashes, arrows lean.

W, H = res()
GROUND = 0

function _init()
  GROUND = H - 40
  p = {x = 60, y = GROUND, vx = 0, vy = 0, on = true, face = 1,
       dash = 0, dash_cd = 0, jump_hold = 0}
  cam, dist, best, over = 0, 0, dget(0), false
  blocks, coins, sparks = {}, {}, {}
  seed_world(0)
  score = 0
end

function seed_world(from)
  for i = 0, 40 do
    local x = from + 220 + i * 130 + rnd(60)
    local w = 40 + rnd(70)
    local h = 14 + rnd(46)
    blocks[#blocks + 1] = {x = x, y = GROUND - h, w = w, h = h}
    if rnd(1) < 0.75 then
      coins[#coins + 1] = {x = x + w/2, y = GROUND - h - 22, got = false,
        bob = rnd(6)}
    end
  end
end

function _update()
  if over then
    if btnp(4) then _init() end
    return
  end
  -- run: hold a direction to build speed, let go and it bleeds off
  local acc = 0.3
  if btn(1) then p.vx = p.vx + acc p.face = 1
  elseif btn(0) then p.vx = p.vx - acc p.face = -1
  else p.vx = p.vx * 0.9 end
  p.vx = mid(-5.2, p.vx, 5.2)

  -- jump with a real hold window, so a tap is a hop
  if btnp(4) and p.on then
    p.vy = -6.2
    p.on = false
    p.jump_hold = 10
    sfx(0)
  end
  if btn(4) and p.jump_hold > 0 then
    p.vy = p.vy - 0.38
    p.jump_hold = p.jump_hold - 1
  else
    p.jump_hold = 0
  end

  p.dash_cd = max(0, p.dash_cd - 1)
  if btnp(5) and p.dash_cd <= 0 then
    p.dash = 10
    p.dash_cd = 50
    sfx(2)
  end
  if p.dash > 0 then
    p.dash = p.dash - 1
    p.vx = p.face * 7
    for i = 1, 2 do
      sparks[#sparks + 1] = {x = p.x, y = p.y - rnd(12), vx = -p.face * rnd(2),
        vy = rnd(2) - 1, life = 14, c = 29}
    end
  end

  p.vy = p.vy + 0.42
  p.x = p.x + p.vx
  p.y = p.y + p.vy

  -- ground and platforms
  p.on = false
  if p.y >= GROUND then p.y = GROUND p.vy = 0 p.on = true end
  for i = 1, #blocks do
    local b = blocks[i]
    if p.x + 6 > b.x and p.x - 6 < b.x + b.w then
      if p.vy >= 0 and p.y >= b.y - 2 and p.y <= b.y + 14 then
        p.y = b.y
        p.vy = 0
        p.on = true
      end
    end
  end

  for i = 1, #coins do
    local c = coins[i]
    if not c.got and abs(c.x - p.x) < 12 and abs(c.y - p.y + 8) < 14 then
      c.got = true
      score = score + 25
      sfx(1)
      for k = 1, 6 do
        sparks[#sparks + 1] = {x = c.x, y = c.y, vx = rnd(3) - 1.5,
          vy = -rnd(2), life = 18, c = 14}
      end
    end
  end

  for i = #sparks, 1, -1 do
    local s = sparks[i]
    s.x = s.x + s.vx
    s.y = s.y + s.vy
    s.life = s.life - 1
    if s.life <= 0 then table.remove(sparks, i) end
  end

  cam = cam + (p.x - 120 - cam) * 0.12
  if p.x > dist then dist = p.x score = score + 1 end
  if p.x < cam - 30 then
    over = true
    if score > best then best = score dset(0, score) end
  end
  if #blocks > 0 and p.x > blocks[#blocks].x - 800 then seed_world(p.x) end
end

function paint_sky()
  -- the background layer is painted ONCE and then scrolled by the
  -- hardware; repainting hills every frame would be paying twice
  layer(0)
  cls(41)
  for i = 0, 8 do
    local hx = i * 90
    tri(hx, H, hx + 60, H - 30 - (i % 4) * 14, hx + 120, H, 44)
  end
  for i = 0, 12 do
    local hx = i * 60
    tri(hx, H, hx + 40, H - 22 - (i % 3) * 10, hx + 80, H, 43)
  end
  for i = 1, 40 do
    pset(flr(rnd(W)), flr(rnd(H - 60)), 1)
  end
  layer(1)
  sky_painted = true
end

function _draw()
  if not sky_painted then paint_sky() end
  bgscroll(flr(cam * 0.35) % W, 0)
  cls(255)
  camera(flr(cam), 0)
  for gx = flr(cam / 16) * 16, flr(cam) + W, 16 do
    spr(7, gx, GROUND)
    spr(7, gx, GROUND + 16)
  end
  for i = 1, #blocks do
    local b = blocks[i]
    if b.x > cam - 100 and b.x < cam + W + 40 then
      -- crates stacked down to the ground line, sixteen at a time
      for ky = b.y, GROUND - 8, 16 do
        for kx = b.x, b.x + b.w - 8, 16 do
          spr(6, flr(kx), flr(ky))
        end
      end
    end
  end
  for i = 1, #coins do
    local c = coins[i]
    if not c.got and c.x > cam - 20 and c.x < cam + W + 20 then
      local y = c.y + sin(t() * 3 + c.bob) * 3
      spr(5, flr(c.x) - 8, flr(y) - 8)
    end
  end
  for i = 1, #sparks do
    local s = sparks[i]
    pset(flr(s.x), flr(s.y), s.c)
  end
  draw_dude()
  camera(0, 0)
  print("SCORE " .. score, 6, 6, 1)
  print("BEST " .. best, W - 90, 6, 71)
  local sp = flr(abs(p.vx) * 10)
  rectfill(6, 18, 6 + sp, 22, sp > 60 and 2 or 29)
  rect(5, 17, 82, 23, 71)
  if p.dash_cd == 0 then print("X DASH READY", 6, 28, 20) end
  if over then
    rectfill(0, H/2 - 24, W, H/2 + 20, 0)
    printc("LEFT BEHIND", W/2, H/2 - 16, 2, 5)
    printc("score " .. score .. "  -  Z to run again", W/2, H/2 + 6, 1)
  end
end

function draw_dude()
  local x, y = flr(p.x), flr(p.y)
  -- the sprite leans with the run, and bobs on every other stride
  local bob = 0
  if p.on and abs(p.vx) > 0.5 then
    bob = flr(abs(sin(dist * 0.09)) * 2)
  end
  spr(4, x - 8, y - 16 - bob, 1, 1, p.face < 0)
  if p.dash > 0 then
    circ(x, y - 8, 10 + p.dash, 29)
    for k = 1, 3 do
      spr(4, x - 8 - p.face * k * 5, y - 16, 1, 1, p.face < 0)
    end
  end
end
""")

# ---------------------------------------------------------------------
static func _demo() -> ArcadeCart:
	return _cart("API TOUR", "the manual", """
-- API TOUR -- every drawing call the console has, on one screen.
-- arrows change page, Z cycles the font.

W, H = res()
page, fontn = 1, 0
PAGES = 3

function _init() end

function _update()
  if btnp(1) then page = page % PAGES + 1 end
  if btnp(0) then page = (page - 2) % PAGES + 1 end
  if btnp(4) then fontn = (fontn + 1) % 6 end
end

function _draw()
  cls(0)
  font(fontn)
  if page == 1 then
    printc("SHAPES", W/2, 6, 14, 5)
    for i = 0, 23 do
      local c = 2 + i * 3
      rectfill(20 + (i % 8) * 40, 40 + flr(i / 8) * 30,
               50 + (i % 8) * 40, 62 + flr(i / 8) * 30, c)
      rectfill(20 + (i % 8) * 40, 40 + flr(i / 8) * 30,
               50 + (i % 8) * 40, 46 + flr(i / 8) * 30, c + 2)
      rectfill(20 + (i % 8) * 40, 56 + flr(i / 8) * 30,
               50 + (i % 8) * 40, 62 + flr(i / 8) * 30, c + 1)
    end
    print("every hue, with its light and its dark", 20, H - 30, 1)
  elseif page == 2 then
    printc("MOTION", W/2, 6, 29, 5)
    for i = 1, 60 do
      local a = t() * 2 + i * 0.1
      local r = 30 + i
      circfill(flr(W/2 + cos(a) * r), flr(H/2 + sin(a * 1.3) * r * 0.5),
        2, 2 + (i % 24) * 3)
    end
    line(0, H/2, W, H/2, 71)
  else
    printc("TYPE", W/2, 6, 8, 5)
    local names = {"SYS", "BOLD", "WIDE", "TALL", "SLANT", "HUGE"}
    local y = 30
    for i = 0, 5 do
      print("Dude-16 " .. names[i+1], 20, y, 1, i)
      y = y + 22
    end
  end
  print("page " .. page .. "/" .. PAGES .. "   arrows: page   Z: font " .. fontn,
    6, H - 12, 71, 0)
end
""")
