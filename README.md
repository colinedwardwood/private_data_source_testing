# Grafana Private Data Source Connect Testing

This is a repository for testing the private data source connect (PDC) feature from Grafana in a Windows environment.

## Prerequisites

* A windows machine with:  

  * Powershell 7+ installed  
  * The OpenSSH version is 9.2 or higher on the server the PDC agent was deployed to.

* A Grafana Cloud account - they have a free tier that you can use for testing.

## Setup Your Windows Environment

### Install Grafana Alloy

We're going to use the Grafana Windows Integration to collect Metrics and Logs from the Windows machine. Grafana Cloud provides detailed instructions. Navigate to Connections in the left hand menu of your Grafana Cloud instance. This will take you to the "Add New Connection" page.  

Once on the Add New Connection page, search for Windows and click on the Windows tile. This will take you to the Windows Integration page.  

From here we will follow the instructions to install Grafana Alloy on the Windows machine. Make sure to select "Include logs."  

Once these steps are complete, you should be able to see the details of the Windows machine in the Windows Integration dashboards.  

### Install and Configure InfluxDB as a Local Data Source  

Private Data Source Connect (PDC) is a feature that allows you to connect Grafana to your private data sources. In this example, we will use InfluxDB as a local data source.

#### Install InfluxDB

##### Download Influx

Navigate here in your webbrowser and download Influx for Windows

<https://docs.influxdata.com/influxdb/v2/install/?t=Windows#>

##### Expand the Archive

Navigate to your download directory, typically the Downloads folder.  

```powershell
cd "$env:USERPROFILE\Downloads"
```

Expand the archive.  

```powershell
Expand-Archive .\influxdb2-2.7.6-windows.zip -DestinationPath 'C:\Program Files\InfluxData\'  
mv 'C:\Program Files\InfluxData\influxdb2-2.7.6' 'C:\Program Files\InfluxData\influxdb'  
```

##### Prep a Logging Directory

```powershell
mkdir C:\Program Files\InfluxData\Logs  
```

##### Start InfluxDB in the Background

Navigate to the program directory.  

```powershell
cd 'C:\Program Files\InfluxData'
```

Start the process.  

```powershell
Start-Process `
    -FilePath '.\influxd.exe'`
    -WorkingDirectory 'C:\Program Files\InfluxData'`
    -WindowStyle Hidden`
    -RedirectStandardOutput 'C:\Program Files\InfluxData\Logs\stdout.log'`
    -RedirectStandardError 'C:\Program Files\InfluxData\Logs\stderr.log'
```

#### Configure InfluxDB

1. Navigate to:
  <http://localhost:8086/>

2. Click "Get Started"  

Enter details:  

* Username: "myuser"  
* Password: "mypassword"  
* Initial Organization Name: "myorg"  
* Initial Bucket Name: "mybucket"  

Click "Continue"  
Copy the Operator Token:  `<operator_token>`  
Click "Configure Later"

### Install and Configure Influx CLI

#### Download InfluxCLI

Navigate to:

<https://download.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-windows-amd64.zip?_gl=1*k7422g*_ga*NjIwNzY3MTE2LjE3MTg5ODgzNjM.*_ga_CNWQ54SDD8*MTcxODk4ODM2My4xLjEuMTcxODk4OTg4Ni41OS4wLjE0NDU4NzQ0NTY.*_gcl_au*MTEyNzY2NjMwNS4xNzE4OTg4OTUz>

#### Install InfluxCLI

```powershell
Expand-Archive .\influxdb2-client-2.7.5-windows-amd64.zip -DestinationPath 'C:\Program Files\InfluxData\'  
mv 'C:\Program Files\InfluxData\influxdb2-client-2.7.5-windows-amd64' 'C:\Program Files\InfluxData\influx'  
```

#### Configure InfluxCLI  

```powershell
./influx config create --config-name myconfig `
  -u 'http://localhost:8086' `
  -o 'myorg' `
  -t '<operator_token>' `
  -a
```

The parameters represent:  

* `-u` is the InfluxDB URL.  
* `-o` is the organization name
* `-t` is the operator_token we generated above
* `-a` sets this as the active configuration for the cli

#### Create an All Access Token  

We will use this token to connect to InfluxDB from Grafana.  

```powershell
./influx auth create --org myorg --all-access  
```

Output  

```Powershell
"<all_access_token>"
```

### Load Sample Influx Data  

In order to test the connection between Grafana and InfluxDB, we will need a sample data set to query.

Download the sample data set.  

```powershell
curl https://s3.amazonaws.com/noaa.water-database/NOAA_data.txt -o NOAA_data.txt  
```

Load the sample data into InfluxDB.  

```powershell
./influx write -b "mybucket" -o "myorg" -p "s" --format="lp" -f "./NOAA_data.txt"
```  

### Install Grafana Private Data Source Connect

#### Create a PDC Token

<https://grafana.com/docs/grafana-cloud/connect-externally-hosted/private-data-source-connect/configure-pdc/>  

In Grafana, go to Connections > Private data source connections and click the Configuration Details tab.

Select your installation method and follow the instructions on the screen, or generate an API key and follow the remaining instructions below. You will need the following environment variables from your instance:

* GCLOUD_PDC_SIGNING_TOKEN set to the API token value generated in your Grafana Cloud instance. This is shown as token in the configuration instructions in the Private data source configuration page.
* GCLOUD_HOSTED_GRAFANA_ID the ID of your Grafana Cloud instance. This is shown as gcloud-hosted-grafana-id in the configuration instructions in the Private data source configuration page.
* GCLOUD_PDC_CLUSTER the cluster for your Private data source connections. This is shown as cluster in the configuration instructions in the Private data source configuration page.

#### Download Private Data Source Connect  

We're going to be deploying Private Data Source Connect (PDC) to the Windows machine. We can download the Windows version of PDC from <https://github.com/grafana/pdc-agent/releases/latest>

#### Place PDC

To keep things simple, we will create a directory for the PDC along side the Alloy directory in `C:\Program Files\GrafanaLabs\`.  

Run the following commands to create the directory and move the PDC executable into it.  

```powershell
mkdir 'C:\Program Files\GrafanaLabs\PDC'
mv .\pdc.exe 'C:\Program Files\GrafanaLabs\PDC\'
```

#### Create a Log Directory for PDC

We want to run PDC in the background, so we will need to create a log directory for it.  

```powershell
mkdir 'C:\Program Files\GrafanaLabs\PDC\Logs'
```

#### Launch PDC as Scheduled Task

We want to launch the PDC every time this machine starts. So we'll use Windows Task Scheduler to achieve this. We want to launch the tast in the background but still have access to its stdout and stderr. For this, we can use the Pwershell `Start-Process` cmdlet.  

First, let's create a script that will launch the PDC. In the script we should set the environment variables for the PDC token, cluster, and hosted Grafana ID. Then we will set some standard location environment variables for the PDC working directory and log directory. Finally, we will define the command to launch the PDC in the background.  

```powershell
New-Item -Path 'C:\Program Files\GrafanaLabs\PDC\start_pdc.ps1' -ItemType File
```

Edit the file `C:\Program Files\GrafanaLabs\PDC\start_pdc.ps1` to look like this:  

```powershell
# Edit these two first three variables to match your environment
[System.Environment]::SetEnvironmentVariable('PDC_ARG_PDC_TOKEN', '<your_pdc_token>')
[System.Environment]::SetEnvironmentVariable('PDC_ARG_HOSTED_GRAFANA_ID', '<your_hosted_grafana_id>')
[System.Environment]::SetEnvironmentVariable('PDC_ARG_CLUSTER', '<your_cluster_id>')
# Do no edit below this line
[System.Environment]::SetEnvironmentVariable('PDC_ARG_LOG_LEVEL', 'debug')
[System.Environment]::SetEnvironmentVariable('PDC_WORKING_DIR', 'C:\Program Files\GrafanaLabs\PDC')
[System.Environment]::SetEnvironmentVariable('PDC_LOG_DIR', 'C:\Program Files\GrafanaLabs\PDC\Logs')
Start-Process -FilePath '.\pdc.exe' `
    -ArgumentList "-token $env:PDC_ARG_PDC_TOKEN","-cluster $env:PDC_ARG_CLUSTER","-gcloud-hosted-grafana-id $env:PDC_ARG_HOSTED_GRAFANA_ID","-log.level $env:PDC_ARG_LOG_LEVEL" `
    -WorkingDirectory "$env:PDC_WORKING_DIR" `
    -RedirectStandardOutput "$env:PDC_LOG_DIR\stdout.log" `
    -RedirectStandardError "$env:PDC_LOG_DIR\stderr.log"
```

Now that we have the script to launch the PDC, we can create a scheduled task to run it.  Let's create a small script to create the scheduled task. We will use the `New-ScheduledTask` cmdlet to create the empty file.

```powershell
New-Item -Path 'C:\Program Files\GrafanaLabs\PDC\schedulepdc.ps1' -ItemType File
```

Edit the file `C:\Program Files\GrafanaLabs\PDC\schedulepdc.ps1` to look like this:  

```powershell
$taskActions = New-ScheduledTaskAction `
                -Execute "./pwsh" `
                -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle None -File '.\start_pdc.ps1'" `
                -WorkingDirectory 'C:\Program Files\GrafanaLabs\PDC'
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask 'Grafana PDC' -Action $taskActions -Trigger $taskTrigger -Force
```

Now we can simply run the script to create the scheduled task. Then, to make sure the PDC is running, we can simply execute the scheduled task.

```powershell
cd 'C:\Program Files\GrafanaLabs\PDC'
.\schedulepdc.ps1
Start-ScheduledTask -TaskName 'Grafana PDC'
```

Lastly, we can test the PDC started successfully in several ways. We can check the logs in `C:\Program Files\GrafanaLabs\PDC\Logs\` or we can check the status of the PDC in Grafana Cloud. First, I want to make sure the process started successfully using a quick PowerShell command.

```powershell
Get-Process | Where-Object { $_.ProcessName -eq "pdc" } 
```

This should return a single result with the process name "pdc" and the status "Running."

### Configure InfluxDB as a Data Source in Grafana

Our next step should be to test the PDC. First, in Grafana Cloud, navigate to Home > Connections > Private Data Source Connect.  There you should see the PDC you just deployed with a green status of "agent connected."
Now, let's configure InfluxDB as a data source in Grafana. To do this, navigate to Home > Data Sources and click "Add Data Source" in the top right corner.
From the list of data sources, select InfluxDB.

Populate the following fields:  
Name: `myInfluxDB`  
Query Language: `InfluxQL`  
URL: `http://localhost:8086`  

Custom HTTP Headers:  
Click + Add Header  

Header: `Authorization` Value: `Token <your_all_access_token_created_above>`  
Database: `mybucket`  
HTTP Method: `GET`  
Private Data Source Connect: `<selectyourpdc>`  

Click "Save & Test" to verify the connection.

### Explore the New InfluxDB Data Source

Navigate to Explore in the left hand menu. You should see the new data source in the drop down menu. Select it and you should see a query builder. Click on the pencil at the top right of the query builder to open the query editor.
Paste the following query into the query editor and click "Run Query."

```InfluxQL
SELECT mean("water_level") FROM "h2o_feet" WHERE $timeFilter GROUP BY time($__interval) fill(null)
```

Update the to and from dates in the query range in the top right of the query editor to see the data from the sample data set.  
From: `2019-08-16 19:40:17` To: `2019-09-17 19:06:25`

You should see a graph of the water level over time.

### Monitor the PDC

#### Update the Alloy Configuration  

The first step in monitoring the PDC will be to update the Alloy configuration to monitor the PDC. On our Windows machine, open the file `C:\Program Files\GrafanaLabs\Alloy\config.alloy` as an Adminitrator for editing.

We will add a few blocks to the configuration file.  

##### Collect Windows Process Metrics  

First, we will update the Windows Integration to collect process metrics. Find the block that looks like this:  

```alloy
prometheus.exporter.windows "integrations_windows_exporter" {
  enabled_collectors = ["cpu", "cs", "logical_disk", "net", "os", "service", "system", "time", "diskdrive"]
}

and update it to include the process collector.  It should now look like this:

```alloy
prometheus.exporter.windows "integrations_windows_exporter" {
  enabled_collectors = ["cpu", "cs", "logical_disk", "net", "os", "service", "system", "time", "diskdrive", "process"]
}
```

Now we have to make sure that the process metrics we want are kept by updating the following block:  

```alloy
  rule {
    action = "keep"
    regex = "up|windows_cpu_interrupts_total|windows_cpu_time_total|windows_cs_hostname|windows_cs_logical_processors|windows_cs_physical_memory_bytes|windows_disk_drive_status|windows_logical_disk_avg_read_requests_queued|windows_logical_disk_avg_write_requests_queued|windows_logical_disk_free_bytes|windows_logical_disk_idle_seconds_total|windows_logical_disk_read_bytes_total|windows_logical_disk_read_seconds_total|windows_logical_disk_reads_total|windows_logical_disk_size_bytes|windows_logical_disk_write_bytes_total|windows_logical_disk_write_seconds_total|windows_logical_disk_writes_total|windows_net_bytes_received_total|windows_net_bytes_sent_total|windows_net_packets_outbound_discarded_total|windows_net_packets_outbound_errors_total|windows_net_packets_received_discarded_total|windows_net_packets_received_errors_total|windows_net_packets_received_unknown_total|windows_os_info|windows_os_paging_limit_bytes|windows_os_physical_memory_free_bytes|windows_os_timezone|windows_service_status|windows_system_context_switches_total|windows_system_processor_queue_length|windows_system_system_up_time|windows_time_computed_time_offset_seconds|windows_time_ntp_round_trip_delay_seconds"
    source_labels = ["__name__"]
  }
```

We will add the process metrics to the list of metrics to keep, resulting in:

```alloy
  rule {
    action = "keep"
    regex = "up|windows_cpu_interrupts_total|windows_cpu_time_total|windows_cs_hostname|windows_cs_logical_processors|windows_cs_physical_memory_bytes|windows_disk_drive_status|windows_logical_disk_avg_read_requests_queued|windows_logical_disk_avg_write_requests_queued|windows_logical_disk_free_bytes|windows_logical_disk_idle_seconds_total|windows_logical_disk_read_bytes_total|windows_logical_disk_read_seconds_total|windows_logical_disk_reads_total|windows_logical_disk_size_bytes|windows_logical_disk_write_bytes_total|windows_logical_disk_write_seconds_total|windows_logical_disk_writes_total|windows_net_bytes_received_total|windows_net_bytes_sent_total|windows_net_packets_outbound_discarded_total|windows_net_packets_outbound_errors_total|windows_net_packets_received_discarded_total|windows_net_packets_received_errors_total|windows_net_packets_received_unknown_total|windows_os_info|windows_os_paging_limit_bytes|windows_os_physical_memory_free_bytes|windows_os_timezone|windows_service_status|windows_system_context_switches_total|windows_system_processor_queue_length|windows_system_system_up_time|windows_time_computed_time_offset_seconds|windows_time_ntp_round_trip_delay_seconds|windows_process_cpu_time_total|windows_process_io_bytes_total"
    source_labels = ["__name__"]
  }
```

##### Collect PDC Metrics and Logs

The newest build of PDC exposes a metrics endpoint. We can use this endpoint to collect metrics from the PDC. The PDC is writing logs to `C:\Program Files\GrafanaLabs\PDC\Logs\` so we can collect those as well.

Add the following block to the Alloy configuration file:

```alloy
// Private Datasource Connect Components
// - Logs
// Wildcard component to find the log files for the pdc process
local.file_match "pdc_logs" {  // Stage 1 - Wildcard component to find the log files for the pdc process
  path_targets = [
    {__path__ = `C:\Program Files\GrafanaLabs\PDC\Logs\*.log`},
  ]
}
loki.source.file "tmpfiles" {  // Stage 2 - Collect the logs from the location found in stage 1
  forward_to = [loki.process.pdc_logs_labels.receiver]
  targets    = local.file_match.pdc_logs.targets
}
loki.process "pdc_logs_labels" {  // Stage 3 - Add labels to the logs collected in stage 2
  forward_to = [loki.relabel.pdc_logs_labels.receiver]
  stage.logfmt {
    mapping = {
      "level" = "",
    }
  }
  stage.labels {
    values = {
        level = "",
    }
  }
}
loki.relabel "pdc_logs_labels" {
  forward_to = [loki.write.grafana_cloud_loki.receiver]
  rule {
    action = "replace"
    target_label = "instance"
    replacement = constants.hostname
  }
  rule {
    action = "replace"
    target_label = "job"
    replacement = "integration/windows_exporter"
  }
  rule {
    action = "replace"
    target_label = "source"
    replacement = "pdc"
  }
}
// - Metrics
prometheus.scrape "pdc_metrics" {
  forward_to = [prometheus.remote_write.metrics_service.receiver]
  targets = [
    {"__address__" = "localhost:8090", "instance" = constants.hostname, "job" = "integrations/windows_exporter", "source" = "pdc"},
  ]
  scrape_interval = "60s"
  metrics_path = "/metrics" // technically not necessary as the default behaviour is to scrape the /metrics endpoint of the targets defined above
}
```

## Create a Dashboard in Grafana for PDC Monitoring  
