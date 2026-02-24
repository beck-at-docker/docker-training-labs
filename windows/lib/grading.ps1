# grading.ps1 - Grading functions

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
