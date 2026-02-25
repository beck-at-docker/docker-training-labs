#!/bin/bash
# state.sh - State management functions
#
# Manages the JSON config file at $CONFIG_FILE using only standard shell
# tools (grep, sed, cat, mv, mktemp) to avoid any dependency on python3.
# The config file has a fixed, known structure so we can read and write it
# without a JSON parser.

# ------------------------------------------------------------------
# _write_config - Atomically write the full config file
# All four fields are required; handles null and numeric values correctly.
# ------------------------------------------------------------------
_write_config() {
    local version=$1
    local trainee=$2
    local scenario=$3
    local start_time=$4
    local temp_file
    temp_file=$(mktemp)

    # Format scenario as a JSON quoted string or the null literal
    local scenario_json
    if [ "$scenario" = "null" ] || [ -z "$scenario" ]; then
        scenario_json="null"
    else
        scenario_json="\"$scenario\""
    fi

    # Format start_time as a JSON number or the null literal
    local time_json
    if [ "$start_time" = "null" ] || [ -z "$start_time" ]; then
        time_json="null"
    else
        time_json="$start_time"
    fi

    cat > "$temp_file" << EOF
{
  "version": "$version",
  "trainee_id": "$trainee",
  "current_scenario": $scenario_json,
  "scenario_start_time": $time_json
}
EOF
    mv "$temp_file" "$CONFIG_FILE"
}

# ------------------------------------------------------------------
# _read_config_field - Extract a single field value from the config JSON.
# Uses grep to find the line and sed to strip the key, quotes, and commas.
# Returns $default if the file is missing or the field is not found.
# ------------------------------------------------------------------
_read_config_field() {
    local field=$1
    local default=$2

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "$default"
        return
    fi

    local value
    value=$(grep "\"$field\"" "$CONFIG_FILE" \
        | sed "s/.*\"$field\": *//;s/[\",$'\''']//g;s/[[:space:]]*$//" \
        | head -1)

    echo "${value:-$default}"
}

# ------------------------------------------------------------------
# get_current_scenario
# ------------------------------------------------------------------
get_current_scenario() {
    _read_config_field "current_scenario" "null"
}

# ------------------------------------------------------------------
# set_current_scenario
# ------------------------------------------------------------------
set_current_scenario() {
    local scenario=$1
    local version trainee start_time

    version=$(_read_config_field "version" "1.0.0")
    trainee=$(_read_config_field "trainee_id" "$USER")
    start_time=$(_read_config_field "scenario_start_time" "null")

    _write_config "$version" "$trainee" "$scenario" "$start_time"
}

# ------------------------------------------------------------------
# clear_current_scenario - Reset scenario and start time to null
# ------------------------------------------------------------------
clear_current_scenario() {
    local version trainee

    version=$(_read_config_field "version" "1.0.0")
    trainee=$(_read_config_field "trainee_id" "$USER")

    _write_config "$version" "$trainee" "null" "null"
}

# ------------------------------------------------------------------
# get_scenario_start_time
# ------------------------------------------------------------------
get_scenario_start_time() {
    local val
    val=$(_read_config_field "scenario_start_time" "0")

    # Treat null or empty as 0
    if [ "$val" = "null" ] || [ -z "$val" ]; then
        echo "0"
    else
        echo "$val"
    fi
}

# ------------------------------------------------------------------
# set_scenario_start_time
# ------------------------------------------------------------------
set_scenario_start_time() {
    local timestamp=$1
    local version trainee scenario

    version=$(_read_config_field "version" "1.0.0")
    trainee=$(_read_config_field "trainee_id" "$USER")
    scenario=$(_read_config_field "current_scenario" "null")

    _write_config "$version" "$trainee" "$scenario" "$timestamp"
}
