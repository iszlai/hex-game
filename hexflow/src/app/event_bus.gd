extends Node
## Typed signals between the app layer and the view (§16.2).
##
## The dependency arrow never reverses: the view emits *intents* upward and
## receives *facts* downward. Nothing in this file carries a rule.

# --- facts: the app telling the view what happened ---------------------------

signal level_loaded(level: Level)
signal state_reset(state: GameState)
signal cell_joined(target: Vector3i, anchor: Vector3i, dir: int)
signal portal_linked(from: Vector3i, to: Vector3i)
signal goal_reached(cell: Vector3i)
## §6's lock opening — the placement that gave a gate its second path neighbour.
## Distinct from "this gate is open", which the marks already read live off
## [method Rules.gate_satisfied]; this is the moment it changed.
signal gate_opened(cell: Vector3i)
signal tile_advanced(current: int, preview: Array)
signal tile_auto_skipped(dir: int)
signal tile_discarded(dir: int, left: int)
signal wild_charges_changed(charges: int)
signal move_undone()
signal legal_targets_changed(targets: Array)
signal level_won(placements: int, par: int, stars: int)
## §5.8's dead state, with the reason — four different endings ask the player for
## different things, and a banner that names the wrong one sends them looking in the
## wrong half of the screen.
signal level_dead(reason: int)
signal illegal_move_attempted(cell: Vector3i)

# --- intents: the view asking the app for something --------------------------

signal place_requested(target: Vector3i)
signal wild_place_requested(target: Vector3i)
signal discard_requested()
signal undo_requested()
signal restart_requested()
signal hint_requested()
signal pause_requested()
## §7.2's run, between stages: the player saying they have looked long enough.
## Endless has no results card, so without this the only thing marking the end of
## a stage is the board being replaced — which happens on top of the goal sequence
## that was celebrating it.
signal advance_requested()
