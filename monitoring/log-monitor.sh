#!/bin/bash
# Log Monitoring and Analysis Script
# Provides real-time log analysis and alerting

set -euo pipefail

readonly BASE_DIR="/data/whatsapp-server"
readonly SERVICE_LOG_FILE="${BASE_DIR}/service.log"
readonly ERROR_LOG_FILE="${BASE_DIR}/error.log"
readonly ALERT_LOG_FILE="${BASE_DIR}/alerts.log"

# Alert thresholds
readonly ERROR_THRESHOLD=10  # Max errors per minute
readonly WARNING_THRESHOLD=20  # Max warnings per minute

# Alert notification function
send_alert() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" >> "$ALERT_LOG_FILE"

    # Could integrate with external alerting systems here
    case "$level" in
        "CRITICAL")
            echo "🚨 CRITICAL ALERT: $message" >&2
            ;;
        "WARNING")
            echo "⚠️  WARNING: $message" >&2
            ;;
        "INFO")
            echo "ℹ️  INFO: $message"
            ;;
    esac
}

# Analyze log patterns
analyze_logs() {
    local timeframe="${1:-1}"  # Minutes to analyze
    local since_time
    since_time=$(date -d "$timeframe minutes ago" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -j -v-"${timeframe}M" '+%Y-%m-%d %H:%M:%S')

    if [[ ! -f "$SERVICE_LOG_FILE" ]]; then
        send_alert "WARNING" "Service log file not found"
        return 1
    fi

    # Count errors in the last timeframe
    local error_count warning_count
    error_count=$(grep -c "\[ERROR\]" "$SERVICE_LOG_FILE" 2>/dev/null || echo "0")
    warning_count=$(grep -c "\[WARN\]" "$SERVICE_LOG_FILE" 2>/dev/null || echo "0")

    # Check thresholds
    if [[ $error_count -gt $ERROR_THRESHOLD ]]; then
        send_alert "CRITICAL" "High error rate: $error_count errors in last $timeframe minutes"
    fi

    if [[ $warning_count -gt $WARNING_THRESHOLD ]]; then
        send_alert "WARNING" "High warning rate: $warning_count warnings in last $timeframe minutes"
    fi

    # Specific error pattern detection
    check_specific_patterns
}

# Check for specific error patterns
check_specific_patterns() {
    local recent_logs
    recent_logs=$(tail -n 100 "$SERVICE_LOG_FILE" 2>/dev/null || echo "")

    # Check for connection issues
    if echo "$recent_logs" | grep -qi "connection.*failed\|timeout\|network.*error"; then
        send_alert "WARNING" "Network connectivity issues detected"
    fi

    # Check for authentication errors
    if echo "$recent_logs" | grep -qi "auth.*failed\|invalid.*key\|unauthorized"; then
        send_alert "CRITICAL" "Authentication errors detected"
    fi

    # Check for memory issues
    if echo "$recent_logs" | grep -qi "out of memory\|memory.*error\|oom"; then
        send_alert "CRITICAL" "Memory issues detected"
    fi

    # Check for disk space issues
    if echo "$recent_logs" | grep -qi "disk.*full\|no space\|write.*failed"; then
        send_alert "CRITICAL" "Disk space issues detected"
    fi
}

# Monitor logs in real-time
monitor_realtime() {
    echo "Starting real-time log monitoring..."
    send_alert "INFO" "Log monitoring started"

    # Monitor service log
    if [[ -f "$SERVICE_LOG_FILE" ]]; then
        tail -f "$SERVICE_LOG_FILE" | while read -r line; do
            case "$line" in
                *"[ERROR]"*)
                    send_alert "WARNING" "Service error: $line"
                    ;;
                *"[CRITICAL]"*)
                    send_alert "CRITICAL" "Service critical: $line"
                    ;;
                *"crash"*|*"fatal"*|*"panic"*)
                    send_alert "CRITICAL" "Service crash detected: $line"
                    ;;
            esac
        done &
    fi

    # Run periodic analysis
    while true; do
        analyze_logs 1
        sleep 60
    done
}

# Generate log summary
generate_summary() {
    local hours="${1:-24}"
    echo "=== Log Summary (Last $hours hours) ==="

    if [[ ! -f "$SERVICE_LOG_FILE" ]]; then
        echo "No service log file found"
        return 1
    fi

    local total_lines error_count warning_count info_count
    total_lines=$(wc -l < "$SERVICE_LOG_FILE" 2>/dev/null || echo "0")
    error_count=$(grep -c "\[ERROR\]" "$SERVICE_LOG_FILE" 2>/dev/null || echo "0")
    warning_count=$(grep -c "\[WARN\]" "$SERVICE_LOG_FILE" 2>/dev/null || echo "0")
    info_count=$(grep -c "\[INFO\]" "$SERVICE_LOG_FILE" 2>/dev/null || echo "0")

    echo "Total log entries: $total_lines"
    echo "Errors: $error_count"
    echo "Warnings: $warning_count"
    echo "Info messages: $info_count"
    echo

    # Show recent errors
    if [[ $error_count -gt 0 ]]; then
        echo "Recent errors:"
        grep "\[ERROR\]" "$SERVICE_LOG_FILE" | tail -n 5 || true
        echo
    fi

    # Show top error patterns
    echo "Top error patterns:"
    grep "\[ERROR\]" "$SERVICE_LOG_FILE" 2>/dev/null | \
        sed 's/.*\[ERROR\]//' | \
        sort | uniq -c | sort -nr | head -n 5 || echo "No errors found"
}

# Rotate large log files
rotate_logs() {
    local max_size=$((50 * 1024 * 1024))  # 50MB

    for logfile in "$SERVICE_LOG_FILE" "$ERROR_LOG_FILE" "$ALERT_LOG_FILE"; do
        if [[ -f "$logfile" ]]; then
            local size
            size=$(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null || echo 0)

            if [[ $size -gt $max_size ]]; then
                echo "Rotating large log file: $logfile"
                mv "$logfile" "${logfile}.$(date +%Y%m%d-%H%M%S)"
                touch "$logfile"
                send_alert "INFO" "Log file rotated: $logfile"
            fi
        fi
    done
}

# Main function
main() {
    case "${1:-summary}" in
        "monitor"|"realtime")
            monitor_realtime
            ;;
        "analyze")
            analyze_logs "${2:-5}"
            ;;
        "summary")
            generate_summary "${2:-24}"
            ;;
        "rotate")
            rotate_logs
            ;;
        *)
            echo "Usage: $0 {monitor|analyze|summary|rotate}"
            echo "  monitor   - Start real-time monitoring"
            echo "  analyze   - Analyze logs for patterns"
            echo "  summary   - Generate log summary"
            echo "  rotate    - Rotate large log files"
            exit 1
            ;;
    esac
}

main "$@"