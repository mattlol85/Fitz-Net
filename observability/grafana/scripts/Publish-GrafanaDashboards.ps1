param(
    [string]$GrafanaUrl = "https://logs.fitznet.org",
    [string]$Username = $env:FITZNET_GRAFANA_USERNAME,
    [string]$Password = $env:FITZNET_GRAFANA_PASSWORD
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
    throw "Grafana credentials are required. Set FITZNET_GRAFANA_USERNAME and FITZNET_GRAFANA_PASSWORD or pass -Username and -Password."
}

$baseUrl = $GrafanaUrl.TrimEnd("/")
$basicToken = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $Username, $Password)))
$headers = @{
    Authorization = "Basic $basicToken"
    Accept = "application/json"
}

function Invoke-GrafanaApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [object]$Body
    )

    $request = @{
        Method = $Method
        Uri = "$baseUrl$Path"
        Headers = $headers
    }

    if ($null -ne $Body) {
        $request.ContentType = "application/json"
        $request.Body = $Body | ConvertTo-Json -Depth 100
    }

    Invoke-RestMethod @request
}

function New-AnnotationList {
    @(
        @{
            builtIn = 1
            datasource = @{
                type = "grafana"
                uid = "-- Grafana --"
            }
            enable = $true
            hide = $true
            iconColor = "rgba(0, 211, 255, 1)"
            name = "Annotations & Alerts"
            type = "dashboard"
        }
    )
}

function New-ReduceOptions {
    @{
        values = $false
        calcs = @("lastNotNull")
        fields = ""
    }
}

function New-DatasourceRef {
    param(
        [string]$Uid,
        [string]$Type
    )

    @{
        uid = $Uid
        type = $Type
    }
}

function New-Target {
    param(
        [string]$RefId,
        [string]$Expr,
        [string]$LegendFormat = "",
        [string]$QueryType = ""
    )

    $target = @{
        refId = $RefId
        editorMode = "code"
        expr = $Expr
        legendFormat = $LegendFormat
    }

    if (-not [string]::IsNullOrWhiteSpace($QueryType)) {
        $target.queryType = $QueryType
    }

    $target
}

function New-StatPanel {
    param(
        [int]$Id,
        [string]$Title,
        [hashtable]$Datasource,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [array]$Targets,
        [string]$Unit,
        [array]$ThresholdSteps,
        [array]$Mappings = @()
    )

    @{
        id = $Id
        title = $Title
        type = "stat"
        datasource = $Datasource
        gridPos = @{
            h = $Height
            w = $Width
            x = $X
            y = $Y
        }
        targets = $Targets
        fieldConfig = @{
            defaults = @{
                unit = $Unit
                color = @{
                    mode = "thresholds"
                }
                thresholds = @{
                    mode = "absolute"
                    steps = $ThresholdSteps
                }
                mappings = $Mappings
            }
            overrides = @()
        }
        options = @{
            reduceOptions = New-ReduceOptions
            orientation = "auto"
            textMode = "auto"
            colorMode = "background"
            graphMode = "none"
            justifyMode = "auto"
        }
    }
}

function New-TimeSeriesPanel {
    param(
        [int]$Id,
        [string]$Title,
        [hashtable]$Datasource,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [array]$Targets,
        [string]$Unit = "short"
    )

    @{
        id = $Id
        title = $Title
        type = "timeseries"
        datasource = $Datasource
        gridPos = @{
            h = $Height
            w = $Width
            x = $X
            y = $Y
        }
        targets = $Targets
        fieldConfig = @{
            defaults = @{
                unit = $Unit
                color = @{
                    mode = "palette-classic"
                }
                custom = @{
                    axisCenteredZero = $false
                    drawStyle = "line"
                    fillOpacity = 10
                    lineInterpolation = "linear"
                    lineWidth = 2
                    pointSize = 4
                    showPoints = "never"
                    spanNulls = $true
                    stacking = @{
                        mode = "none"
                        group = "A"
                    }
                }
            }
            overrides = @()
        }
        options = @{
            legend = @{
                calcs = @()
                displayMode = "list"
                placement = "bottom"
            }
            tooltip = @{
                mode = "multi"
                sort = "none"
            }
        }
    }
}

function New-LogsPanel {
    param(
        [int]$Id,
        [string]$Title,
        [hashtable]$Datasource,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [string]$Expr
    )

    @{
        id = $Id
        title = $Title
        type = "logs"
        datasource = $Datasource
        gridPos = @{
            h = $Height
            w = $Width
            x = $X
            y = $Y
        }
        targets = @(
            (New-Target -RefId "A" -Expr $Expr -QueryType "range")
        )
        options = @{
            dedupStrategy = "none"
            enableLogDetails = $true
            prettifyLogMessage = $false
            showCommonLabels = $false
            showLabels = $true
            showTime = $true
            sortOrder = "Descending"
            wrapLogMessage = $true
        }
    }
}

function New-Dashboard {
    param(
        [string]$Uid,
        [string]$Title,
        [array]$Tags,
        [array]$Panels
    )

    @{
        id = $null
        uid = $Uid
        title = $Title
        tags = $Tags
        style = "dark"
        timezone = "browser"
        editable = $true
        graphTooltip = 0
        schemaVersion = 39
        version = 0
        refresh = "30s"
        time = @{
            from = "now-6h"
            to = "now"
        }
        annotations = @{
            list = New-AnnotationList
        }
        templating = @{
            list = @()
        }
        panels = $Panels
    }
}

function Get-DatasourceUid {
    param(
        [string]$PreferredName,
        [string]$Type
    )

    try {
        $byName = Invoke-GrafanaApi -Method "GET" -Path ("/api/datasources/name/" + [uri]::EscapeDataString($PreferredName))
        if ($byName.uid) {
            return $byName.uid
        }
    } catch {
    }

    $datasources = Invoke-GrafanaApi -Method "GET" -Path "/api/datasources"
    $match = $datasources | Where-Object { $_.type -eq $Type } | Select-Object -First 1
    if ($null -eq $match) {
        throw "Could not find a Grafana datasource of type '$Type'."
    }

    $match.uid
}

function Ensure-FolderUid {
    param([string]$Title)

    $search = Invoke-GrafanaApi -Method "GET" -Path ("/api/search?type=dash-folder&query=" + [uri]::EscapeDataString($Title))
    $existing = $search | Where-Object { $_.title -eq $Title } | Select-Object -First 1
    if ($null -ne $existing) {
        return $existing.uid
    }

    (Invoke-GrafanaApi -Method "POST" -Path "/api/folders" -Body @{ title = $Title }).uid
}

function Publish-Dashboard {
    param(
        [string]$FolderUid,
        [hashtable]$Dashboard
    )

    $payload = @{
        dashboard = $Dashboard
        folderUid = $FolderUid
        overwrite = $true
        message = "Updated by Publish-GrafanaDashboards.ps1"
    }

    $response = Invoke-GrafanaApi -Method "POST" -Path "/api/dashboards/db" -Body $payload
    [pscustomobject]@{
        Title = $Dashboard.title
        Url = "$baseUrl$($response.url)"
        Status = $response.status
    }
}

$prometheusUid = Get-DatasourceUid -PreferredName "Prometheus" -Type "prometheus"
$lokiUid = Get-DatasourceUid -PreferredName "Loki" -Type "loki"
$prometheus = New-DatasourceRef -Uid $prometheusUid -Type "prometheus"
$loki = New-DatasourceRef -Uid $lokiUid -Type "loki"
$folderUid = Ensure-FolderUid -Title "Fitz-Net Services"

$websitePanels = @(
    (New-StatPanel -Id 1 -Title "Container Up" -Datasource $prometheus -X 0 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "max(container_last_seen{container_label_com_docker_compose_service=`"fitz-net-website`",image!=`"`"}) > bool 0")
    ) -Unit "none" -ThresholdSteps @(
        @{ color = "red"; value = $null },
        @{ color = "green"; value = 1 }
    ) -Mappings @(
        @{
            type = "value"
            options = @{
                "0" = @{ text = "Down" }
                "1" = @{ text = "Up" }
            }
        }
    )),
    (New-StatPanel -Id 2 -Title "Requests/s" -Datasource $loki -X 6 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate({service=`"fitz-net-website`"} | json | __error__=`"`" [5m]))")
    ) -Unit "reqps" -ThresholdSteps @(
        @{ color = "green"; value = $null }
    )),
    (New-StatPanel -Id 3 -Title "5xx Rate" -Datasource $loki -X 12 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate({service=`"fitz-net-website`"} | json | __error__=`"`" | status =~ `"5..`" [5m])) / sum(rate({service=`"fitz-net-website`"} | json | __error__=`"`" [5m]))")
    ) -Unit "percentunit" -ThresholdSteps @(
        @{ color = "green"; value = $null },
        @{ color = "orange"; value = 0.01 },
        @{ color = "red"; value = 0.05 }
    )),
    (New-StatPanel -Id 4 -Title "Request Latency p95" -Datasource $loki -X 18 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "quantile_over_time(0.95, {service=`"fitz-net-website`"} | json | __error__=`"`" | unwrap request_time [5m]) * 1000")
    ) -Unit "ms" -ThresholdSteps @(
        @{ color = "green"; value = $null },
        @{ color = "orange"; value = 250 },
        @{ color = "red"; value = 1000 }
    )),
    (New-TimeSeriesPanel -Id 5 -Title "Request Rate by Status Class" -Datasource $loki -X 0 -Y 4 -Width 12 -Height 8 -Unit "reqps" -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate({service=`"fitz-net-website`"} | json | __error__=`"`" | status =~ `"2..`" [5m]))" -LegendFormat "2xx"),
        (New-Target -RefId "B" -Expr "sum(rate({service=`"fitz-net-website`"} | json | __error__=`"`" | status =~ `"4..`" [5m]))" -LegendFormat "4xx"),
        (New-Target -RefId "C" -Expr "sum(rate({service=`"fitz-net-website`"} | json | __error__=`"`" | status =~ `"5..`" [5m]))" -LegendFormat "5xx")
    )),
    (New-TimeSeriesPanel -Id 6 -Title "Request Latency" -Datasource $loki -X 12 -Y 4 -Width 12 -Height 8 -Unit "ms" -Targets @(
        (New-Target -RefId "A" -Expr "avg_over_time({service=`"fitz-net-website`"} | json | __error__=`"`" | unwrap request_time [5m]) * 1000" -LegendFormat "avg"),
        (New-Target -RefId "B" -Expr "quantile_over_time(0.95, {service=`"fitz-net-website`"} | json | __error__=`"`" | unwrap request_time [5m]) * 1000" -LegendFormat "p95")
    )),
    (New-TimeSeriesPanel -Id 7 -Title "Container CPU Usage" -Datasource $prometheus -X 0 -Y 12 -Width 12 -Height 8 -Unit "percentunit" -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate(container_cpu_usage_seconds_total{container_label_com_docker_compose_service=`"fitz-net-website`",image!=`"`"}[5m]))" -LegendFormat "CPU cores")
    )),
    (New-TimeSeriesPanel -Id 8 -Title "Container Memory Usage" -Datasource $prometheus -X 12 -Y 12 -Width 12 -Height 8 -Unit "bytes" -Targets @(
        (New-Target -RefId "A" -Expr "max(container_memory_working_set_bytes{container_label_com_docker_compose_service=`"fitz-net-website`",image!=`"`"})" -LegendFormat "memory")
    )),
    (New-LogsPanel -Id 9 -Title "Website Logs" -Datasource $loki -X 0 -Y 20 -Width 24 -Height 10 -Expr "{service=`"fitz-net-website`"}")
)

$apiPanels = @(
    (New-StatPanel -Id 1 -Title "Service Up" -Datasource $prometheus -X 0 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "max(up{service=`"fitz-net-api`"})")
    ) -Unit "none" -ThresholdSteps @(
        @{ color = "red"; value = $null },
        @{ color = "green"; value = 1 }
    ) -Mappings @(
        @{
            type = "value"
            options = @{
                "0" = @{ text = "Down" }
                "1" = @{ text = "Up" }
            }
        }
    )),
    (New-StatPanel -Id 2 -Title "Requests/s" -Datasource $prometheus -X 6 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate(http_server_requests_seconds_count{service=`"fitz-net-api`",uri!=`"/actuator/prometheus`"}[5m]))")
    ) -Unit "reqps" -ThresholdSteps @(
        @{ color = "green"; value = $null }
    )),
    (New-StatPanel -Id 3 -Title "5xx Rate" -Datasource $prometheus -X 12 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate(http_server_requests_seconds_count{service=`"fitz-net-api`",uri!=`"/actuator/prometheus`",status=~`"5..`"}[5m])) / sum(rate(http_server_requests_seconds_count{service=`"fitz-net-api`",uri!=`"/actuator/prometheus`"}[5m]))")
    ) -Unit "percentunit" -ThresholdSteps @(
        @{ color = "green"; value = $null },
        @{ color = "orange"; value = 0.01 },
        @{ color = "red"; value = 0.05 }
    )),
    (New-StatPanel -Id 4 -Title "Request Latency Avg" -Datasource $prometheus -X 18 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "(sum(rate(http_server_requests_seconds_sum{service=`"fitz-net-api`",uri!=`"/actuator/prometheus`"}[5m])) / sum(rate(http_server_requests_seconds_count{service=`"fitz-net-api`",uri!=`"/actuator/prometheus`"}[5m]))) * 1000")
    ) -Unit "ms" -ThresholdSteps @(
        @{ color = "green"; value = $null },
        @{ color = "orange"; value = 250 },
        @{ color = "red"; value = 1000 }
    )),
    (New-TimeSeriesPanel -Id 5 -Title "HTTP Status Rate" -Datasource $prometheus -X 0 -Y 4 -Width 12 -Height 8 -Unit "reqps" -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate(http_server_requests_seconds_count{service=`"fitz-net-api`",uri!=`"/actuator/prometheus`",status=~`"2..`"}[5m]))" -LegendFormat "2xx"),
        (New-Target -RefId "B" -Expr "sum(rate(http_server_requests_seconds_count{service=`"fitz-net-api`",uri!=`"/actuator/prometheus`",status=~`"4..`"}[5m]))" -LegendFormat "4xx"),
        (New-Target -RefId "C" -Expr "sum(rate(http_server_requests_seconds_count{service=`"fitz-net-api`",uri!=`"/actuator/prometheus`",status=~`"5..`"}[5m]))" -LegendFormat "5xx")
    )),
    (New-TimeSeriesPanel -Id 6 -Title "Business Operations" -Datasource $prometheus -X 12 -Y 4 -Width 12 -Height 8 -Unit "ops" -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate(fitznet_user_operations_total{service=`"fitz-net-api`"}[5m]))" -LegendFormat "user ops"),
        (New-Target -RefId "B" -Expr "sum(rate(fitznet_encryption_operations_total{service=`"fitz-net-api`"}[5m]))" -LegendFormat "encryption ops"),
        (New-Target -RefId "C" -Expr "sum(rate(fitznet_api_failures_total{service=`"fitz-net-api`"}[5m]))" -LegendFormat "api failures")
    )),
    (New-TimeSeriesPanel -Id 7 -Title "JVM Heap" -Datasource $prometheus -X 0 -Y 12 -Width 12 -Height 8 -Unit "bytes" -Targets @(
        (New-Target -RefId "A" -Expr "sum(jvm_memory_used_bytes{service=`"fitz-net-api`",area=`"heap`"})" -LegendFormat "used"),
        (New-Target -RefId "B" -Expr "sum(jvm_memory_max_bytes{service=`"fitz-net-api`",area=`"heap`"})" -LegendFormat "max")
    )),
    (New-TimeSeriesPanel -Id 8 -Title "Container Runtime Health" -Datasource $prometheus -X 12 -Y 12 -Width 12 -Height 8 -Unit "short" -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate(container_cpu_usage_seconds_total{container_label_com_docker_compose_service=`"fitz-net-api`",image!=`"`"}[5m]))" -LegendFormat "CPU cores"),
        (New-Target -RefId "B" -Expr "max(container_memory_working_set_bytes{container_label_com_docker_compose_service=`"fitz-net-api`",image!=`"`"})" -LegendFormat "memory")
    )),
    (New-LogsPanel -Id 9 -Title "API Error Logs" -Datasource $loki -X 0 -Y 20 -Width 24 -Height 10 -Expr "{service=`"fitz-net-api`"} |= `"ERROR`"")
)

$gamerbellPanels = @(
    (New-StatPanel -Id 1 -Title "Service Up" -Datasource $prometheus -X 0 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "max(up{service=`"gamerbell`"})")
    ) -Unit "none" -ThresholdSteps @(
        @{ color = "red"; value = $null },
        @{ color = "green"; value = 1 }
    ) -Mappings @(
        @{
            type = "value"
            options = @{
                "0" = @{ text = "Down" }
                "1" = @{ text = "Up" }
            }
        }
    )),
    (New-StatPanel -Id 2 -Title "Active Sessions" -Datasource $prometheus -X 6 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "max(gamerbell_websocket_sessions_active{service=`"gamerbell`"})")
    ) -Unit "short" -ThresholdSteps @(
        @{ color = "green"; value = $null }
    )),
    (New-StatPanel -Id 3 -Title "Button Events/s" -Datasource $prometheus -X 12 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate(gamerbell_button_events_total{service=`"gamerbell`"}[5m]))")
    ) -Unit "reqps" -ThresholdSteps @(
        @{ color = "green"; value = $null }
    )),
    (New-StatPanel -Id 4 -Title "WebSocket Errors/s" -Datasource $prometheus -X 18 -Y 0 -Width 6 -Height 4 -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate(gamerbell_websocket_errors_total{service=`"gamerbell`"}[5m]))")
    ) -Unit "reqps" -ThresholdSteps @(
        @{ color = "green"; value = $null },
        @{ color = "orange"; value = 0.01 },
        @{ color = "red"; value = 0.05 }
    )),
    (New-TimeSeriesPanel -Id 5 -Title "Button Events by Type" -Datasource $prometheus -X 0 -Y 4 -Width 12 -Height 8 -Unit "reqps" -Targets @(
        (New-Target -RefId "A" -Expr "sum by (event) (rate(gamerbell_button_events_total{service=`"gamerbell`"}[5m]))" -LegendFormat "{{event}}")
    )),
    (New-TimeSeriesPanel -Id 6 -Title "Broadcast Delivery Outcomes" -Datasource $prometheus -X 12 -Y 4 -Width 12 -Height 8 -Unit "reqps" -Targets @(
        (New-Target -RefId "A" -Expr "sum by (result) (rate(gamerbell_broadcast_deliveries_total{service=`"gamerbell`"}[5m]))" -LegendFormat "{{result}}"),
        (New-Target -RefId "B" -Expr "sum(rate(gamerbell_broadcast_duration_seconds_sum{service=`"gamerbell`"}[5m])) / sum(rate(gamerbell_broadcast_duration_seconds_count{service=`"gamerbell`"}[5m]))" -LegendFormat "avg duration (s)")
    )),
    (New-TimeSeriesPanel -Id 7 -Title "Firmware Activity" -Datasource $prometheus -X 0 -Y 12 -Width 12 -Height 8 -Unit "reqps" -Targets @(
        (New-Target -RefId "A" -Expr "sum by (outcome) (rate(gamerbell_firmware_checks_total{service=`"gamerbell`"}[5m]))" -LegendFormat "checks {{outcome}}"),
        (New-Target -RefId "B" -Expr "sum by (outcome) (rate(gamerbell_firmware_downloads_total{service=`"gamerbell`"}[5m]))" -LegendFormat "downloads {{outcome}}")
    )),
    (New-TimeSeriesPanel -Id 8 -Title "Container Runtime Health" -Datasource $prometheus -X 12 -Y 12 -Width 12 -Height 8 -Unit "short" -Targets @(
        (New-Target -RefId "A" -Expr "sum(rate(container_cpu_usage_seconds_total{container_label_com_docker_compose_service=`"gamerbell`",image!=`"`"}[5m]))" -LegendFormat "CPU cores"),
        (New-Target -RefId "B" -Expr "max(container_memory_working_set_bytes{container_label_com_docker_compose_service=`"gamerbell`",image!=`"`"})" -LegendFormat "memory")
    )),
    (New-LogsPanel -Id 9 -Title "GamerBell Error Logs" -Datasource $loki -X 0 -Y 20 -Width 24 -Height 10 -Expr "{service=`"gamerbell`"} |= `"ERROR`"")
)

$dashboards = @(
    (New-Dashboard -Uid "fitz-net-website-overview" -Title "fitz-net-website / Overview" -Tags @("fitz-net", "website", "operations") -Panels $websitePanels),
    (New-Dashboard -Uid "fitz-net-api-overview" -Title "fitz-net-api / Overview" -Tags @("fitz-net", "api", "operations") -Panels $apiPanels),
    (New-Dashboard -Uid "gamerbell-overview" -Title "gamerbell / Overview" -Tags @("fitz-net", "gamerbell", "operations") -Panels $gamerbellPanels)
)

$results = foreach ($dashboard in $dashboards) {
    Publish-Dashboard -FolderUid $folderUid -Dashboard $dashboard
}

$results | ForEach-Object {
    Write-Output ("{0} [{1}] -> {2}" -f $_.Title, $_.Status, $_.Url)
}
