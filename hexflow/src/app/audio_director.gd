extends Node
## Bus mixing, stem cross-fades, the pentatonic placement index and voice limits
## (§15). Decides nothing about gameplay.
##
## M0 stub: the index bookkeeping is real because undo has to step the scale back
## down (§15.2); playback is wired in M7 when the audio assets exist.

const PENTATONIC_STEPS := 5
const MAX_PLACE_VOICES := 4

var _scale_index: int = 0


func _ready() -> void:
	EventBus.cell_joined.connect(_on_cell_joined)
	EventBus.move_undone.connect(_on_move_undone)
	EventBus.state_reset.connect(_on_state_reset)


## The rising pentatonic ascent turns a long path into a melody — the single most
## important audio decision in the spec. Resets per level, steps down on undo.
func placement_note_index() -> int:
	return _scale_index


func _on_cell_joined(_target: Vector3i, _anchor: Vector3i, _dir: int) -> void:
	_scale_index += 1


func _on_move_undone() -> void:
	_scale_index = maxi(0, _scale_index - 1)


func _on_state_reset(_state: GameState) -> void:
	_scale_index = 0


func play_sfx(_id: String) -> void:
	pass  # M7


func set_bus_volume(bus: String, percent: int) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(percent / 100.0, 0.0, 1.0)))
