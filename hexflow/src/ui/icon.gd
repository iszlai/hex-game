## §13.5's nine line icons, drawn as vector paths on a 24×24 grid.
##
## §13.5 offers a choice — "drawn as vector paths or an SVG-imported atlas" — and
## the paths win for the same reason C-23 chose procedural silhouettes for the
## board's modifier marks: an atlas is a raster at one size, and this project draws
## the same nine shapes at a rail row's size, at a legend row's size and at §21's
## 1.0–1.5 text scale on top of both. A path is crisp at all of them and costs no
## import step, no texture memory (§20) and no second file to keep in step with the
## palette.
##
## The grid is the contract. Every path below is written in 24×24 units and scaled
## once, so "2 px stroke on a 24 grid" stays true at any drawn size — which is what
## makes the nine read as one family rather than as nine drawings.
class_name Icon
extends Control

## §13.5's list, in its order. `hexagon` is the brand mark.
enum Kind { UNDO, DISCARD, WILD, HINT, GATE, PORTAL, GOAL, WALL, HEXAGON }

const GRID := 24.0
const STROKE := 2.0

@export var kind: Kind = Kind.HEXAGON:
	set(value):
		kind = value
		queue_redraw()

@export var colour: Color = Color.WHITE:
	set(value):
		colour = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(GRID, GRID)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The paths of one icon, in 24×24 units. Each entry is a polyline; a closed shape
## repeats its first point. Kept as data rather than as a `match` full of draw
## calls so the nine can be counted, measured and asserted (§13.5 says nine).
static func paths_of(kind_of: Kind) -> Array:
	match kind_of:
		Kind.UNDO:
			# An arc over the top with an arrowhead on its left tip, so the eye
			# reads it travelling anticlockwise — back the way it came.
			# `_arc` sweeps *forward* from the first angle to the second, and y is
			# down, so 180 → 360 is the top half and not the bottom one.
			return [
				_arc(12.0, 14.0, 7.0, 180.0, 360.0),
				[Vector2(19.0, 14.0), Vector2(19.0, 18.5)],
				[Vector2(1.8, 10.8), Vector2(5.0, 14.0)],
				[Vector2(5.0, 14.0), Vector2(8.2, 10.8)],
			]
		Kind.DISCARD:
			return [
				[Vector2(6.0, 6.0), Vector2(18.0, 18.0)],
				[Vector2(18.0, 6.0), Vector2(6.0, 18.0)],
			]
		Kind.WILD:
			return [_star(12.0, 12.0, 9.0, 4.0, 5)]
		Kind.HINT:
			# A question mark: a hook and a dot, the dot as a very short stroke so
			# every icon in the family is made of the same one primitive.
			return [
				_arc(12.0, 9.0, 4.5, 180.0, 440.0),
				[Vector2(12.8, 13.4), Vector2(12.0, 16.5)],
				[Vector2(12.0, 19.0), Vector2(12.0, 20.0)],
			]
		Kind.GATE:
			# A padlock: body and shackle.
			return [
				_rect(6.0, 11.0, 12.0, 8.0),
				_arc(12.0, 11.0, 4.0, 180.0, 360.0),
			]
		Kind.PORTAL:
			return [_arc(12.0, 12.0, 9.0, 0.0, 360.0), _arc(12.0, 12.0, 4.0, 0.0, 360.0)]
		Kind.GOAL:
			# A target: a ring, a dot, and four ticks — the reticle §6 gives a goal.
			return [
				_arc(12.0, 12.0, 7.0, 0.0, 360.0),
				[Vector2(12.0, 1.5), Vector2(12.0, 5.0)],
				[Vector2(12.0, 19.0), Vector2(12.0, 22.5)],
				[Vector2(1.5, 12.0), Vector2(5.0, 12.0)],
				[Vector2(19.0, 12.0), Vector2(22.5, 12.0)],
				[Vector2(11.5, 12.0), Vector2(12.5, 12.0)],
			]
		Kind.WALL:
			# A hatched square: the wall's colour-independent identity (§21), the
			# same 45° hatch the board and the level-select map both draw.
			return [
				_rect(4.0, 4.0, 16.0, 16.0),
				[Vector2(4.0, 12.0), Vector2(12.0, 4.0)],
				[Vector2(4.0, 20.0), Vector2(20.0, 4.0)],
				[Vector2(12.0, 20.0), Vector2(20.0, 12.0)],
			]
		_:
			return [_polygon(12.0, 12.0, 10.0, 6, -30.0)]


func _draw() -> void:
	var scale: float = minf(size.x, size.y) / GRID
	if scale <= 0.0:
		return
	for path: Variant in paths_of(kind):
		var points := PackedVector2Array()
		for p: Vector2 in (path as Array):
			points.append(p * scale)
		if points.size() >= 2:
			draw_polyline(points, colour, STROKE * scale, true)


# --- primitives, all in 24×24 units -------------------------------------------

static func _arc(cx: float, cy: float, r: float, from_deg: float, to_deg: float) -> Array:
	var out: Array = []
	var steps: int = maxi(4, int(absf(to_deg - from_deg) / 15.0))
	for i: int in range(steps + 1):
		var t: float = float(i) / float(steps)
		var a: float = deg_to_rad(from_deg + (to_deg - from_deg) * t)
		out.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return out


static func _rect(x: float, y: float, w: float, h: float) -> Array:
	return [
		Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h),
		Vector2(x, y + h), Vector2(x, y),
	]


static func _polygon(cx: float, cy: float, r: float, sides: int, offset_deg: float) -> Array:
	var out: Array = []
	for i: int in range(sides + 1):
		var a: float = deg_to_rad(offset_deg + 360.0 * float(i) / float(sides))
		out.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return out


static func _star(cx: float, cy: float, outer: float, inner: float, points_count: int) -> Array:
	var out: Array = []
	for i: int in range(points_count * 2 + 1):
		var r: float = outer if i % 2 == 0 else inner
		var a: float = deg_to_rad(-90.0 + 180.0 * float(i) / float(points_count))
		out.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return out
