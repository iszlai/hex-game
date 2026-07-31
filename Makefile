# Hexflow — developer entry point.
#
# Everything here operates on the hexflow/ Godot project. The 2016 libGDX
# prototype at the top level is retired and is not built by any target; see
# README.md for the migration plan.
#
#   make            list the targets
#   make godot      fetch the pinned engine into .tools/ (no system install)
#   make test       the whole suite
#   make gate       what CI runs — run this before pushing

GODOT_VERSION := 4.7.1
PROJECT       := hexflow

# Where `make godot` puts the engine. Override GODOT to use your own install:
#   make test GODOT=/Applications/Godot.app/Contents/MacOS/Godot
TOOLS_DIR := .tools
UNAME_S   := $(shell uname -s)
UNAME_M   := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
  GODOT_ARCHIVE := Godot_v$(GODOT_VERSION)-stable_macos.universal.zip
  GODOT_LOCAL   := $(TOOLS_DIR)/Godot.app/Contents/MacOS/Godot
else
  ifeq ($(UNAME_M),aarch64)
    GODOT_ARCHIVE := Godot_v$(GODOT_VERSION)-stable_linux.arm64.zip
    GODOT_BINARY  := Godot_v$(GODOT_VERSION)-stable_linux.arm64
  else
    GODOT_ARCHIVE := Godot_v$(GODOT_VERSION)-stable_linux.x86_64.zip
    GODOT_BINARY  := Godot_v$(GODOT_VERSION)-stable_linux.x86_64
  endif
  GODOT_LOCAL := $(TOOLS_DIR)/$(GODOT_BINARY)
endif

GODOT_URL := https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)-stable/$(GODOT_ARCHIVE)

# Prefer an explicit GODOT, then the local fetch, then whatever is on PATH.
GODOT ?= $(shell test -x $(GODOT_LOCAL) && echo $(GODOT_LOCAL) || echo godot)

GUT := --headless -s res://addons/gut/gut_cmdln.gd -ginclude_subdirs -gexit -gprefix=test_

# Resolve GODOT to an absolute path only when it is a local file, so a bare
# `godot` on PATH still works.
GODOT_CMD = $(shell test -x "$(GODOT)" && echo "$(abspath $(GODOT))" || echo "$(GODOT)")

.DEFAULT_GOAL := help
.PHONY: help godot check import run editor test test-core test-property test-e2e \
        test-file gate levels sfx art assets assets-add shot measure \
        playtest playtest-restore \
        clean clean-levels legacy-branch status

## ---------------------------------------------------------------- meta

help: ## List the available targets
	@echo "Hexflow — Godot $(GODOT_VERSION)"
	@echo "engine: $(GODOT_CMD)"
	@echo
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

status: ## Show engine, branch and level-file counts
	@echo "engine   : $(GODOT_CMD)"
	@"$(GODOT_CMD)" --version --headless 2>/dev/null || echo "           (not found — run: make godot)"
	@echo "branch   : $$(git rev-parse --abbrev-ref HEAD)"
	@echo "levels   : $$(find $(PROJECT)/src/data/levels -name '*.json' | wc -l | tr -d ' ') frozen files"
	@echo "tests    : $$(find $(PROJECT)/tests -name 'test_*.gd' | wc -l | tr -d ' ') scripts"

## ---------------------------------------------------------------- setup

godot: $(GODOT_LOCAL) ## Download the pinned engine into .tools/ (no system install)
	@echo "engine ready: $(GODOT_LOCAL)"

$(GODOT_LOCAL):
	@mkdir -p $(TOOLS_DIR)
	@echo "fetching Godot $(GODOT_VERSION) …"
	@curl -sL -o $(TOOLS_DIR)/godot.zip "$(GODOT_URL)"
	@cd $(TOOLS_DIR) && unzip -oq godot.zip && rm godot.zip
	@chmod +x $(GODOT_LOCAL) 2>/dev/null || true

check: ## Fail early if no engine is available
	@command -v "$(GODOT_CMD)" >/dev/null 2>&1 || test -x "$(GODOT_CMD)" || { \
	  echo "no Godot $(GODOT_VERSION) found. Run: make godot"; exit 1; }

import: check ## Import assets and refresh the global class cache
	@$(RUN_CMD) --headless --import

## ---------------------------------------------------------------- play

run: check ## Play the game at the 1280x800 Deck reference resolution
	@$(RUN_CMD) --resolution 1280x800

editor: check ## Open the project in the Godot editor
	@$(RUN_CMD) --editor

shot: check ## Screenshot a screen. PRESSES=cceccc OUT=board.png LEVEL=5.1 SCREEN=level_select
	@$(RUN_CMD) --resolution 1280x800 -s res://tools/screenshot.gd -- \
	  "$(abspath $(or $(OUT),board.png))" "$(or $(PRESSES),)" "$(or $(LEVEL),)" "$(or $(SCREEN),)"
	@echo "wrote $(or $(OUT),board.png)"

measure: check ## Frame cost per renderer (C-3). METHOD=forward_plus|mobile|gl_compatibility
	@$(RUN_CMD) --resolution 1280x800 \
	  --rendering-method $(or $(METHOD),gl_compatibility) \
	  -s res://tools/measure_renderer.gd

## ---------------------------------------------------------------- test

test: check ## Run the whole suite: @core, @property and @e2e
	@$(RUN_CMD) $(GUT) -gdir=res://tests

test-core: check ## Pure logic only — fast, no scenes
	@$(RUN_CMD) $(GUT) -gdir=res://tests/unit

test-property: check ## Generator, solver and shipped level-file invariants
	@$(RUN_CMD) $(GUT) -gdir=res://tests/property

test-e2e: check ## Full flows through the real scene tree with injected input
	@$(RUN_CMD) $(GUT) -gdir=res://tests/e2e

test-file: check ## One script. FILE=tests/unit/test_rules.gd
	@test -n "$(FILE)" || { echo "usage: make test-file FILE=tests/unit/test_rules.gd"; exit 1; }
	@$(RUN_CMD) $(GUT) -gtest=res://$(FILE)

gate: check ## Everything CI runs — do this before pushing
	@GODOT="$(GODOT_CMD)" ./$(PROJECT)/tools/ci_gate.sh

## ---------------------------------------------------------------- content

levels: check ## Regenerate and re-verify campaign levels. CHAPTER=3 for one
	@$(RUN_CMD) --headless -s res://tools/author_levels.gd -- $(CHAPTER)
	@echo
	@echo "levels are frozen data — commit the JSON, and expect pars to change"

sfx: check ## Re-render §15.2's sixteen effects into assets/sfx/ (commit the output)
	@$(RUN_CMD) --headless -s res://tools/make_sfx.gd
	@echo
	@echo "sound effects are committed assets — commit the .wav files"

art: check ## Re-render §13.7's backdrops and panel surfaces into assets/art/ (commit the output)
	@$(RUN_CMD) --headless -s res://tools/make_art.gd
	@echo
	@echo "art is a committed asset — commit the .png files (C-27: placeholder until an illustrator)"

assets: check ## What art and audio the game has, and what it is still missing
	@$(RUN_CMD) --headless -s res://tools/assets.gd -- status

assets-add: check ## Put a file where the game looks for it. FILE=~/x.png AS=chapter_3
	@$(RUN_CMD) --headless -s res://tools/assets.gd -- add "$(FILE)" "$(or $(AS),)"

playtest: check ## Play as a first-time player would: your save is moved aside, not deleted
	@$(RUN_CMD) --headless -s res://tools/playtest.gd -- reset
	@echo
	@$(RUN_CMD) --resolution 1280x800

playtest-restore: check ## Put your own save back after a playtest
	@$(RUN_CMD) --headless -s res://tools/playtest.gd -- restore

## ---------------------------------------------------------------- misc

legacy-branch: ## Re-pin legacy/libgdx-2016 at the last commit holding the prototype
	@git rev-parse --verify legacy/libgdx-2016 >/dev/null 2>&1 \
	  && echo "legacy/libgdx-2016 already exists at $$(git rev-parse --short legacy/libgdx-2016)" \
	  || git branch legacy/libgdx-2016 master

clean: ## Drop the Godot import cache
	@rm -rf $(PROJECT)/.godot
	@echo "removed $(PROJECT)/.godot — the next run will reimport"

clean-levels: ## Delete the frozen campaign data (regenerate with `make levels`)
	@rm -rf $(PROJECT)/src/data/levels/chapter_*
	@echo "removed campaign level files"

# Every recipe above runs from hexflow/, so a relative GODOT still resolves.
RUN_CMD = cd $(PROJECT) && "$(GODOT_CMD)"
