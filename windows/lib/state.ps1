# state.ps1 - State management functions
# Compatible with Windows PowerShell 5.1+

function Get-CurrentScenario {
    if (-not (Test-Path $CONFIG_FILE)) { return $null }
    try {
        $data = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
        return $data.current_scenario
    } catch { return $null }
}

function Set-CurrentScenario {
    param([string]$Scenario)
    try {
        if (Test-Path $CONFIG_FILE) {
            $data = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
        } else {
            $data = New-Object PSObject
        }
        $data | Add-Member -MemberType NoteProperty -Name current_scenario -Value $Scenario -Force
        $data | ConvertTo-Json | Set-Content $CONFIG_FILE -Encoding UTF8
    } catch {
        # Fallback: write minimal config
        [PSCustomObject]@{ current_scenario = $Scenario } | ConvertTo-Json | Set-Content $CONFIG_FILE -Encoding UTF8
    }
}

function Clear-CurrentScenario {
    try {
        if (Test-Path $CONFIG_FILE) {
            $data = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
        } else {
            $data = New-Object PSObject
        }
        $data | Add-Member -MemberType NoteProperty -Name current_scenario    -Value $null -Force
        $data | Add-Member -MemberType NoteProperty -Name scenario_start_time -Value $null -Force
        $data | ConvertTo-Json | Set-Content $CONFIG_FILE -Encoding UTF8
    } catch {
        [PSCustomObject]@{ current_scenario = $null; scenario_start_time = $null } | ConvertTo-Json | Set-Content $CONFIG_FILE -Encoding UTF8
    }
}

function Get-ScenarioStartTime {
    if (-not (Test-Path $CONFIG_FILE)) { return 0 }
    try {
        $data = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
        if ($null -eq $data.scenario_start_time) { return 0 }
        return [long]$data.scenario_start_time
    } catch { return 0 }
}

function Set-ScenarioStartTime {
    param([long]$Timestamp)
    try {
        if (Test-Path $CONFIG_FILE) {
            $data = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json
        } else {
            $data = New-Object PSObject
        }
        $data | Add-Member -MemberType NoteProperty -Name scenario_start_time -Value $Timestamp -Force
        $data | ConvertTo-Json | Set-Content $CONFIG_FILE -Encoding UTF8
    } catch {
        [PSCustomObject]@{ scenario_start_time = $Timestamp } | ConvertTo-Json | Set-Content $CONFIG_FILE -Encoding UTF8
    }
}
