#!/bin/bash
# Advanced Process and Memory Management
# Provides intelligent process monitoring and resource optimization

set -euo pipefail

readonly BASE_DIR="/data/whatsapp-server"
readonly PID_FILE="${BASE_DIR}/service.pid"
readonly LOCK_FILE="${BASE_DIR}/process.lock"
readonly METRICS_FILE="${BASE_DIR}/process-metrics.json"
readonly EXECUTABLE_NAME="titansys-whatsapp-linux"

# Resource limits
readonly MAX_MEMORY_MB=1024
readonly MAX_CPU_PERCENT=80
readonly RESTART_THRESHOLD=5
readonly MONITORING_INTERVAL=30

# Process management functions
log_process() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [PROCESS] $*" >&2
}

# Create lock file to prevent multiple instances
acquire_lock() {
    local lock_timeout="${1:-30}"

    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")

        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log_process "Another process manager is already running (PID: $lock_pid)"
            return 1
        else
            log_process "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi

    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
    return 0
}

# Start service with resource monitoring
start_service() {
    local pcode="$1"
    local key="$2"
    local port="${3:-443}"

    log_process "Starting WhatsApp service..."

    # Pre-start validation
    if ! validate_resources; then
        log_process "Resource validation failed. Cannot start service."
        return 1
    fi

    # Check if already running
    if is_service_running; then
        log_process "Service is already running"
        return 0
    fi

    # Clean up any stale PID files
    rm -f "$PID_FILE"

    # Start the service with resource limits
    cd "$BASE_DIR"

    # Use systemd-run if available for better resource control
    if command -v systemd-run >/dev/null 2>&1; then
        systemd-run --user --scope \
            --property=MemoryLimit="${MAX_MEMORY_MB}M" \
            --property=CPUQuota="$((MAX_CPU_PERCENT))%" \
            "./${EXECUTABLE_NAME}" \
            --pcode="$pcode" \
            --key="$key" \
            --host="0.0.0.0" \
            --port="$port" &
    else
        # Fallback to regular process with ulimit
        (
            ulimit -v $((MAX_MEMORY_MB * 1024))  # Virtual memory limit
            "./${EXECUTABLE_NAME}" \
                --pcode="$pcode" \
                --key="$key" \
                --host="0.0.0.0" \
                --port="$port"
        ) &
    fi

    local pid=$!
    echo "$pid" > "$PID_FILE"

    # Wait for service to initialize
    local attempts=0
    while [[ $attempts -lt 10 ]]; do
        if kill -0 "$pid" 2>/dev/null; then
            log_process "Service started successfully with PID $pid"
            start_monitoring
            return 0
        fi
        sleep 1
        ((attempts++))
    done

    log_process "Service failed to start properly"
    rm -f "$PID_FILE"
    return 1
}

# Check if service is running
is_service_running() {
    if [[ ! -f "$PID_FILE" ]]; then
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if kill -0 "$pid" 2>/dev/null; then
        return 0
    else
        rm -f "$PID_FILE"
        return 1
    fi
}

# Stop service gracefully
stop_service() {
    local force="${1:-false}"
    local timeout="${2:-30}"

    log_process "Stopping WhatsApp service..."

    if ! is_service_running; then
        log_process "Service is not running"
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if [[ "$force" == "true" ]]; then
        log_process "Force stopping process $pid"
        kill -9 "$pid" 2>/dev/null || true
    else
        log_process "Gracefully stopping process $pid"
        kill -TERM "$pid" 2>/dev/null || true

        # Wait for graceful shutdown
        local elapsed=0
        while [[ $elapsed -lt $timeout ]] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            ((elapsed++))
        done

        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            log_process "Process did not stop gracefully, force killing"
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi

    rm -f "$PID_FILE"
    log_process "Service stopped"
    return 0
}

# Validate system resources
validate_resources() {
    # Check available memory
    local available_memory
    available_memory=$(free -m 2>/dev/null | awk '/^Mem:/ {print $7}' || echo "0")

    if [[ $available_memory -lt 256 ]]; then
        log_process "Insufficient memory: ${available_memory}MB available"
        return 1
    fi

    # Check disk space
    local available_space
    available_space=$(df -m "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")

    if [[ $available_space -lt 100 ]]; then
        log_process "Insufficient disk space: ${available_space}MB available"
        return 1
    fi

    return 0
}

# Monitor process resources
monitor_process() {
    if ! is_service_running; then
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE")

    # Get process metrics
    local memory_mb cpu_percent uptime_seconds
    memory_mb=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}' || echo "0")
    cpu_percent=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print $1}' || echo "0")
    uptime_seconds=$(ps -p "$pid" -o etime= 2>/dev/null | awk -F: '{
        if(NF==2) print $1*60+$2
        else if(NF==3) print $1*3600+$2*60+$3
        else print 0
    }' || echo "0")

    # Update metrics file
    cat > "$METRICS_FILE" << EOF
{
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
    "pid": $pid,
    "memory_mb": $memory_mb,
    "cpu_percent": $cpu_percent,
    "uptime_seconds": $uptime_seconds,
    "limits": {
        "max_memory_mb": $MAX_MEMORY_MB,
        "max_cpu_percent": $MAX_CPU_PERCENT
    }
}
EOF

    # Check resource limits
    local restart_needed=false

    if [[ $(echo "$memory_mb > $MAX_MEMORY_MB" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
        log_process "Memory limit exceeded: ${memory_mb}MB > ${MAX_MEMORY_MB}MB"
        restart_needed=true
    fi

    if [[ $(echo "$cpu_percent > $MAX_CPU_PERCENT" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
        log_process "CPU limit exceeded: ${cpu_percent}% > ${MAX_CPU_PERCENT}%"
        restart_needed=true
    fi

    # Restart if limits exceeded
    if [[ "$restart_needed" == "true" ]]; then
        log_process "Resource limits exceeded. Restarting service..."
        restart_service
    fi

    return 0
}

# Start continuous monitoring
start_monitoring() {
    if [[ -f "${BASE_DIR}/monitor.pid" ]]; then
        local monitor_pid
        monitor_pid=$(cat "${BASE_DIR}/monitor.pid")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            log_process "Monitoring already running"
            return 0
        fi
    fi

    (
        echo $$ > "${BASE_DIR}/monitor.pid"
        while true; do
            monitor_process || break
            sleep "$MONITORING_INTERVAL"
        done
        rm -f "${BASE_DIR}/monitor.pid"
    ) &

    log_process "Started resource monitoring"
}

# Stop monitoring
stop_monitoring() {
    if [[ -f "${BASE_DIR}/monitor.pid" ]]; then
        local monitor_pid
        monitor_pid=$(cat "${BASE_DIR}/monitor.pid")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            kill "$monitor_pid" 2>/dev/null || true
            rm -f "${BASE_DIR}/monitor.pid"
            log_process "Stopped resource monitoring"
        fi
    fi
}

# Restart service with backoff
restart_service() {
    local attempt="${1:-1}"

    log_process "Restarting service (attempt $attempt)..."

    # Stop current service
    stop_service false 15

    # Exponential backoff delay
    local delay=$((attempt * 5))
    if [[ $delay -gt 30 ]]; then
        delay=30
    fi

    log_process "Waiting ${delay} seconds before restart..."
    sleep "$delay"

    # Load configuration
    if [[ -f "${BASE_DIR}/.env" ]]; then
        set -a; source "${BASE_DIR}/.env"; set +a
    else
        log_process "Configuration file not found"
        return 1
    fi

    # Attempt restart
    if start_service "$PCODE" "$KEY" "${PORT:-443}"; then
        log_process "Service restarted successfully"
        return 0
    else
        if [[ $attempt -lt $RESTART_THRESHOLD ]]; then
            log_process "Restart failed. Retrying..."
            restart_service $((attempt + 1))
        else
            log_process "Restart failed after $RESTART_THRESHOLD attempts"
            return 1
        fi
    fi
}

# Get process status
get_status() {
    if is_service_running; then
        local pid
        pid=$(cat "$PID_FILE")

        local memory_mb cpu_percent uptime
        memory_mb=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}' || echo "unknown")
        cpu_percent=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print $1}' || echo "unknown")
        uptime=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ' || echo "unknown")

        echo "Status: RUNNING"
        echo "PID: $pid"
        echo "Memory: ${memory_mb}MB"
        echo "CPU: ${cpu_percent}%"
        echo "Uptime: $uptime"
    else
        echo "Status: STOPPED"
    fi

    # Show monitoring status
    if [[ -f "${BASE_DIR}/monitor.pid" ]]; then
        echo "Monitoring: ACTIVE"
    else
        echo "Monitoring: INACTIVE"
    fi
}

# Cleanup function
cleanup() {
    stop_monitoring
    rm -f "$LOCK_FILE"
}

# Main function
main() {
    local action="${1:-status}"

    # Acquire lock for most operations
    case "$action" in
        "status"|"monitor")
            # These don't need exclusive lock
            ;;
        *)
            if ! acquire_lock; then
                exit 1
            fi
            ;;
    esac

    case "$action" in
        "start")
            if [[ $# -lt 3 ]]; then
                echo "Usage: $0 start <pcode> <key> [port]"
                exit 1
            fi
            start_service "$2" "$3" "${4:-443}"
            ;;
        "stop")
            stop_service "${2:-false}"
            ;;
        "restart")
            restart_service
            ;;
        "status")
            get_status
            ;;
        "monitor")
            monitor_process
            ;;
        "start-monitoring")
            start_monitoring
            ;;
        "stop-monitoring")
            stop_monitoring
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|status|monitor|start-monitoring|stop-monitoring}"
            exit 1
            ;;
    esac
}

# Cleanup on exit
trap cleanup EXIT

# Execute main function
main "$@"