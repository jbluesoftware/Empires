#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/build-love.sh"
adb push "$SCRIPT_DIR/../build/game.love" /sdcard/Download/game.love