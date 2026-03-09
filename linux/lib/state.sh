#!/bin/bash
# lib/state.sh - State management functions
#
# Uses python3 for all JSON reads and writes. Unlike the Mac version which
# avoids python3 by using sed, Linux can rely on it as a checked prerequisite
# (install.sh requires Python 3.6+).
#
# Config file structure ($HOME/.docker-training-labs/config.json):
#   {
#     "version": "1.0.0",
#     "trainee_id": "<username>",
#     "current_scenario": "DNS" | null,
#     "scenario_start_time": <epoch_seconds> | null
#   }
#
# Write functions (set_current_scenario, set_scenario_start_time,
# clear_current_scenario) all use a temp file + mv pattern: the new
# content is written to a temp file first, then atomically renamed into
# place. This prevents a half-written config if the process is interrupted.

# Get current scenario name from config, or "null" if unset or null.
# Note: json.load returns Python None for JSON null values. print(None)
# outputs the string "None", not "null", so we must handle it explicitly.
get_current_scenario() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "null"
        return
    fi
    python3 -c "
import json
val = json.load(open('$CONFIG_FILE')).get('current_scenario')
print(val if val is not None else 'null')
" 2>/dev/null || echo "null"
}

# Write the current scenario name into config
set_current_scenario() {
    local scenario=$1
    local temp_file
    temp_file=$(mktemp)

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE"
    fi

    # $scenario and $CONFIG_FILE are interpolated directly into the Python
    # string. This is safe because scenario values are hardcoded constants
    # (DNS, PORT, BRIDGE, PROXY, CHAOS) set by start_lab() and never
    # derived from user input.
    python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    data = json.load(f)
data['current_scenario'] = '$scenario'
with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null

    # Atomic replace: mv is a single syscall so the file is never half-written
    mv "$temp_file" "$CONFIG_FILE"
}

# Reset scenario and start time to null in a single atomic write
clear_current_scenario() {
    local temp_file
    temp_file=$(mktemp)

    python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    data = json.load(f)
data['current_scenario'] = None
data['scenario_start_time'] = None
with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null

    mv "$temp_file" "$CONFIG_FILE"
}

# Read epoch start time, defaulting to 0 if unset or null.
# Same None vs 'null' issue as get_current_scenario: handle explicitly.
get_scenario_start_time() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "0"
        return
    fi
    python3 -c "
import json
val = json.load(open('$CONFIG_FILE')).get('scenario_start_time')
print(val if val is not None else 0)
" 2>/dev/null || echo "0"
}

# Write epoch start time into config
set_scenario_start_time() {
    local timestamp=$1
    local temp_file
    temp_file=$(mktemp)

    python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    data = json.load(f)
data['scenario_start_time'] = $timestamp
with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null

    mv "$temp_file" "$CONFIG_FILE"
}
