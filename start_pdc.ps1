# Edit these two first three variables to match your environment
[System.Environment]::SetEnvironmentVariable('PDC_ARG_PDC_TOKEN', '<YOUR_PDC_TOKEN>')
[System.Environment]::SetEnvironmentVariable('PDC_ARG_HOSTED_GRAFANA_ID', '<YOUR_HOSTED_GRAFANA_ID>')
[System.Environment]::SetEnvironmentVariable('PDC_ARG_CLUSTER', '<YOUR_CLUSTER_ADDRESS>')
# Do no edit below this line
[System.Environment]::SetEnvironmentVariable('PDC_ARG_LOG_LEVEL', 'debug')
[System.Environment]::SetEnvironmentVariable('PDC_WORKING_DIR', 'C:\Program Files\GrafanaLabs\PDC')
[System.Environment]::SetEnvironmentVariable('PDC_LOG_DIR', 'C:\Program Files\GrafanaLabs\PDC\Logs')
Start-Process -FilePath '.\pdc.exe' `
    -ArgumentList "-token $env:PDC_ARG_PDC_TOKEN","-cluster $env:PDC_ARG_CLUSTER","-gcloud-hosted-grafana-id $env:PDC_ARG_HOSTED_GRAFANA_ID","-log.level $env:PDC_ARG_LOG_LEVEL" `
    -WorkingDirectory "$env:PDC_WORKING_DIR" `
    -RedirectStandardOutput "$env:PDC_LOG_DIR\stdout.log" `
    -RedirectStandardError "$env:PDC_LOG_DIR\stderr.log"
