#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
exec godot --headless --script res://tests/run.gd
