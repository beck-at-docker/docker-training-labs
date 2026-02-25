#!/bin/bash
# lib/colors.sh - Terminal color definitions

# Regular colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Bold colors
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_BLUE='\033[1;34m'

# Other styles
DIM='\033[2m'
UNDERLINE='\033[4m'
NC='\033[0m' # No Color

# Disable colors when not writing to a terminal (e.g. piped to a file)
if [ ! -t 1 ]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    WHITE=''
    BOLD_RED=''
    BOLD_GREEN=''
    BOLD_YELLOW=''
    BOLD_BLUE=''
    DIM=''
    UNDERLINE=''
    NC=''
fi
