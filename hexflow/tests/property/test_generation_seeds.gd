## @property — Feature: Generation invariants, swept over consecutive seeds
## (§24.2, §24.4).
##
## The other half of `test_generation_chapters.gd`. Consecutive seeds rather than
## spread ones, because B3's unsolvable boards were not evenly distributed — they
## came in runs, and a sweep that samples every 37th seed can step straight over
## a cluster of them.
extends "res://tests/property/soundness.gd"


func test_consecutive_seeds_all_produce_sound_levels() -> void:
	var params := Generator.chapter_params(2, 6)
	for s: int in range(SWEEP_SEEDS):
		assert_candidate_is_sound(Generator.generate(500000 + s, params), "seed %d" % (500000 + s))
