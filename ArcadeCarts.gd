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
	_shelf = [_voidwing(), _blockparty(), _dudedash(), _demo()]
	for c in _shelf:
		c.readonly = true
	return _shelf

static func _cart(nm: String, author: String, code: String, res_mode: int = 1) -> ArcadeCart:
	var c := ArcadeCart.new()
	c.name = nm
	c.author = author
	c.code = code
	c.res_mode = res_mode
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
    circfill(x, y, f.r, f.c)
    circfill(x, y - 2, f.r - 3, f.c + 2)
    line(x - f.r, y + 2, x, y + f.r, f.c + 1)
    line(x + f.r, y + 2, x, y + f.r, f.c + 1)
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
    circ(flr(pops[i].x), flr(pops[i].y), pops[i].r, 1)
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
  tri(x, y - 9, x - 7, y + 6, x + 7, y + 6, 32)
  tri(x, y - 6, x - 4, y + 4, x + 4, y + 4, 34)
  rectfill(x - 1, y - 10, x + 1, y - 4, 1)
  -- engine flare, flickering
  local f = 3 + flr(rnd(3))
  tri(x - 3, y + 6, x + 3, y + 6, x, y + 6 + f, 8)
  tri(x - 1, y + 6, x + 1, y + 6, x, y + 6 + f + 2, 14)
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
  local acc = 0.42
  if btn(1) then p.vx = p.vx + acc p.face = 1
  elseif btn(0) then p.vx = p.vx - acc p.face = -1
  else p.vx = p.vx * 0.92 end
  p.vx = mid(-7.5, p.vx, 7.5)

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
    p.dash_cd = 40
    sfx(2)
  end
  if p.dash > 0 then
    p.dash = p.dash - 1
    p.vx = p.face * 9
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
  rectfill(flr(cam), GROUND + 10, flr(cam) + W, H, 65)
  rectfill(flr(cam), GROUND + 10, flr(cam) + W, GROUND + 13, 67)
  for i = 1, #blocks do
    local b = blocks[i]
    if b.x > cam - 100 and b.x < cam + W + 40 then
      rectfill(b.x, b.y, b.x + b.w, GROUND + 12, 56)
      rectfill(b.x, b.y, b.x + b.w, b.y + 3, 58)
      for k = 0, flr(b.w / 16) do
        line(b.x + k * 16, b.y + 4, b.x + k * 16, GROUND + 10, 57)
      end
    end
  end
  for i = 1, #coins do
    local c = coins[i]
    if not c.got and c.x > cam - 20 and c.x < cam + W + 20 then
      local y = c.y + sin(t() * 3 + c.bob) * 3
      circfill(flr(c.x), flr(y), 4, 14)
      circfill(flr(c.x), flr(y), 2, 16)
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
  local lean = flr(p.vx * 0.6)
  -- legs move with speed, not with a timer
  local step = sin(dist * 0.09) * 4
  if p.on then
    line(x, y - 8, x - 3 + step, y, 32)
    line(x, y - 8, x + 3 - step, y, 32)
  else
    line(x, y - 8, x - 4, y - 2, 32)
    line(x, y - 8, x + 4, y - 1, 32)
  end
  rectfill(x - 4 + lean, y - 20, x + 4 + lean, y - 7, 34)
  circfill(x + lean, y - 24, 5, 61)
  circfill(x + lean + p.face * 2, y - 25, 1, 0)
  if p.dash > 0 then
    circ(x, y - 12, 10 + p.dash, 29)
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
