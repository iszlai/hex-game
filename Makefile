# Hexflow — developer entry point.
#
# Everything here operates on the hexflow/ Godot project, which is now the only
# code in the tree. The 2016 libGDX prototype was removed from master and lives
# at the libgdx-2016 tag.
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
        test-file gate levels sheet sfx art icon glyphs marks marks-cut panels-cut grain-cut faces-cut assets assets-add assets-ui shot measure \
        playtest playtest-restore edit-maps \
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

# A capture gets its own `user://`, the same way each test script does. The tool
# boots the real game, and the real game writes its save on the way out — so every
# screenshot used to overwrite the player's progress, and a capture that needed
# progress in it meant editing that save by hand first and remembering to put it
# back. Isolation rather than `playtest`'s move-aside-and-restore: nothing to
# restore is better than something to restore, and a capture that crashes leaves
# no state behind at all. Godot resolves `user://` under $HOME.
shot: check ## Screenshot a screen. PRESSES=cceccc OUT=board.png LEVEL=5.1 SCREEN=level_select PROGRESS=5
	@home=$$(mktemp -d); trap 'rm -rf "$$home"' EXIT; \
	  cd $(PROJECT) && HOME="$$home" XDG_DATA_HOME="$$home/data" \
	    XDG_CONFIG_HOME="$$home/config" XDG_CACHE_HOME="$$home/cache" \
	    "$(GODOT_CMD)" --resolution 1280x800 -s res://tools/screenshot.gd -- \
	    "$(abspath $(or $(OUT),board.png))" "$(or $(PRESSES),)" "$(or $(LEVEL),)" \
	    "$(or $(SCREEN),)" "$(or $(PROGRESS),)"
	@echo "wrote $(or $(OUT),board.png)"

sheet: check ## One image of all 60 boards, tiled with ffmpeg. OUT=campaign.png MOVES=4
	@home=$$(mktemp -d); trap 'rm -rf "$$home"' EXIT; \
	  dir=$$(mktemp -d); \
	  cd $(PROJECT) && HOME="$$home" XDG_DATA_HOME="$$home/data" \
	    XDG_CONFIG_HOME="$$home/config" XDG_CACHE_HOME="$$home/cache" \
	    "$(GODOT_CMD)" --resolution 1280x800 -s res://tools/contact_sheet.gd -- \
	    "$$dir" "$(or $(MOVES),4)" >/dev/null; \
	  ffmpeg -y -loglevel error -pattern_type glob -i "$$dir/*.png" \
	    -filter_complex "crop=880:690:0:56,scale=440:345,tile=6x10:padding=4:color=0x1a1410" \
	    -frames:v 1 "$(abspath $(or $(OUT),campaign.png))"; \
	  rm -rf "$$dir"
	@echo "wrote $(or $(OUT),campaign.png)"

measure: check ## Frame cost per renderer (C-3). METHOD=forward_plus|mobile|gl_compatibility
	@$(RUN_CMD) --resolution 1280x800 \
	  --rendering-method $(or $(METHOD),gl_compatibility) \
	  -s res://tools/measure_renderer.gd

## ---------------------------------------------------------------- test

test: check ## Run the whole suite: @core, @property and @e2e. JOBS=1 to run it serially
	@GODOT="$(GODOT_CMD)" ./$(PROJECT)/tools/run_tests.sh

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

edit-maps: check ## Draw a campaign board by hand (hexflow/docs/MAP-EDITOR.md)
	@$(RUN_CMD) --resolution 1440x900 res://tools/map_editor/map_editor.tscn
	@echo
	@echo "levels are frozen data — commit the JSON the editor wrote"

sfx: check ## Re-render §15.2's sixteen effects into assets/sfx/ (commit the output)
	@$(RUN_CMD) --headless -s res://tools/make_sfx.gd
	@echo
	@echo "sound effects are committed assets — commit the .wav files"

art: check ## Re-render §13.7's backdrops and panel surfaces into assets/art/ (commit the output)
	@$(RUN_CMD) --headless -s res://tools/make_art.gd
	@echo
	@echo "art is a committed asset — commit the .png files (C-27: placeholder until an illustrator)"

glyphs: check ## Re-render §11.4's 52 controller glyphs into assets/glyphs/. FRESH=1 overwrites
	@$(RUN_CMD) --headless -s res://tools/make_glyphs.gd -- $(if $(FRESH),fresh,)
	@echo
	@echo "glyphs are committed assets — commit the .png files (placeholders until a licensed pack)"

icon: check ## Re-cut the window and dock icon out of assets/art/logo.png (commit the output)
	@$(RUN_CMD) --headless -s res://tools/make_icon.gd
	@echo
	@echo "the icon is a committed asset — commit assets/icons/icon.png"

marks: check ## Re-render C-29's modifier atlas into assets/art/marks.png. FRESH=1 overwrites
	@$(RUN_CMD) --headless -s res://tools/make_marks.gd -- $(if $(FRESH),fresh,)
	@echo
	@echo 'a stand-in for painted art — commit it, and see: make assets ROLE=marks'

marks-cut: ## Cut a generated sheet of four icons into assets/art/marks.png. FILE=~/Downloads/sheet.png
	@test -n "$(FILE)" || { echo "usage: make marks-cut FILE=~/Downloads/sheet.png"; exit 1; }
	@python3 $(PROJECT)/tools/cut_marks.py "$(FILE)" $(PROJECT)/assets/art/marks.png

panels-cut: ## Cut a drawn panel into a nine-slice texture. FILE=~/f.png AS=panel_frame
	@test -n "$(FILE)" || { echo "usage: make panels-cut FILE=~/frame.png AS=panel_frame"; exit 1; }
	@python3 $(PROJECT)/tools/cut_panel.py "$(FILE)" \
	  $(PROJECT)/assets/art/$(or $(AS),panel_frame).png

grain-cut: ## Turn a drawn stone texture into the board's value map. FILE=~/stone.png
	@test -n "$(FILE)" || { echo "usage: make grain-cut FILE=~/stone.png"; exit 1; }
	@python3 $(PROJECT)/tools/cut_grain.py "$(FILE)" $(PROJECT)/assets/art/tile_grain.png

faces-cut: ## Cut a 2x2 sheet of drawn hex tiles into the face atlas. FILE=~/tiles.png
	@test -n "$(FILE)" || { echo "usage: make faces-cut FILE=~/tiles.png"; exit 1; }
	@python3 $(PROJECT)/tools/cut_faces.py "$(FILE)" $(PROJECT)/assets/art/tile_face.png

assets: check ## What art and audio the game has, and what it is missing. ROLE=glyphs for one group's files
	@$(RUN_CMD) --headless -s res://tools/assets.gd -- status "$(or $(ROLE),)"

assets-add: check ## Put a file where the game looks for it. FILE=~/x.png AS=chapter_3
	@$(RUN_CMD) --headless -s res://tools/assets.gd -- add "$(FILE)" "$(or $(AS),)"

assets-ui: ## The asset desk in a browser: see every slot, drop files onto them
	@python3 $(PROJECT)/tools/asset_server.py $(or $(PORT),7777)

playtest: check ## Play as a first-time player would: your save is moved aside, not deleted
	@$(RUN_CMD) --headless -s res://tools/playtest.gd -- reset
	@echo
	@$(RUN_CMD) --resolution 1280x800

playtest-restore: check ## Put your own save back after a playtest
	@$(RUN_CMD) --headless -s res://tools/playtest.gd -- restore

## ---------------------------------------------------------------- misc

legacy-branch: ## Where the retired 2016 libGDX prototype went
	@echo "the prototype is at the libgdx-2016 tag; master holds the Godot game only"
	@git rev-parse --verify libgdx-2016 >/dev/null 2>&1 \
	  && echo "  tag    libgdx-2016  $$(git rev-parse --short libgdx-2016^{commit})" \
	  || echo "  WARNING: the libgdx-2016 tag is not in this clone"
	@echo "  check it out with: git checkout libgdx-2016"

clean: ## Drop the Godot import cache
	@rm -rf $(PROJECT)/.godot
	@echo "removed $(PROJECT)/.godot — the next run will reimport"

clean-levels: ## Delete the frozen campaign data (regenerate with `make levels`)
	@rm -rf $(PROJECT)/src/data/levels/chapter_*
	@echo "removed campaign level files"

# Every recipe above runs from hexflow/, so a relative GODOT still resolves.
RUN_CMD = cd $(PROJECT) && "$(GODOT_CMD)"
