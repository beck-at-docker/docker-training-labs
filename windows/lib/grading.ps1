# grading.ps1 - Grade recording functions
#
# Grades are stored as rows in $GRADES_FILE (grades.csv). The header row
# is written by install.ps1; this function appends one row per lab attempt.
# Multiple attempts at the same lab are all kept - Show-ReportCard uses
# the last recorded score for each scenario when building the display.

function Record-Grade {
    param(
        [string]$Trainee,
        [string]$Scenario,
        [int]$Score,
        [int]$DurationSeconds
    )
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Add-Content $GRADES_FILE "$Trainee,$Scenario,$Score,$timestamp,$DurationSeconds"
}
