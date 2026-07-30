## Shared level fixtures for the test suite.
class_name Fixtures

const START := Vector3i(-3, 0, 3)
const GOAL := Vector3i(3, 0, -3)


## The reference radius-3 board of Appendix A: 37 cells, start bottom-left,
## goal top-right, cube distance 6.
static func reference_board(
	walls: Array[Vector3i] = [],
	goals: Array[Vector3i] = [GOAL] as Array[Vector3i]
) -> Board:
	return Board.build(3, START, goals, walls)


## A level with an explicit tile sequence, so tests are fully deterministic.
static func fixed_level(tiles: Array[String], walls: Array[Vector3i] = []) -> Level:
	var lv := Level.build(reference_board(walls), dirs(tiles))
	lv.id = "fixture"
	lv.discards = 3
	return lv


## A level fed by the seeded bag rather than a fixed sequence.
static func seeded_level(p_seed: int, walls: Array[Vector3i] = []) -> Level:
	var lv := Level.build(reference_board(walls), [] as Array[int], p_seed)
	lv.id = "fixture_seeded"
	lv.discards = 3
	return lv


static func dirs(names: Array[String]) -> Array[int]:
	var out: Array[int] = []
	for n: String in names:
		out.append(Direction.from_name(n))
	return out


## The straight diagonal from start to goal. `goal - start` is `(6, 0, -6)`, which
## is exactly six NE steps — the shortest possible route on a radius-3 board, so
## any level using it has par 6.
static func shortest_route_tiles() -> Array[String]:
	return ["NE", "NE", "NE", "NE", "NE", "NE"]


static func cells(list: Array) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for a: Variant in list:
		out.append(a as Vector3i)
	return out
