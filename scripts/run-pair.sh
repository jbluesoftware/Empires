#!/bin/bash
# Opens two side-by-side windows straight into the Play scene to test discovery, hosting and migration on one machine.
# Close the left window (the host) to watch the right one take over. Press R, G or B in a window to toggle its lights.
cd "$(dirname "$0")/.."
LOVE=/Applications/love.app/Contents/MacOS/love
$LOVE src play 1 &
$LOVE src play 2 &
wait
