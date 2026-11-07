# Everything DisplayDial needs, from the command line.
#
# `make` on its own lists every target, which is the only documentation of this file that
# cannot go stale.

APP   := build/DisplayDial.app
SHOTS := build/screenshots

.DEFAULT_GOAL := help
.PHONY: help build release test live-test run shot install icon version bump clean

help: ## list every target
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  make %-10s %s\n", $$1, $$2}'

build: ## Debug build, a compile check
	swift build

release: ## Release build, packaged as build/DisplayDial.app
	@./build.sh

test: ## run the unit tests (no monitor needed)
	swift test

live-test: ## read-only check against the connected monitor
	DISPLAYDIAL_LIVE=1 swift test --filter LiveMonitorTests

run: release ## build Release, then launch it (quits a running copy first)
	-@pkill -TERM -x DisplayDial; sleep 1
	open "$(APP)"

# shot starts a second copy beside any DisplayDial already running and stops only that copy.
# In snapshot mode the app reads the monitor but never writes to it.
shot: release ## save the app's windows to build/screenshots (TAB=general|presets|about adds Settings)
	@rm -rf "$(SHOTS)"
	@DISPLAYDIAL_SNAPSHOT_DIR="$(CURDIR)/$(SHOTS)" DISPLAYDIAL_SETTINGS_TAB="$(TAB)" \
		"$(APP)/Contents/MacOS/DisplayDial" >/dev/null 2>&1 & pid=$$!; sleep 6; kill -TERM $$pid; sleep 1
	@ls "$(SHOTS)"

install: release ## copy the app to ~/Applications, where Launch at login expects it
	@mkdir -p ~/Applications
	rm -rf ~/Applications/DisplayDial.app
	cp -R "$(APP)" ~/Applications/

icon: ## redraw Resources/AppIcon.icns from Scripts/make-icon.swift
	@tmp=$$(mktemp -d); swift Scripts/make-icon.swift "$$tmp/AppIcon.iconset" && \
		iconutil -c icns "$$tmp/AppIcon.iconset" -o Resources/AppIcon.icns; rm -rf "$$tmp"

version: ## print the app's version
	@cat VERSION

bump: ## raise the version (PART=minor|major, default patch)
	@old=$$(cat VERSION); \
	new=$$(echo $$old | awk -F. -v part="$(PART)" '{ if (part == "major") { $$1++; $$2 = 0; $$3 = 0 } \
		else if (part == "minor") { $$2++; $$3 = 0 } else { $$3++ }; print $$1 "." $$2 "." $$3 }'); \
	echo $$new > VERSION; echo "$$old -> $$new"

clean: ## delete build products
	rm -rf build .build
