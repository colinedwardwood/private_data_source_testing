#requires -PSEdition Core
$debug = $false; $args -contains '--debug' | ForEach-Object { $debug = $true }

# Helper Functions
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor                                # save the current color
    $host.UI.RawUI.ForegroundColor = $ForegroundColor                   # set the new color
    if ($args) { Write-Output $args } else { $input | Write-Output }    # output
    $host.UI.RawUI.ForegroundColor = $fc                                # restore the original color
}

function exists {
    param([string]$path)
    if (Test-Path -Path $path) {
        Write-ColorOutput green ("✔  - $path was found.")
        return $true
    } else {
        Write-ColorOutput red ("×  - $path was not found.")
        return $false
    }
}

function cleanup {
    try {
        Stop-Process -Name "pdc" -Force -ErrorAction Stop
    } catch {
        if ($debug) { Write-ColorOutput yellow ("DEBUG - ERROR - msg: `"$_`"") }
    }
    try {
        Unregister-ScheduledTask -TaskName 'Grafana PDC' -Confirm:$false -ErrorAction Stop
    } catch {
        if ($debug) { Write-ColorOutput yellow ("DEBUG - ERROR - msg: `"$_`"") }
    }
    # Add verification of cleanup
    try {
        $process = Get-Process -Name "pdc" -ErrorAction Stop
        Write-ColorOutput red ("×  -  The PDC Process is still running")
    } catch {
        if ($debug) { Write-ColorOutput yellow ("DEBUG - INFO - The PDC Process stopped") }
    }
    try {
        $task = Get-ScheduledTask -TaskName 'Grafana PDC' -ErrorAction Stop
        Write-ColorOutput red ("×  -  The Grafana PDC Scheduled Task still exists")
    
    } catch {
        Write-ColorOutput yellow ("DEBUG - INFO - The Grafana PDC scheduled task has been removed")
    }
}

function downloadPDC {
    # Prompt the user
    $response = Read-Host "Would you like to download it? [Y]es or [N]o"

    # Convert the response to uppercase for comparison
    $response = $response.ToUpper()

    if ($response -eq 'Y') {
        # Define variables
        $url = "https://github.com/grafana/pdc-agent/releases/download/v0.0.30/pdc-agent_Windows_x86_64.zip"
        $zipFilePath = "$pdcPath\pdc-agent.zip"
        $extractPath = "($pdcPath\pdc-agent"
        $destinationDir = "C:\Program Files\GrafanaLabs\PDC\"
        $exeFileName = "pdc.exe"

        # Download the file
        Invoke-WebRequest -Uri $url -OutFile $zipFilePath

        # Unzip the file
        Expand-Archive -Path $zipFilePath -DestinationPath $extractPath

         # Copy the pdc.exe file to the destination directory
        Copy-Item -Path (Join-Path -Path $extractPath -ChildPath $exeFileName) -Destination $destinationDir
        Write-ColorOutput blue ("pdc.exe has been copied to $destinationDir")
    } else {
        Write-ColorOutput blue ("Download cancelled.")
    }
}

function createFolder {
    param(
        [string]$folderPath
    )

    if (-Not (Test-Path -Path $folderPath)) {
        try {
            New-Item -ItemType Directory -Path $folderPath -Force
            Write-ColorOutput green ("✔  - Created folder: $folderPath")
            return $true
        } catch {
            Write-ColorOutput red ("×  - Failed to create folder: $folderPath. Error: $_") -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host ("✔  - Folder already exists: $folderPath") -ForegroundColor Green
        return $true
    }
}

function Show-ACLInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$file
    )

    try {
        $acl = Get-Acl -Path $file -ErrorAction Stop
        $accessRules = $acl.Access

        foreach ($rule in $accessRules) {
            $userName = $rule.IdentityReference.Value
            Write-Output "User: $userName"
        }
    } catch {
        Write-Output "Failed to retrieve ACL for $file : $_"
    }
}

function fixPermissions {
    $file = "C:\Windows\System32\config\systemprofile\.ssh\grafana_pdc"
    Write-Output " "
    Write-ColorOutput blue ("Setting ACL for:")
    Write-ColorOutput blue ("$file")
    Write-Output " "
    Write-ColorOutput blue ("Current ACL for:")
    Write-ColorOutput blue ("$file")
    Show-ACLInfo -file $file
    Write-Output (" ")
    Write-ColorOutput blue ("Trying to apply new ACL")
    try {
        # Create a new ACL object
        $acl = New-Object System.Security.AccessControl.FileSecurity
    
        # Remove all existing access rules
        $acl.SetAccessRuleProtection($true, $false) # Protects the ACL from inheritance but preserves existing rules
        $acl.Access | ForEach-Object {
            $acl.RemoveAccessRule($_)
        }
    
        # Add permission for the specified user
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "FullControl", "Allow")
        $acl.AddAccessRule($accessRule)
    
        # Set the modified ACL to the file
        Set-Acl -Path $file -AclObject $acl -ErrorAction Stop
         Write-ColorOutput green ("✔  - Successfully adjusted permissions for $file")
    } catch {
        Write-ColorOutput red ("×  - Failed to adjust permissions for $file : $_")
    }
    Write-Output " "
    Write-ColorOutput blue ("Current ACL for:")
    Write-ColorOutput blue ("$file")
    Show-ACLInfo -file $file
}

function testConnection {
    # Test if the PDC process connected
    $logFilePath = "$pdcLogPath\stdout.txt"
    $found = $false
    $successPattern = "This is Grafana Private Datasource Connect!"
    $timeOutSec = 30
    $timeOutTime = (Get-Date).AddSeconds($timeOutSec)

    $fileStream = [System.IO.File]::Open($logFilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $streamReader = [System.IO.StreamReader]::new($fileStream)
    
   
    while (-not $found -and ((Get-Date) -lt $timeOutTime)) {
        while ($streamReader.Peek() -ge 0) {
            $line = $streamReader.ReadLine()
            if ($line -match "parsed flags") { # parsed flags
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"$msgPart`"")
            }
            elseif ($line -match "sshversion") { # ssh version
                $msgPart = $line -replace "^.*sshversion=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"$msgPart`"")
            }
            elseif ($line -match "Connecting to") { # connecting to
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"$msgPart`"")
            }
            elseif ($line -match "Connection established") { # connection established
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"$msgPart`"")
            }
            elseif ($line -match "Host '.*' is known and matches the .* host certificate") { # host matches
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"$msgPart`"")
            }
            elseif ($line -match "send packet: type 20") { # Key exchange begins by each side sending SSH_MSG_KEXINIT
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"SSH_MSG_KEXINIT - BEGIN Key Exchange`"")             
            }
            elseif ($line -match "SSH_MSG_NEWKEYS received") { # Key exchange ends by each side sending an SSH_MSG_NEWKEYS message.
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"SSH_MSG_KEXINIT - END Key Exchange`"")
                fixPermissions
            } 
            elseif ($line -match "receive packet: type 6") { # After the key exchange, the client requests a service. 
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"SSH_MSG_SERVICE_REQUEST - BEGIN Service Request`"")
            }
            elseif ($line -match "send packet: type 50") { # After the service request, an auth request is sent.
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"SSH_MSG_USERAUTH_REQUEST - BEGIN Auth Request`"")
            }          
            elseif ($line -match "receive packet: type 51") { # Auth failure SSH_MSG_USERAUTH_FAILURE.
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"SSH_MSG_USERAUTH_FAILURE - Failed to Authenticate`"")
            }
            elseif ($line -match "Bad permissions") { # bad permissions
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"$msgPart`"")
                fixPermissions
            }
            elseif ($line -match "No more authentication methods to try.") { # Final auth failure no more methods to try.
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"SSH_MSG_USERAUTH_FAILURE - No more authentication methods to try.`"")
            }
            elseif ($line -match "ssh client exited. restarting") { # Client restart
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"SSH Client Restarting`"")
            }
            elseif ($line -match "receive packet: type 52") { # Auth success SSH_MSG_USERAUTH_SUCCESS.
                $msgPart = $line -replace "^.*msg=`"([^`"]+)`".*$", '$1'
                Write-ColorOutput yellow ("DEBUG - INFO - msg:`"SSH_MSG_USERAUTH_SUCCESS - Auth Success`"")
            }
            elseif ($line -match $successPattern) {
                $found = $true
                Write-ColorOutput green ("✔  - The PDC process connected successfully")
                break
            }
        }
        Start-Sleep -Seconds 1
    }
    $streamReader.Close()
    $fileStream.Close()
    if (-not $found) {
        Write-ColorOutput red ("×  - The PDC process failed to connect")
    }
}


$scriptStart = (Get-Date)
Clear-Host
Write-ColorOutput red (" ")
Write-ColorOutput red ("=========================================================================================")
Write-ColorOutput red ("|                              This script is destructive!                              |")
Write-ColorOutput red ("| It will:                                                                              |")
Write-ColorOutput red ("| - remove and existing scheduled task named 'Grafana PDC'                              |")
Write-ColorOutput red ("| - stop any running task named 'pdc'                                                   |")
Write-ColorOutput red ("| - remove any exists ssh keys that match grafana_pdc*                                  |")
Write-ColorOutput red ("=========================================================================================")
Write-ColorOutput red (" ")
$done = $false
do {
    $accept = Read-Host "  Would you like to continue? [Y]es or [n]o"
    switch ($accept.ToUpper()) {
        
        'Y' { Write-Output "  Continuing..."; $done = $true }
        'n' { Write-Output "  Exiting..."; exit }
        default { Write-Output "Invalid input. Please press 'Y' to continue or 'N' to exit." }
    }
} while (!$done)

Write-ColorOutput blue (" ")
Write-ColorOutput blue ("==== Beginning clean up +++==============================================================")
Write-ColorOutput blue (". Stopping any existing PDC processes and removing existing scheduled pdc tasks")

# Do Quick Cleanup
cleanup


Write-ColorOutput blue (" ")
Write-ColorOutput blue ("==== Beginning setup tests ==============================================================")
Write-ColorOutput blue (". Checking that the necessary envvar, paths and files exist.")



# Check if necessary env-vars exist.
$envvars = 'PDC_ARG_PDC_TOKEN','PDC_ARG_HOSTED_GRAFANA_ID','PDC_ARG_CLUSTER','PDC_ARG_LOG_LEVEL','PDC_WORKING_DIR','PDC_LOG_DIR'
foreach ($v in $envvars) {
    if (Test-Path env:$($v)) {
        $tokenVal = [System.Environment]::GetEnvironmentVariable($v)
        Write-ColorOutput green ("✔  - Environment Variable $v exists as $tokenVal")
    } else {
        Write-ColorOutput red ("×  - Environment Variable $v not found, please run the setenvvars.ps1 script.")
        exit(1)
    }
}

# check if PDC directory exists
$pdcPath = [System.Environment]::GetEnvironmentVariable("PDC_WORKING_DIR") # default - "C:\Program Files\GrafanaLabs\PDC"
if (-not (exists($pdcPath))) {
    if ($debug) { Write-ColorOutput yellow ("DEBUG - INFO - msg: `"The PDC Folder was not found. Creating it`"") }
    createFolder($pdcPath)
}

# check if pdc.exe file exists
$filePath = "$pdcPath\pdc.exe"
if (-not (exists($filePath))) {
    if ($debug) { Write-ColorOutput yellow ("DEBUG - INFO - msg: `"The pdc.exe was not found asking for download`"") }
    downloadPDC
}

# check if PDC Logs directory exists
$pdcLogPath = [System.Environment]::GetEnvironmentVariable("PDC_LOG_DIR") # default - "C:\Program Files\GrafanaLabs\PDC\Logs"
if (-not (exists($pdcLogPath))) {
    if ($debug) { Write-ColorOutput yellow ("DEBUG - INFO - msg: `"The PDC Folder was not found. Creating it`"") }
    createFolder($pdcLogPath)
}

# check that start_pdc.ps1 exists
$pdcFilePath = "$pdcPath\start_pdc.ps1"
if (-not (exists($pdcFilePath))) {
    Write-ColorOutput red ("Please place the 'start_pdc.ps1' script in $pdcPath")
}

Write-ColorOutput blue (" ")
Write-ColorOutput blue ("==== Setup tests complete, beginning unit tests ==============================================================")
Write-ColorOutput blue (". Checking that the PDC will start and connect successfully.")

# try starting the PDC process directly
if ($debug) {
    Write-ColorOutput yellow ("DEBUG - INFO - msg: `"Executing Start-Process with the following options:`"") 
    Write-ColorOutput yellow ("DEBUG - INFO - msg: `"Start-Process`"") 
    Write-ColorOutput yellow ("DEBUG - INFO - msg: `"-FilePath '.\pdc.exe'`"") 
    Write-ColorOutput yellow ("DEBUG - INFO - msg: `"-token $env:PDC_ARG_PDC_TOKEN`"") 
    Write-ColorOutput yellow ("DEBUG - INFO - msg: `"-cluster $env:PDC_ARG_CLUSTER`"") 
    Write-ColorOutput yellow ("DEBUG - INFO - msg: `"-gcloud-hosted-grafana-id $env:PDC_ARG_HOSTED_GRAFANA_ID`"") 
    Write-ColorOutput yellow ("DEBUG - INFO - msg: `"-log.level $env:PDC_ARG_LOG_LEVEL`"") 
    Write-ColorOutput yellow ("DEBUG - INFO - msg: `"-NoNewWindow`"") 
    Write-ColorOutput yellow ("DEBUG - INFO - msg: `"-RedirectStandardOutput `"$env:PDC_LOG_DIR\stdout.txt`"`"")
    Write-ColorOutput yellow ("DEBUG - INFO - msg: `"-RedirectStandardError `"$env:PDC_LOG_DIR\stderr.txt`"`"") 
}
Start-Process -FilePath '.\pdc.exe' `
    -ArgumentList "-token $env:PDC_ARG_PDC_TOKEN","-cluster $env:PDC_ARG_CLUSTER","-gcloud-hosted-grafana-id $env:PDC_ARG_HOSTED_GRAFANA_ID","-log.level $env:PDC_ARG_LOG_LEVEL" `
    -WorkingDirectory "$env:PDC_WORKING_DIR" `
    -NoNewWindow `
    -RedirectStandardOutput "$env:PDC_LOG_DIR\stdout.txt" `
    -RedirectStandardError "$env:PDC_LOG_DIR\stderr.txt" 

# Test if the PDC process started
$pdc_process =  Get-Process | Where-Object { $_.ProcessName -eq "pdc" } 
if ($pdc_process) {
     Write-ColorOutput green ("✔  - The PDC process is running")
} else {
    Write-ColorOutput red ("×  - The PDC process failed")
    exit(1)
}

# Test if the PDC process connected
testConnection

# kill the pdc.exe process created above

if ($pdc_process) {
    $pdc_process | Stop-Process -Force
    Write-ColorOutput green ("✔  - The test PDC process has been stopped")
}
Remove-Variable pdc_process


Write-ColorOutput blue (" ")
Write-ColorOutput blue ("==== Unit tests complete, beginning integration tests ========================================================")

# Create the scheduled task ################################
Write-ColorOutput blue (". Scheduling Grafana PDC task") 

$pwsh = (Get-Process -Id $PID).Path

$taskName = "Grafana PDC"
$taskSettings = New-ScheduledTaskSettingsSet
$taskSettings.ExecutionTimeLimit = 'PT0S'
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskAction = New-ScheduledTaskAction `
                -Execute "$pwsh" `
                -Argument "-NoProfile -ExecutionPolicy Bypass  -File `"$pdcFilePath`"" `
                -WorkingDirectory "$pdcPath"
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Principal $taskPrincipal -AsJob -Force > $null

# Check the scheduled task 
Start-Sleep -Seconds 2
$task = Get-ScheduledTask -TaskName 'Grafana PDC'
# Check if the scheduled task exists
if ($task) {
    Write-ColorOutput green ("✔  - The PDC task was scheduled successfully")
} else {
    Write-ColorOutput red ("×  - The PDC task was not scheduled")
    exit(1)
}

# Show windows event logs for the scheduled task
Start-Sleep -Seconds 2                                              # let the log populate, it takes a moment
$startdate = $scriptStart                                           # search between the start of the script and now for task scheduler events
$enddate = (Get-Date)
Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-TaskScheduler/Operational'
    StartTime = $startdate
    EndTime = $enddate
} | Where-Object -Property Message -Match "PDC" | ForEach-Object {"     $($_.TimeCreated) - $($_.Message)"}
# Show the PDC User
$user = $task.Principal.UserId
Write-ColorOutput green ("✔  - The Grafana PDC task will be run as $user")

# Start-ScheduledTask -TaskName 'Grafana PDC'
Write-ColorOutput blue (". Starting the scheduled Grafana PDC task")  # ================================================================
Start-ScheduledTask -TaskName 'Grafana PDC'
Start-Sleep -Seconds 2                                               # let the task start

# ssh seems to apply wrong permissions to file so it won't connect, remove the extra permissions
$file = "C:\Windows\System32\config\systemprofile\.ssh\grafana_pdc"     # target file
# if (Test-Path -Path $file) {
$acl = Get-Acl -Path $file                                              # get current acl of file
$acl.Access | ForEach-Object { $acl.RemoveAccessRule($_)| Out-Null }              # Remove existing permissions

# Add permission for SYSTEM
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl","None", "None", "Allow")
$acl.AddAccessRule($accessRule) | Out-Null
Set-Acl -Path $file -AclObject $acl -ErrorAction SilentlyContinue | Out-Null  # Apply the modified ACL to the file
Start-Sleep -Seconds 8
# }

# Test if the PDC process started
$pdc_process = Get-Process | Where-Object { $_.ProcessName -eq "pdc" } 

if ($pdc_process) {
    Write-ColorOutput green ("✔  - The PDC process is running")
} else {
    Write-ColorOutput red ("×  - The PDC process failed")
    exit(1)
}

# Test if the PDC process connected
testConnection


Write-ColorOutput blue ("==== Setup complete ==========================================================================================")
Write-ColorOutput blue ("| The Grafana PDC task should now be:                                                                        |")
Write-ColorOutput blue ("| - Scheduled to run as SYSTEM at system startup                                                             |")
Write-ColorOutput blue ("| - Currently running and connected to Grafana Cloud                                                         |")
Write-ColorOutput blue ("==============================================================================================================")
