## The seeded source of directions (§5.3).
##
## Two modes:
##   * bag     — an endless sequence of shuffled 6-direction bags, so the player
##               never suffers a drought and randomness stays auditable.
##   * fixed   — an explicit array from a campaign level file; exhausting it ends
##               the level (§5.8).
##
## The generated sequence is memoised, so [method rewind_to] is exact and undo
## can never desynchronise the stream from the state (§5.9).
##
## The only [RandomNumberGenerator] instances in the game live here and in
## [Generator] (§19, C2). Global `randi()` / `randf()` / `randomize()` are banned.
class_name TileStream
extends RefCounted

var index: int = 0

var _seed: int = 0
var _rng: RandomNumberGenerator = null
var _fixed: Array[int] = []
var _drawn: Array[int] = []  # memoised bag output, index-addressable


static func from_seed(p_seed: int) -> TileStream:
	var s := TileStream.new()
	s._seed = p_seed
	s._rng = RandomNumberGenerator.new()
	s._rng.seed = p_seed
	return s


static func from_tiles(p_tiles: Array[int]) -> TileStream:
	var s := TileStream.new()
	s._fixed = p_tiles.duplicate()
	return s


func is_fixed() -> bool:
	return not _fixed.is_empty()


func get_seed() -> int:
	return _seed


## The tile at absolute position [param i], or [constant Direction.NONE] when a
## fixed sequence has run out.
func at(i: int) -> int:
	if is_fixed():
		return _fixed[i] if i < _fixed.size() else Direction.NONE
	_fill_to(i)
	return _drawn[i]


func current() -> int:
	return at(index)


## The next [param n] tiles after the current one — the preview queue shows 2.
##
## A fixed stream returns **fewer than [param n]** as it runs down, rather than
## padding the tail with [constant Direction.NONE]. The sentinel means "there is no
## tile here", and handing it out as though it were one made every caller
## responsible for spotting it: C-18's pile drew a coin per entry, so a level with
## two tiles left showed a full stack of five, three of them carrying an arrow read
## out of `DELTAS[-2]`. What is left is what gets returned.
##
## An endless bag never runs out, so this only ever shortens a campaign queue.
func peek(n: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(1, n + 1):
		var tile: int = at(index + i)
		if tile == Direction.NONE:
			break
		out.append(tile)
	return out


func is_exhausted() -> bool:
	return current() == Direction.NONE


func advance() -> void:
	index += 1


func rewind_to(i: int) -> void:
	assert(i >= 0)
	index = i


func remaining() -> int:
	if is_fixed():
		return maxi(0, _fixed.size() - index)
	return -1  # infinite


## Grows the memoised sequence until position [param i] exists.
func _fill_to(i: int) -> void:
	while _drawn.size() <= i:
		_drawn.append_array(_next_bag())


## Canonical descending-index Fisher-Yates (§19). Specified precisely so the
## sequence is byte-identical on every platform and every engine version.
func _next_bag() -> Array[int]:
	var bag: Array[int] = Direction.ALL.duplicate()
	for i: int in range(bag.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: int = bag[i]
		bag[i] = bag[j]
		bag[j] = tmp
	return bag
