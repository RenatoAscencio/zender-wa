#!/bin/bash
# Advanced Health Check Script for WhatsApp Service
# Provides comprehensive health monitoring with metrics

set -euo pipefail

readonly BASE_DIR="/data/whatsapp-server"
readonly PID_FILE="${BASE_DIR}/service.pid"
readonly SERVICE_LOG_FILE="${BASE_DIR}/service.log"
readonly HEALTH_LOG_FILE="${BASE_DIR}/health.log"
readonly METRICS_FILE="${BASE_DIR}/metrics.json"

# Health check configuration
readonly MAX_MEMORY_MB=1024
readonly MAX_CPU_PERCENT=80
readonly MAX_LOG_SIZE_MB=100
readonly CONNECTION_TIMEOUT=10

log_health() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [HEALTH] $*" >> "${HEALTH_LOG_FILE}"
}

# Check if service process is running
check_process() {
    if [[ ! -f "$PID_FILE" ]]; then
        echo "CRITICAL: PID file not found"
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "CRITICAL: Process with PID $pid not running"
        return 1
    fi

    echo "OK: Process running with PID $pid"
    return 0
}

# Check memory usage
check_memory() {
    if [[ ! -f "$PID_FILE" ]]; then
        return 1
    fi

    local pid memory_mb
    pid=$(cat "$PID_FILE")

    # Get memory usage in MB
    memory_mb=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}' || echo "0")

    if [[ $memory_mb -gt $MAX_MEMORY_MB ]]; then
        echo "WARNING: High memory usage: ${memory_mb}MB (max: ${MAX_MEMORY_MB}MB)"
        return 1
    fi

    echo "OK: Memory usage: ${memory_mb}MB"
    return 0
}

# Check CPU usage
check_cpu() {
    if [[ ! -f "$PID_FILE" ]]; then
        return 1
    fi

    local pid cpu_percent
    pid=$(cat "$PID_FILE")

    # Get CPU percentage
    cpu_percent=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print int($1)}' || echo "0")

    if [[ $cpu_percent -gt $MAX_CPU_PERCENT ]]; then
        echo "WARNING: High CPU usage: ${cpu_percent}% (max: ${MAX_CPU_PERCENT}%)"
        return 1
    fi

    echo "OK: CPU usage: ${cpu_percent}%"
    return 0
}

# Check log file size
check_logs() {
    if [[ ! -f "$SERVICE_LOG_FILE" ]]; then
        echo "WARNING: Service log file not found"
        return 1
    fi

    local log_size_mb
    log_size_mb=$(stat -f%z "$SERVICE_LOG_FILE" 2>/dev/null || stat -c%s "$SERVICE_LOG_FILE" 2>/dev/null || echo 0)
    log_size_mb=$((log_size_mb / 1024 / 1024))

    if [[ $log_size_mb -gt $MAX_LOG_SIZE_MB ]]; then
        echo "WARNING: Large log file: ${log_size_mb}MB (max: ${MAX_LOG_SIZE_MB}MB)"
        return 1
    fi

    echo "OK: Log file size: ${log_size_mb}MB"
    return 0
}

# Check service endpoint
check_endpoint() {
    local port
    port=$(grep "^PORT=" "${BASE_DIR}/.env" 2>/dev/null | cut -d'=' -f2 || echo "443")

    if timeout "$CONNECTION_TIMEOUT" bash -c "</dev/tcp/localhost/$port" 2>/dev/null; then
        echo "OK: Service responding on port $port"
        return 0
    else
        echo "CRITICAL: Service not responding on port $port"
        return 1
    fi
}

# Generate metrics JSON
generate_metrics() {
    local timestamp pid memory_mb cpu_percent uptime_seconds
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -f "$PID_FILE" ]]; then
        pid=$(cat "$PID_FILE")
        memory_mb=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}' || echo "0")
        cpu_percent=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print $1}' || echo "0")
        uptime_seconds=$(ps -p "$pid" -o etime= 2>/dev/null | awk -F: '{if(NF==2) print $1*60+$2; else if(NF==3) print $1*3600+$2*60+$3}' || echo "0")
    else
        pid="null"
        memory_mb="0"
        cpu_percent="0"
        uptime_seconds="0"
    fi

    cat > "$METRICS_FILE" << EOF
{
    "timestamp": "$timestamp",
    "service": {
        "status": "$(check_process >/dev/null 2>&1 && echo "running" || echo "stopped")",
        "pid": $pid,
        "uptime_seconds": $uptime_seconds
    },
    "resources": {
        "memory_mb": $memory_mb,
        "cpu_percent": $cpu_percent
    },
    "health_checks": {
        "process": $(check_process >/dev/null 2>&1 && echo "true" || echo "false"),
        "memory": $(check_memory >/dev/null 2>&1 && echo "true" || echo "false"),
        "cpu": $(check_cpu >/dev/null 2>&1 && echo "true" || echo "false"),
        "logs": $(check_logs >/dev/null 2>&1 && echo "true" || echo "false"),
        "endpoint": $(check_endpoint >/dev/null 2>&1 && echo "true" || echo "false")
    }
}
EOF
}

# Main health check function
main() {
    local exit_code=0
    local checks=("check_process" "check_memory" "check_cpu" "check_logs" "check_endpoint")

    echo "=== WhatsApp Service Health Check ==="
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo

    for check in "${checks[@]}"; do
        if ! $check; then
            exit_code=1
        fi
    done

    echo
    generate_metrics
    log_health "Health check completed with exit code $exit_code"

    if [[ $exit_code -eq 0 ]]; then
        echo "✅ Overall health: HEALTHY"
    else
        echo "❌ Overall health: UNHEALTHY"
    fi

    exit $exit_code
}

main "$@"