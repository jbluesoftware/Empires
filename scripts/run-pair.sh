#!/bin/bash
cd "$(dirname "$0")/.."
LOVE=/Applications/love.app/Contents/MacOS/love
$LOVE src host &
$LOVE src client &
wait