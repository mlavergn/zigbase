###############################################
#
# Makefile — zigbase
#
# `make validate` is the pre-commit gate; `make build` is the entry point.
#
###############################################

# Source roots `make format` and `make lint` cover; set before the include.
ZIG_DIRS := src cli web app

# Optional include to extend the makefile targets
-include ../styleguide/Makefile.in

.DEFAULT_GOAL := all

.PHONY: all build dist install install-app app run demo linux windows targets \
	test docs tag st open github clone claude clean

# ---------------------------------------------
# Configuration
# ---------------------------------------------

# The released version, read from build.zig.zon (the source of truth).
VERSION := $(shell sed -n -E 's/^[[:space:]]*\.version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' build.zig.zon)

# The native app's name, read from `app_name` in build.zig (the source of truth).
APP_NAME := $(shell sed -n -E 's/^const app_name = "([^"]+)";.*/\1/p' build.zig)

# Where `make install-app` puts the macOS bundle.
APP_DIR ?= $(HOME)/Applications

# ---------------------------------------------
# Primary workflows
# ---------------------------------------------

# Build, format, and test.
all: build format test
	@echo "done"

# ---------------------------------------------
# Build
# ---------------------------------------------

# Build the library and CLI.
build:
	zig build

# Build optimized for release.
dist:
	zig build --release=fast

# Install the release CLI (zbase) to ~/.local/bin.
install:
	zig build cli --release=fast --prefix "$(HOME)/.local"

# Install the native app: on macOS the bundle to $(APP_DIR); on Linux the
# executable to ~/.local/bin and its desktop entry under ~/.local/share. The
# first run fetches and builds SDL3.
install-app:
	@test -n "$(APP_NAME)" || { echo "❌ could not read app_name from build.zig"; exit 1; }
	@if [ "$$(uname -s)" = "Darwin" ]; then \
		zig build app -Dapp --release=fast && \
		install -d "$(APP_DIR)" && \
		rm -rf "$(APP_DIR)/$(APP_NAME).app" && \
		cp -R "zig-out/$(APP_NAME).app" "$(APP_DIR)/$(APP_NAME).app" && \
		echo "installed $(APP_DIR)/$(APP_NAME).app"; \
	else \
		zig build app -Dapp --release=fast --prefix "$(HOME)/.local"; \
	fi

# Build and open the native app: on macOS the bundle, on Linux the
# executable. The first run fetches and builds SDL3.
app:
	@test -n "$(APP_NAME)" || { echo "❌ could not read app_name from build.zig"; exit 1; }
	zig build app -Dapp --release=fast
	@if [ "$$(uname -s)" = "Darwin" ]; then \
		open -n "zig-out/$(APP_NAME).app"; \
	else \
		./zig-out/bin/$(APP_NAME); \
	fi

# Build and run the CLI. Pass arguments with `make run ARGS="Zig"`.
run:
	zig build run -- $(ARGS)

# Build and run the web console on a random port; it opens a browser itself.
demo:
	zig build serve

# ---------------------------------------------
# Cross-compilation
# ---------------------------------------------

# Compile for Linux.
linux:
	zig build -Dtarget=x86_64-linux

# Compile for Windows.
windows:
	zig build -Dtarget=x86_64-windows

# List every target Zig can build for.
targets:
	zig targets

# ---------------------------------------------
# Test
# ---------------------------------------------

# Run the unit test suite.
test:
	zig build test --summary all

# ---------------------------------------------
# Documentation
# ---------------------------------------------

# Build the API docs and serve them locally.
docs:
	zig build docs docs-serve

# ---------------------------------------------
# Release
# ---------------------------------------------

# Tag the build.zig.zon version (e.g. 1.0.0) and push it.
tag:
	@test -n "$(VERSION)" || { echo "❌ could not read .version from build.zig.zon"; exit 1; }
	git tag -a "$(VERSION)" -m "$(VERSION)"
	git push
	git push --tags

# ---------------------------------------------
# Environment
# ---------------------------------------------

# Open the working copy in SourceTree.
st:
	open -a SourceTree .

# Open the project in the editor.
open:
	code .

# Open the repository on GitHub.
github:
	open "https://github.com/mlavergn/zigbase"

# Clone a fresh working copy.
clone:
	git clone git@github.com:mlavergn/zigbase.git

# Start Claude Code here.
claude:
	claude

# ---------------------------------------------
# Housekeeping
# ---------------------------------------------

# Remove every build artifact.
clean:
	rm -rf .zig-cache
	rm -rf zig-out
