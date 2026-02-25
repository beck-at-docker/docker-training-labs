#!/bin/bash
# lib/grading.sh - Grade recording functions

# Append a trainee's lab result to the grades CSV
record_grade() {
    local trainee=$1
    local scenario=$2
    local score=$3
    local duration=$4
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    echo "$trainee,$scenario,$score,$timestamp,$duration" >> "$GRADES_FILE"
}
