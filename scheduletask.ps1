$taskActions = New-ScheduledTaskAction `
                -Execute "./pwsh" `
                -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle None -File '.\start_pdc.ps1'" `
                -WorkingDirectory 'C:\Program Files\GrafanaLabs\PDC'
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask 'Grafana PDC' -Action $taskActions -Trigger $taskTrigger -Force
