#requires -PSEdition Core

# Helper Functions
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor                                # save the current color
    $host.UI.RawUI.ForegroundColor = $ForegroundColor                   # set the new color
    if ($args) { Write-Output $args } else { $input | Write-Output }    # output
    $host.UI.RawUI.ForegroundColor = $fc                                # restore the original color
}

Clear-Host
Write-ColorOutput red (" ")
Write-ColorOutput red ("=========================================================================================")
Write-ColorOutput red ("|              This script will grant SYSTEM access to the PDC Logs                     |")
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

Write-ColorOutput blue (". Getting the Grafana Alloy Service")
$serviceName = "Alloy"                                                                  # Replace with the actual service name if different
$logsDirectory = "C:\Program Files\GrafanaLabs\PDC\Logs"

$service = Get-Service -Name $serviceName

if ($service) {
    Write-ColorOutput green ("✔  - Found the Alloy Service")
    Write-ColorOutput blue (". Getting the Grafana Alloy Service Username")
    $userName = $service.UserName
    if ($userName) {
        Write-ColorOutput green ("✔  - Found the Alloy Service Username")
        Write-ColorOutput blue ("     The $serviceName service is running as: $userName")
        if ($userName -eq "LocalSystem") {

            Write-ColorOutput blue (". Getting the files in the logs directory")
            $files = Get-ChildItem -Path $logsDirectory -File
            foreach ($file in $files) {
                try{
                    Write-ColorOutput blue (". Found $($file.FullName)")
                    $acl = Get-Acl -Path $file.FullName
                    if ($userName -eq "LocalSystem") {
                        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "FullControl", "Allow")
                    } else {
                        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($userName, "FullControl", "Allow")
                    }
                    $acl.SetAccessRule($accessRule)
                    Set-Acl -Path $file.FullName -AclObject $acl
                    Write-ColorOutput green ("✔  - Granted read permission to $userName for $($file.FullName)")
                } catch {
                    Write-ColorOutput red ("×  - Failed to modify ACL for $($file.FullName): $_")
                }
            }
        }
    } else {
        Write-ColorOutput red ("×  - Unable to determine the service account for $serviceName.")
    }
} else {
    Write-ColorOutput red ("×  - Service '$serviceName' not found.")
}
