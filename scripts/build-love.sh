
#!/bin/bash
set -e
cd "$(dirname "$0")/.."
mkdir -p build
rm -f build/game.love
(cd src && zip -9 -r ../build/game.love . -x "*.DS_Store" "lib/lurker.lua")
echo "Built build/game.love"