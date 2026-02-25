#!/bin/bash
# lib/colors.sh - Terminal color definitions
#
# Only four colors are used across this codebase: RED, GREEN, YELLOW, BLUE.
# NC (No Color) resets to the terminal default after a colored sequence.
# All variables are set to empty strings when stdout is not a terminal so
# that piped or redirected output is never polluted with escape codes.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Disable colors when not writing to a terminal (e.g. piped to a file)
if [ ! -t 1 ]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi
