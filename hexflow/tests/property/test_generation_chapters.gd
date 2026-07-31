## @property — Feature: Generation invariants, swept across every chapter
## (§24.2, §24.4).
##
## With `test_generation_seeds.gd`, the single most valuable test in the suite:
## unsolvable levels are the 2016 prototype's signature failure (B2, B3). This
## half sweeps the five chapters' own parameter sets, so a modifier that only
## chapter 4 turns on is still proven to generate something winnable.
extends "res://tests/property/soundness.gd"


func test_every_accepted_candidate_is_solvable_across_all_chapters() -> void:
	for chapter: int in CHAPTERS:
		for i: int in range(SWEEP_SEEDS / CHAPTERS.size()):
			var level_index: int = 1 + (i % 12)
			var params := Generator.chapter_params(chapter, level_index)
			var lv := Generator.generate(1000 + i * 37, params)
			assert_candidate_is_sound(lv, "ch%d l%d seed %d" % [chapter, level_index, 1000 + i * 37])
