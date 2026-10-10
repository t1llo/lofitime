SHELL := /bin/bash
CONFIGURATION ?= release
APP := build/Lofitime.app
DIAGNOSTIC_ARGS := -ApplePersistenceIgnoreState YES

.PHONY: help build debug run dev test check smoke activity-smoke activity-preview audio-smoke performance preview install clean
.DEFAULT_GOAL := help

help: ## Show the available commands
	@awk 'BEGIN {FS = ":.*## "; printf "\n  Lofitime — a little space for you\n\n"} /^[a-zA-Z_-]+:.*## / {printf "  make %-10s %s\n", $$1, $$2} END {print ""}' $(MAKEFILE_LIST)

build: ## Build and locally sign a release .app in build/
	@./scripts/build-app.sh "$(CONFIGURATION)"

debug: ## Build a debug .app with native diagnostics
	@./scripts/build-app.sh debug

run: build ## Build, restart, and open the app
	@./scripts/run-app.sh

dev: debug ## Build and open a debug app
	@./scripts/run-app.sh

test: ## Run timer, activity, preferences, and GitHub sync tests (no network needed)
	swift build --product LofiMenCoreTests --disable-keychain
	@set -e; bin="$$(swift build --product LofiMenCoreTests --disable-keychain --show-bin-path)/LofiMenCoreTests"; \
		codesign --force --sign - "$$bin"; \
		"$$bin"

check: test build ## Test, release-build, and verify the app bundle
	plutil -lint "$(APP)/Contents/Info.plist"
	codesign --verify --deep --strict "$(APP)"
	@test -f "$(APP)/Contents/Resources/LofiMen_LofiMen.bundle/player.html" || test -f "$(APP)/Contents/Resources/LofiMen_LofiMen.bundle/Contents/Resources/player.html"
	@test -f "$(APP)/Contents/Frameworks/Sparkle.framework/Sparkle"
	@test -f "$(APP)/Contents/Resources/AppIcon.icns"
	@test -f "$(APP)/Contents/Resources/LofiMen_LofiMen.bundle/lofi-head.svg" || test -f "$(APP)/Contents/Resources/LofiMen_LofiMen.bundle/Contents/Resources/lofi-head.svg"
	@test -f "$(APP)/Contents/Resources/LofiMen_LofiMen.bundle/app-icon.png" || test -f "$(APP)/Contents/Resources/LofiMen_LofiMen.bundle/Contents/Resources/app-icon.png"
	@python3 scripts/check-room-assets.py "$(APP)"
	@python3 -c 'import pathlib,re; data=pathlib.Path("$(APP)/Contents/MacOS/LofiMen").read_bytes(); assert not re.search(rb"/Users/|/home/|/private/(var|tmp)/", data), "Release binary contains local build paths"'
	@echo "All checks passed. Open build/Lofitime.app or run make run."

smoke: debug ## Exercise native timer + real YouTube playback (requires internet)
	@"$(APP)/Contents/MacOS/LofiMen" $(DIAGNOSTIC_ARGS) --smoke-test

activity-smoke: debug ## Check 3D room growth, activity history, and themes (no network)
	@"$(APP)/Contents/MacOS/LofiMen" $(DIAGNOSTIC_ARGS) --smoke-activity

activity-preview: debug ## Render every room growth stage and activity theme (no network)
	@"$(APP)/Contents/MacOS/LofiMen" $(DIAGNOSTIC_ARGS) --render-activity "$(CURDIR)/build/previews"

audio-smoke: debug ## Check headphone-loss pause and explicit resume with live playback
	@"$(APP)/Contents/MacOS/LofiMen" $(DIAGNOSTIC_ARGS) --smoke-audio-output

performance: debug ## Check background playback and idle resource behavior (requires internet)
	@"$(APP)/Contents/MacOS/LofiMen" $(DIAGNOSTIC_ARGS) --performance-test

preview: debug ## Render native room, menu-bar, and settings PNGs
	@"$(APP)/Contents/MacOS/LofiMen" $(DIAGNOSTIC_ARGS) --render-preview "$(CURDIR)/build/previews"

install: build ## Copy the app into ~/Applications
	mkdir -p "$(HOME)/Applications"
	ditto "$(APP)" "$(HOME)/Applications/Lofitime.app"

clean: ## Remove generated builds and previews
	rm -rf .build build
