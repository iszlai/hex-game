extends Node
## Achievements and leaderboards, with a graceful no-op when Steam is absent
## (§23). Never blocks or errors a local run.
##
## GodotSteam is not linked yet (M9). Until then [member available] is false and
## every call mirrors locally, which is exactly the code path §23.1 requires when
## a real player launches outside Steam.

var available: bool = false


func _ready() -> void:
	available = Engine.has_singleton("Steam")


## Achievements are mirrored into the save so they unlock correctly offline and
## sync on the next successful init.
func unlock_achievement(api_name: String) -> void:
	var mirror: Array = SaveService.data["achievements_mirror"]
	if not mirror.has(api_name):
		mirror.append(api_name)
		SaveService.save_to_disk()
	if not available:
		return
	# M9: Steam.setAchievement(api_name); Steam.storeStats()


func submit_leaderboard(_board_name: String, _score: int, _detail: Array = []) -> void:
	if not available:
		return
	# M9: Steam.uploadLeaderboardScore(...)


func sync_pending() -> void:
	if not available:
		return
	for api_name: Variant in SaveService.data["achievements_mirror"]:
		unlock_achievement(str(api_name))
