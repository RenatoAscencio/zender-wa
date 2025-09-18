#!/bin/bash
# Prometheus Metrics Exporter for Zender WhatsApp Server
# Exports metrics in Prometheus format

set -euo pipefail

readonly BASE_DIR="/data/whatsapp-server"
readonly METRICS_FILE="${BASE_DIR}/metrics.json"
readonly PROMETHEUS_FILE="${BASE_DIR}/prometheus-metrics.txt"
readonly PID_FILE="${BASE_DIR}/service.pid"
readonly SERVICE_LOG_FILE="${BASE_DIR}/service.log"

# Default port for metrics endpoint
readonly METRICS_PORT="${METRICS_PORT:-9090}"

# Logging function
log_metrics() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [METRICS] $*" >&2
}

# Get service status
get_service_status() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "1"
    else
        echo "0"
    fi
}

# Get process metrics
get_process_metrics() {
    if [[ ! -f "$PID_FILE" ]]; then
        echo "0 0 0"
        return
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "0 0 0"
        return
    fi

    # Get memory usage in bytes
    local memory_kb
    memory_kb=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print $1}' || echo "0")
    local memory_bytes=$((memory_kb * 1024))

    # Get CPU percentage
    local cpu_percent
    cpu_percent=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print $1}' || echo "0")

    # Get uptime in seconds
    local uptime_seconds
    uptime_seconds=$(ps -p "$pid" -o etime= 2>/dev/null | awk -F: '
        {
            if(NF==1) print $1
            else if(NF==2) print $1*60+$2
            else if(NF==3) print $1*3600+$2*60+$3
            else print 0
        }' || echo "0")

    echo "$memory_bytes $cpu_percent $uptime_seconds"
}

# Get system metrics
get_system_metrics() {
    # Total memory in bytes
    local total_memory
    total_memory=$(free -b 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "0")

    # Available memory in bytes
    local available_memory
    available_memory=$(free -b 2>/dev/null | awk '/^Mem:/ {print $7}' || echo "0")

    # Disk usage for data directory
    local disk_total disk_used disk_available
    if command -v df >/dev/null 2>&1; then
        local disk_info
        disk_info=$(df -B1 "$BASE_DIR" 2>/dev/null | tail -1)
        disk_total=$(echo "$disk_info" | awk '{print $2}')
        disk_used=$(echo "$disk_info" | awk '{print $3}')
        disk_available=$(echo "$disk_info" | awk '{print $4}')
    else
        disk_total="0"
        disk_used="0"
        disk_available="0"
    fi

    echo "$total_memory $available_memory $disk_total $disk_used $disk_available"
}

# Get log metrics
get_log_metrics() {
    if [[ ! -f "$SERVICE_LOG_FILE" ]]; then
        echo "0 0 0 0"
        return
    fi

    # Count log entries in last hour
    local cutoff_time
    cutoff_time=$(date -d '1 hour ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -j -v-1H '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "1970-01-01 00:00:00")

    local total_logs error_logs warning_logs info_logs
    total_logs=$(wc -l < "$SERVICE_LOG_FILE" 2>/dev/null || echo "0")
    error_logs=$(grep -c "\[ERROR\]" "$SERVICE_LOG_FILE" 2>/dev/null || echo "0")
    warning_logs=$(grep -c "\[WARN\]" "$SERVICE_LOG_FILE" 2>/dev/null || echo "0")
    info_logs=$(grep -c "\[INFO\]" "$SERVICE_LOG_FILE" 2>/dev/null || echo "0")

    echo "$total_logs $error_logs $warning_logs $info_logs"
}

# Get network metrics
get_network_metrics() {
    local connections_total connections_established

    if command -v netstat >/dev/null 2>&1; then
        connections_total=$(netstat -an 2>/dev/null | grep -c "^tcp" || echo "0")
        connections_established=$(netstat -an 2>/dev/null | grep -c "ESTABLISHED" || echo "0")
    elif command -v ss >/dev/null 2>&1; then
        connections_total=$(ss -t -a 2>/dev/null | grep -c "^LISTEN\|^ESTAB" || echo "0")
        connections_established=$(ss -t -a 2>/dev/null | grep -c "^ESTAB" || echo "0")
    else
        connections_total="0"
        connections_established="0"
    fi

    echo "$connections_total $connections_established"
}

# Generate Prometheus metrics
generate_prometheus_metrics() {
    local timestamp
    timestamp=$(date +%s)

    {
        echo "# HELP whatsapp_service_up Whether the WhatsApp service is running"
        echo "# TYPE whatsapp_service_up gauge"
        echo "whatsapp_service_up $(get_service_status) $timestamp"
        echo

        # Process metrics
        local process_metrics
        process_metrics=$(get_process_metrics)
        local memory_bytes cpu_percent uptime_seconds
        read -r memory_bytes cpu_percent uptime_seconds <<< "$process_metrics"

        echo "# HELP whatsapp_process_memory_bytes Memory usage in bytes"
        echo "# TYPE whatsapp_process_memory_bytes gauge"
        echo "whatsapp_process_memory_bytes $memory_bytes $timestamp"
        echo

        echo "# HELP whatsapp_process_cpu_percent CPU usage percentage"
        echo "# TYPE whatsapp_process_cpu_percent gauge"
        echo "whatsapp_process_cpu_percent $cpu_percent $timestamp"
        echo

        echo "# HELP whatsapp_process_uptime_seconds Process uptime in seconds"
        echo "# TYPE whatsapp_process_uptime_seconds counter"
        echo "whatsapp_process_uptime_seconds $uptime_seconds $timestamp"
        echo

        # System metrics
        local system_metrics
        system_metrics=$(get_system_metrics)
        local total_memory available_memory disk_total disk_used disk_available
        read -r total_memory available_memory disk_total disk_used disk_available <<< "$system_metrics"

        echo "# HELP whatsapp_system_memory_total_bytes Total system memory in bytes"
        echo "# TYPE whatsapp_system_memory_total_bytes gauge"
        echo "whatsapp_system_memory_total_bytes $total_memory $timestamp"
        echo

        echo "# HELP whatsapp_system_memory_available_bytes Available system memory in bytes"
        echo "# TYPE whatsapp_system_memory_available_bytes gauge"
        echo "whatsapp_system_memory_available_bytes $available_memory $timestamp"
        echo

        echo "# HELP whatsapp_disk_total_bytes Total disk space in bytes"
        echo "# TYPE whatsapp_disk_total_bytes gauge"
        echo "whatsapp_disk_total_bytes $disk_total $timestamp"
        echo

        echo "# HELP whatsapp_disk_used_bytes Used disk space in bytes"
        echo "# TYPE whatsapp_disk_used_bytes gauge"
        echo "whatsapp_disk_used_bytes $disk_used $timestamp"
        echo

        echo "# HELP whatsapp_disk_available_bytes Available disk space in bytes"
        echo "# TYPE whatsapp_disk_available_bytes gauge"
        echo "whatsapp_disk_available_bytes $disk_available $timestamp"
        echo

        # Log metrics
        local log_metrics
        log_metrics=$(get_log_metrics)
        local total_logs error_logs warning_logs info_logs
        read -r total_logs error_logs warning_logs info_logs <<< "$log_metrics"

        echo "# HELP whatsapp_logs_total Total number of log entries"
        echo "# TYPE whatsapp_logs_total counter"
        echo "whatsapp_logs_total $total_logs $timestamp"
        echo

        echo "# HELP whatsapp_logs_errors_total Total number of error log entries"
        echo "# TYPE whatsapp_logs_errors_total counter"
        echo "whatsapp_logs_errors_total $error_logs $timestamp"
        echo

        echo "# HELP whatsapp_logs_warnings_total Total number of warning log entries"
        echo "# TYPE whatsapp_logs_warnings_total counter"
        echo "whatsapp_logs_warnings_total $warning_logs $timestamp"
        echo

        echo "# HELP whatsapp_logs_info_total Total number of info log entries"
        echo "# TYPE whatsapp_logs_info_total counter"
        echo "whatsapp_logs_info_total $info_logs $timestamp"
        echo

        # Network metrics
        local network_metrics
        network_metrics=$(get_network_metrics)
        local connections_total connections_established
        read -r connections_total connections_established <<< "$network_metrics"

        echo "# HELP whatsapp_network_connections_total Total network connections"
        echo "# TYPE whatsapp_network_connections_total gauge"
        echo "whatsapp_network_connections_total $connections_total $timestamp"
        echo

        echo "# HELP whatsapp_network_connections_established Established network connections"
        echo "# TYPE whatsapp_network_connections_established gauge"
        echo "whatsapp_network_connections_established $connections_established $timestamp"
        echo

        # Health check metrics
        local health_status
        if [[ -f "${BASE_DIR}/health.log" ]]; then
            health_status=$(tail -1 "${BASE_DIR}/health.log" | grep -c "Overall health: HEALTHY" || echo "0")
        else
            health_status="0"
        fi

        echo "# HELP whatsapp_health_status Health check status (1=healthy, 0=unhealthy)"
        echo "# TYPE whatsapp_health_status gauge"
        echo "whatsapp_health_status $health_status $timestamp"
        echo

        # Build information
        echo "# HELP whatsapp_build_info Build information"
        echo "# TYPE whatsapp_build_info gauge"
        echo "whatsapp_build_info{version=\"${VERSION:-unknown}\",platform=\"${PLATFORM:-unknown}\",architecture=\"${ARCHITECTURE:-unknown}\"} 1 $timestamp"
        echo

    } > "$PROMETHEUS_FILE"
}

# Start HTTP server for metrics endpoint
start_metrics_server() {
    log_metrics "Starting metrics server on port $METRICS_PORT"

    while true; do
        # Generate fresh metrics
        generate_prometheus_metrics

        # Serve metrics using netcat or built-in tools
        if command -v nc >/dev/null 2>&1; then
            {
                echo "HTTP/1.1 200 OK"
                echo "Content-Type: text/plain; version=0.0.4; charset=utf-8"
                echo "Content-Length: $(wc -c < "$PROMETHEUS_FILE")"
                echo
                cat "$PROMETHEUS_FILE"
            } | nc -l -p "$METRICS_PORT" -q 1 2>/dev/null || true
        elif command -v socat >/dev/null 2>&1; then
            {
                echo "HTTP/1.1 200 OK"
                echo "Content-Type: text/plain; version=0.0.4; charset=utf-8"
                echo "Content-Length: $(wc -c < "$PROMETHEUS_FILE")"
                echo
                cat "$PROMETHEUS_FILE"
            } | socat -T1 TCP-LISTEN:"$METRICS_PORT",reuseaddr,fork STDIO 2>/dev/null || true
        else
            # Fallback: update metrics file only
            log_metrics "No network tools available. Metrics written to $PROMETHEUS_FILE"
            sleep 30
        fi

        sleep 15  # Update interval
    done
}

# Export metrics to JSON (backward compatibility)
export_json_metrics() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local process_metrics system_metrics log_metrics network_metrics
    process_metrics=$(get_process_metrics)
    system_metrics=$(get_system_metrics)
    log_metrics=$(get_log_metrics)
    network_metrics=$(get_network_metrics)

    local memory_bytes cpu_percent uptime_seconds
    read -r memory_bytes cpu_percent uptime_seconds <<< "$process_metrics"

    local total_memory available_memory disk_total disk_used disk_available
    read -r total_memory available_memory disk_total disk_used disk_available <<< "$system_metrics"

    local total_logs error_logs warning_logs info_logs
    read -r total_logs error_logs warning_logs info_logs <<< "$log_metrics"

    local connections_total connections_established
    read -r connections_total connections_established <<< "$network_metrics"

    cat > "$METRICS_FILE" << EOF
{
    "timestamp": "$timestamp",
    "service": {
        "status": "$(get_service_status | sed 's/1/running/; s/0/stopped/')",
        "pid": $(cat "$PID_FILE" 2>/dev/null || echo "null"),
        "uptime_seconds": $uptime_seconds
    },
    "resources": {
        "memory_bytes": $memory_bytes,
        "memory_mb": $((memory_bytes / 1024 / 1024)),
        "cpu_percent": $cpu_percent
    },
    "system": {
        "memory_total_bytes": $total_memory,
        "memory_available_bytes": $available_memory,
        "disk_total_bytes": $disk_total,
        "disk_used_bytes": $disk_used,
        "disk_available_bytes": $disk_available
    },
    "logs": {
        "total": $total_logs,
        "errors": $error_logs,
        "warnings": $warning_logs,
        "info": $info_logs
    },
    "network": {
        "connections_total": $connections_total,
        "connections_established": $connections_established
    },
    "build": {
        "version": "${VERSION:-unknown}",
        "platform": "${PLATFORM:-unknown}",
        "architecture": "${ARCHITECTURE:-unknown}"
    }
}
EOF
}

# Main function
main() {
    local mode="${1:-server}"

    case "$mode" in
        "server")
            start_metrics_server
            ;;
        "once")
            generate_prometheus_metrics
            export_json_metrics
            log_metrics "Metrics generated: $PROMETHEUS_FILE and $METRICS_FILE"
            ;;
        "json")
            export_json_metrics
            cat "$METRICS_FILE"
            ;;
        "prometheus")
            generate_prometheus_metrics
            cat "$PROMETHEUS_FILE"
            ;;
        "--help"|"-h")
            cat << EOF
Prometheus Metrics Exporter for Zender WhatsApp Server

Usage: $0 [MODE]

Modes:
    server      Start HTTP metrics server (default)
    once        Generate metrics once and exit
    json        Output JSON metrics to stdout
    prometheus  Output Prometheus metrics to stdout

Environment Variables:
    METRICS_PORT    Port for HTTP metrics server (default: 9090)

Examples:
    $0                 # Start metrics server
    $0 once            # Generate metrics once
    $0 json            # Output JSON metrics
    $0 prometheus      # Output Prometheus metrics

EOF
            ;;
        *)
            log_metrics "Unknown mode: $mode"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"