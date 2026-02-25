#!/bin/bash
# lib/state.sh - State management functions
# Uses python3 for JSON read/write to avoid platform-specific tools.

# Get current scenario name from config, or "null" if unset
get_current_scenario() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "null"
        return
    fi
    python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('current_scenario', 'null'))" 2>/dev/null || echo "null"
}

# Write the current scenario name into config
set_current_scenario() {
    local scenario=$1
    local temp_file
    temp_file=$(mktemp)

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE"
    fi

    python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    data = json.load(f)
data['current_scenario'] = '$scenario'
with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null

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

# Read epoch start time, defaulting to 0
get_scenario_start_time() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "0"
        return
    fi
    python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('scenario_start_time', 0))" 2>/dev/null || echo "0"
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
