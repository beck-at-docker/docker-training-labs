#!/bin/bash
# state.sh - State management functions

# Get current scenario
get_current_scenario() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "null"
        return
    fi
    python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('current_scenario', 'null'))" 2>/dev/null || echo "null"
}

# Set current scenario
set_current_scenario() {
    local scenario=$1
    local temp_file=$(mktemp)
    
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

# Clear current scenario
clear_current_scenario() {
    set_current_scenario "null"
    python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    data = json.load(f)
data['scenario_start_time'] = None
with open('$CONFIG_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
}

# Get scenario start time
get_scenario_start_time() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "0"
        return
    fi
    python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('scenario_start_time', 0))" 2>/dev/null || echo "0"
}

# Set scenario start time
set_scenario_start_time() {
    local timestamp=$1
    local temp_file=$(mktemp)
    
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
