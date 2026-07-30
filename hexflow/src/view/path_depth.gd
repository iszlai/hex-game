## Breadth-first depth from the start through the path tree, which drives the
## colour gradient along a long path (§13.3).
##
## Extracted from `board_view.gd` when the C-18 view arrived: the grey-box and the
## 3D board both need it, and two copies of a traversal is two chances for the two
## views to disagree about which cell is how far along.
class_name PathDepth
extends RefCounted


## Cell → steps from the start, for every cell in [param state]'s path.
static func of(state: GameState) -> Dictionary:
	var depth: Dictionary = {}
	if state == null:
		return depth
	var board: Board = state.board
	var queue: Array[Vector3i] = [board.start]
	depth[board.start] = 0
	var head: int = 0
	while head < queue.size():
		var c: Vector3i = queue[head]
		head += 1
		for dir: int in Direction.ALL:
			var n: Vector3i = c + Direction.delta(dir)
			if state.path.has(n) and not depth.has(n):
				depth[n] = int(depth[c]) + 1
				queue.append(n)
	# Portal twins are not lattice neighbours; give them their partner's depth.
	for pair: Variant in board.portal_pairs():
		var p: Array = pair
		var a: Vector3i = p[0]
		var b: Vector3i = p[1]
		if depth.has(a) and not depth.has(b) and state.path.has(b):
			depth[b] = int(depth[a]) + 1
		elif depth.has(b) and not depth.has(a) and state.path.has(a):
			depth[a] = int(depth[b]) + 1
	return depth
