## §14.4's four emitters, and the cap over them.
##
## "Four emitters total, all GPU" — so they are built once from a table and
## reused, never spawned per event. A particle system created at the moment
## something happens is a heap allocation in the middle of the frame that event
## landed on, which is precisely what C4 exists to stop.
##
## §14.5 turns all four off outright. That is a stronger statement than scaling a
## duration, and it is why every emit goes through [method Motion.particles_allowed]
## rather than through a shorter lifetime.
##
## The budget is the spec's: 8 sparks, 24 for the goal burst, 12 ambient motes and
## 10 for a wild pickup — 54 in total against §14.4's hard cap of 120, which leaves
## room for two bursts to overlap without breaching it.
class_name BoardParticles
extends Node3D

## §14.4's emitters, with the palette token each is coloured from and how long a
## particle lives. `ambient` emitters run continuously; the rest are one-shots.
const EMITTERS := {
	"placement_sparks": {"token": "path_core", "life": 0.42, "speed": 34.0, "ambient": false},
	"goal_burst": {"token": "goal_cell", "life": 0.32, "speed": 58.0, "ambient": false},
	"flow_motes": {"token": "path_glow", "life": 2.6, "speed": 6.0, "ambient": true},
	"wild_pickup": {"token": "wild", "life": 0.5, "speed": 28.0, "ambient": false},
}

@export var palette: Palette = null

var _emitters: Dictionary = {}     # String -> GPUParticles3D
var _scale: float = 1.0


func _ready() -> void:
	if palette == null:
		palette = Palette.current()
	_build()


## Sizes the emitters to the board: everything §14.4 specifies is in particles, not
## in pixels, so the only thing that scales with the board is how far they travel.
func bind(layout: HexLayout) -> void:
	_build()
	_scale = layout.size / 50.0
	for name: Variant in _emitters:
		var node: GPUParticles3D = _emitters[name]
		var mat := node.process_material as ParticleProcessMaterial
		var speed: float = float(EMITTERS[name]["speed"]) * _scale
		mat.initial_velocity_min = speed * 0.55
		mat.initial_velocity_max = speed
	set_motion()


## Fires the one-shot [param name] at [param at]. Silently does nothing under
## §14.5, which is the point — a caller should not have to ask first.
func burst(name: String, at: Vector3) -> void:
	if not _emitters.has(name) or not Motion.particles_allowed():
		return
	var node: GPUParticles3D = _emitters[name]
	node.position = at
	node.restart()


## §14.5: all four off, together. Called at bind and whenever the setting moves.
func set_motion() -> void:
	var allowed: bool = Motion.particles_allowed()
	for name: Variant in _emitters:
		var node: GPUParticles3D = _emitters[name]
		if bool(EMITTERS[name]["ambient"]):
			node.emitting = allowed
		elif not allowed:
			node.emitting = false


func emitter(name: String) -> GPUParticles3D:
	return _emitters.get(name, null)


## Every particle every emitter could have alive at once. §14.4 caps this at 120,
## and the check belongs in code rather than in a comment because the table is the
## kind of thing that grows.
static func live_budget() -> int:
	var total := 0
	for name: Variant in Motion.PARTICLE_BUDGET:
		total += int(Motion.PARTICLE_BUDGET[name])
	return total


func _build() -> void:
	if not _emitters.is_empty():
		return
	for name: Variant in EMITTERS:
		var node := GPUParticles3D.new()
		node.name = str(name)
		node.amount = int(Motion.PARTICLE_BUDGET[name])
		node.lifetime = float(EMITTERS[name]["life"])
		node.one_shot = not bool(EMITTERS[name]["ambient"])
		node.explosiveness = 0.0 if bool(EMITTERS[name]["ambient"]) else 1.0
		node.emitting = false
		node.draw_pass_1 = _spark_mesh()
		node.process_material = _process_material(str(name))
		add_child(node)
		_emitters[name] = node


## A particle is a small unlit quad in the emitter's own colour. §13.1 wants
## everything drawn procedurally, and a spark is the smallest thing that has to
## obey it.
func _spark_mesh() -> Mesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(3.0, 3.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	return mesh


func _process_material(name: String) -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO
	# Drag, so a burst opens out and settles rather than flying off the board
	# (§14.2 asks for exactly that on the goal burst).
	mat.damping_min = 8.0
	mat.damping_max = 16.0
	mat.scale_min = 0.4
	mat.scale_max = 1.0
	mat.color = palette.get(str(EMITTERS[name]["token"])) as Color
	if bool(EMITTERS[name]["ambient"]):
		# Ambient motes drift over the whole board rather than leaving one cell.
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(220.0, 4.0, 220.0)
		mat.damping_min = 0.0
		mat.damping_max = 1.0
	return mat
