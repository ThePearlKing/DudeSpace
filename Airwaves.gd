class_name Airwaves
extends RefCounted
## THE DIAL, as a shared resource. Every BROADCAST module that goes on
## air claims a frequency here; if somebody already holds it, the claim
## walks up the band until it finds a free slot and the module says so on
## its own panel. Radios ask this registry what is actually being
## broadcast right now, and by whom.
##
## One band, 88.0 to 108.0 MHz, in 0.2 steps -- exactly the dial the
## Intergalactic Radio already sweeps.

const LOW := 88.0
const HIGH := 108.0
const STEP := 0.2

## freq (rounded to STEP) -> {"owner": Node, "name": String, "want": float}
static var _band: Dictionary = {}

static func _snap(f: float) -> float:
	return roundf(clampf(f, LOW, HIGH) / STEP) * STEP

static func _prune() -> void:
	for k in _band.keys():
		var e: Dictionary = _band[k]
		if not is_instance_valid(e.get("owner", null)):
			_band.erase(k)

## Put `owner` on air as close to `want` as the band allows. Returns the
## frequency actually granted -- which is `want` unless somebody got
## there first, in which case it is the next free slot going up (and
## wrapping round the bottom of the band if it has to).
static func claim(owner: Node, want: float, sname: String) -> float:
	_prune()
	release(owner)
	var w := _snap(want)
	var steps := int((HIGH - LOW) / STEP) + 1
	for i in steps:
		var f := _snap(LOW + fmod((w - LOW) + float(i) * STEP, HIGH - LOW + STEP))
		if not _band.has(f):
			_band[f] = {"owner": owner, "name": sname, "want": w}
			return f
	return -1.0     # the entire band is taken. impressive.

static func release(owner: Node) -> void:
	for k in _band.keys():
		if _band[k].get("owner", null) == owner:
			_band.erase(k)

static func rename(owner: Node, sname: String) -> void:
	for k in _band.keys():
		if _band[k].get("owner", null) == owner:
			_band[k]["name"] = sname

## Was this claim bumped off the frequency it asked for?
static func fallback_of(owner: Node) -> Dictionary:
	for k in _band.keys():
		if _band[k].get("owner", null) == owner:
			var want := float(_band[k].get("want", k))
			return {"freq": float(k), "want": want, "bumped": absf(float(k) - want) > 0.01,
				"name": str(_band[k].get("name", ""))}
	return {}

static func station_at(freq: float) -> Dictionary:
	_prune()
	var f := _snap(freq)
	if _band.has(f):
		var e: Dictionary = _band[f]
		return {"freq": f, "owner": e["owner"], "name": str(e.get("name", "UNNAMED"))}
	return {}

static func live_stations() -> Array:
	_prune()
	var out: Array = []
	for k in _band.keys():
		out.append({"freq": float(k), "owner": _band[k]["owner"],
			"name": str(_band[k].get("name", "UNNAMED"))})
	out.sort_custom(func(a, b): return float(a["freq"]) < float(b["freq"]))
	return out

static func clear() -> void:
	_band.clear()
