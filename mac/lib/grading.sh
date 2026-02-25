#!/bin/bash
# grading.sh - Grade recording functions
#
# Grades are stored as rows in $GRADES_FILE (grades.csv). The header row
# is written by install.sh; this function appends one row per lab attempt.
# Multiple attempts at the same lab are all kept - show_report_card uses
# the last recorded score for each scenario when building the display.

# record_grade - Append a lab result to grades.csv
record_grade() {
    local trainee=$1
    local scenario=$2
    local score=$3
    local duration=$4
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    echo "$trainee,$scenario,$score,$timestamp,$duration" >> "$GRADES_FILE"
}
