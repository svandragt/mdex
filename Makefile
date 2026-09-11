# Thin wrapper over meson. Ninja already tracks dependencies, so every target
# defers to it rather than restating them here.
.PHONY: all run test clean install uninstall

BUILD := build
BIN   := $(BUILD)/src/mdex

# Default to a user install: ~/.local/bin is already on PATH and needs no sudo.
# Override for a system install: make install PREFIX=/usr/local
PREFIX ?= $(HOME)/.local

all: $(BUILD)
	meson compile -C $(BUILD)

$(BUILD):
	meson setup $(BUILD)

run: all
	./$(BIN)

install: all
	meson configure $(BUILD) --prefix=$(PREFIX)
	meson install -C $(BUILD)

uninstall:
	ninja -C $(BUILD) uninstall

clean:
	rm -rf $(BUILD)

test: all
	meson test -C $(BUILD) --print-errorlogs
