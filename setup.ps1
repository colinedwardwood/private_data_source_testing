# Requirements
# 0. Powershell 7 is installed and in the correct location
# 1. "C:\Program Files\GrafanaLabs\PDC" directory exists
# 2. "C:\Program Files\GrafanaLabs\PDC\pdc.exe" exists
# 3. "C:\Program Files\GrafanaLabs\PDC\Logs" directory exists

# Check if necessary env-vars exist.
$envvars = 'PDC_ARG_PDC_TOKEN','PDC_ARG_HOSTED_GRAFANA_ID','PDC_ARG_CLUSTER','PDC_ARG_LOG_LEVEL','PDC_WORKING_DIR','PDC_LOG_DIR'
foreach ($v in $envvars)
{
    if (Test-Path env:$($v)) {
        $tokenVal = [System.Environment]::GetEnvironmentVariable($v)
        Write-Output "✓ Environment Variable $v exists as $tokenVal"
    } else {
        Write-Output "✘ Environment Variable $v not found, please run the setenvvars.ps1 script."
        exit(1)
    }
}

# Powershell 7 exists in the correct location
$filePath = "C:\Program Files\WindowsPowerShell\7\pwsh.exe"
if (Test-Path -Path $filePath -PathType Leaf) {
    Write-Output "✓ PowerShell pwsh.exe exists at $filePath."
} else {
    Write-Output "✘ PowerShell pwsh.exe not found at $filePath"
    exit(1)
}

# check if PDC directory exists
$pdcPath = [System.Environment]::GetEnvironmentVariable("PDC_WORKING_DIR") # default - "C:\Program Files\GrafanaLabs\PDC"
$dirPath = $pdcPath
if (Test-Path -Path $dirPath) {
    Write-Output "✓ The PDC folder exists at $dirPath"
} else {
    Write-Output "✘ The PDC folder not found at $dirPath"
    exit(1)
}

# check if pdc.exe file exists
$filePath = "$pdcPath\pdc.exe"
if (Test-Path -Path $filePath -PathType Leaf) {
    Write-Output "✓ Grafana PDC pdc.exe exists at $filePath."
} else {
    Write-Output "✘ Grafana PDC pdc.exe not found at $filePath"
    exit(1)
}

# check if PDC Logs directory exists
$pdcLogPath = [System.Environment]::GetEnvironmentVariable("PDC_LOG_DIR") # default - "C:\Program Files\GrafanaLabs\PDC\Logs"
$dirPath = $pdcLogPath
if (Test-Path -Path $dirPath) {
    Write-Output "✓ The PDC Logs folder exists at $dirPath"
} else {
    Write-Output "✘ The PDC Logs folder not found at $dirPath"
    exit(1)
}

# check that start_pdc.ps1 exists
$filePath = "$pdcPath\start_pdc.ps1"
if (Test-Path -Path $filePath -PathType Leaf) {
    Write-Output "✓ Grafana start_pdc.ps1 exists at $filePath."
} else {
    Write-Output "✘ Grafana start_pdc.ps1 not found at $filePath"
    exit(1)
}

# check that scheduletask.ps1 exists
$filePath = "$pdcPath\scheduletask.ps1"
if (Test-Path -Path $filePath -PathType Leaf) {
    Write-Output "✓ Grafana scheduletask.ps1 exists at $filePath."
} else {
    Write-Output "✘ Grafana scheduletask.ps1 not found at $filePath"
    exit(1)
}

# try starting the PDC process
Start-Process -FilePath '.\pdc.exe' `
    -ArgumentList "-token $env:PDC_ARG_PDC_TOKEN","-cluster $env:PDC_ARG_CLUSTER","-gcloud-hosted-grafana-id $env:PDC_ARG_HOSTED_GRAFANA_ID","-log.level $env:PDC_ARG_LOG_LEVEL" `
    -WorkingDirectory "$env:PDC_WORKING_DIR" `
    -NoNewWindow `
    -RedirectStandardOutput "$env:PDC_LOG_DIR\stdout.txt" `
    -RedirectStandardError "$env:PDC_LOG_DIR\stderr.txt" 

# Test if the PDC process started
$pdc_process = Get-Process | Where-Object { $_.ProcessName -eq "pdc" } 

if ($pdc_process) {
    Write-Output "✓ The PDC process is running"
} else {
    Write-Output "✘ The PDC process failed"
    exit(1)
}

$logFile = "$pdcLogPath\stdout.txt"
$pattern = "This is Grafana Private Datasource Connect!"
$timeOutSec = 30
$found = $false
$timeOutTime = (Get-Date).AddSeconds($timeOutSec)
while (-not $found -and ((Get-Date) -lt $timeOutTime)) {
    $content = Get-Content -Path $logFile -Raw -ErrorAction SilentlyContinue
    if ($content -match $pattern) {
        $found = $true
        Write-Output "✓ The PDC process connected successfully"
    }
}
if (-not $found) {
    Write-Output "✘ The PDC process failed to connect"
}

# kill the pdc.exe process created above
if ($pdc_process) {
    $pdc_process | Stop-Process -Force
    Write-Output "✓ The PDC process has been stopped"
}
Remove-Variable pdc_process