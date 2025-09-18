#!/bin/bash
set -euo pipefail

# --- Configuration ---
readonly BASE_DIR="/data/whatsapp-server"
readonly SERVICE_LOG_FILE="${BASE_DIR}/service.log"
readonly CRON_LOG_FILE="${BASE_DIR}/cron.log"
readonly ERROR_LOG_FILE="${BASE_DIR}/error.log"
readonly EXECUTABLE_NAME="titansys-whatsapp-linux"
readonly EXECUTABLE_PATH="${BASE_DIR}/${EXECUTABLE_NAME}"
readonly PID_FILE="${BASE_DIR}/service.pid"
readonly ENV_FILE="${BASE_DIR}/.env"
readonly DOWNLOAD_URL="${DOWNLOAD_URL_OVERRIDE:-https://raw.anycdn.link/wa/linux.zip}"

# --- Logging Functions ---
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*" | tee -a "${SERVICE_LOG_FILE}"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" | tee -a "${ERROR_LOG_FILE}" >&2
}

log_warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $*" | tee -a "${SERVICE_LOG_FILE}"
}

# --- Color Definitions ---
readonly NC='\033[0m'
readonly BOLD='\033[1m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly LIGHT_RED='\033[1;31m'
readonly LIGHT_GREEN='\033[1;32m'
readonly LIGHT_BLUE='\033[1;34m'
readonly LIGHT_CYAN='\033[1;36m'

# --- Helper Functions ---
print_header() {
    echo
    echo -e "${LIGHT_BLUE}${BOLD}╭────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${LIGHT_BLUE}${BOLD}│${NC} ${CYAN}🚀 WhatsApp Server Container - Optimized Version${NC}      ${LIGHT_BLUE}${BOLD}│${NC}"
    echo -e "${LIGHT_BLUE}${BOLD}├────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${LIGHT_BLUE}${BOLD}│${NC} ${CYAN}Version:${NC}    ${VERSION:-unknown}"
    echo -e "${LIGHT_BLUE}${BOLD}│${NC} ${CYAN}Build Date:${NC} ${BUILD_DATE:-not specified}"
    echo -e "${LIGHT_BLUE}${BOLD}│${NC} ${CYAN}Author:${NC}     @RenatoAscencio"
    echo -e "${LIGHT_BLUE}${BOLD}╰────────────────────────────────────────────────────────────╯${NC}"
    echo
}

validate_environment() {
    log_info "Validating environment..."

    # Check if running as non-root
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root user. Consider using non-root for security."
    fi

    # Create necessary directories
    mkdir -p "${BASE_DIR}" "$(dirname "${SERVICE_LOG_FILE}")"

    # Setup log rotation
    if command -v logrotate >/dev/null 2>&1; then
        cat > /tmp/whatsapp-logrotate << EOF
${SERVICE_LOG_FILE} ${CRON_LOG_FILE} ${ERROR_LOG_FILE} {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    copytruncate
    maxsize 10M
}
EOF
        sudo mv /tmp/whatsapp-logrotate /etc/logrotate.d/whatsapp 2>/dev/null || true
    fi
}

cleanup_old_logs() {
    log_info "Cleaning up old log files..."

    # Rotate logs if they're too large
    for logfile in "${SERVICE_LOG_FILE}" "${CRON_LOG_FILE}" "${ERROR_LOG_FILE}"; do
        if [[ -f "$logfile" ]] && [[ $(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null || echo 0) -gt 10485760 ]]; then
            mv "$logfile" "${logfile}.old" 2>/dev/null || true
            touch "$logfile"
        fi
    done
}

# --- Management Script Generator ---
generate_management_scripts() {
    log_info "Generating optimized management scripts..."

    local scripts=(
        "autostart-wa:create_autostart_script"
        "install-wa:create_install_script"
        "config-wa:create_config_script"
        "stop-wa:create_stop_script"
        "restart-wa:create_restart_script"
        "update-wa:create_update_script"
        "status-wa:create_status_script"
    )

    for script_def in "${scripts[@]}"; do
        local script_name="${script_def%%:*}"
        local function_name="${script_def##*:}"
        local script_path="/usr/local/bin/${script_name}"

        $function_name > "$script_path"
        chmod +x "$script_path"
    done

    log_info "Management scripts created successfully"
}

create_autostart_script() {
cat << 'EOF'
#!/bin/bash
set -euo pipefail

readonly BASE_DIR="/data/whatsapp-server"
readonly ENV_FILE="${BASE_DIR}/.env"
readonly PID_FILE="${BASE_DIR}/service.pid"
readonly SERVICE_LOG_FILE="${BASE_DIR}/service.log"
readonly CRON_LOG_FILE="${BASE_DIR}/cron.log"
readonly EXECUTABLE_NAME="titansys-whatsapp-linux"

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [AUTOSTART] $*" >> "${CRON_LOG_FILE}"
}

# Check if service is already running
if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
    log_info "Service already running with PID $(cat "${PID_FILE}")"
    exit 0
fi

# Check if configuration exists
if [[ ! -f "${ENV_FILE}" ]]; then
    log_info "Configuration file not found. Skipping autostart."
    exit 0
fi

# Clean up stale PID file
rm -f "${PID_FILE}"

# Source environment variables
set -a; source "${ENV_FILE}"; set +a

# Validate required variables
if [[ -z "${PCODE:-}" ]] || [[ -z "${KEY:-}" ]]; then
    log_info "Missing required configuration. Please run config-wa"
    exit 1
fi

# Start the service
log_info "Starting WhatsApp service..."
cd "${BASE_DIR}"

nohup "./${EXECUTABLE_NAME}" \
    --pcode="$PCODE" \
    --key="$KEY" \
    --host="0.0.0.0" \
    --port="${PORT:-443}" \
    >> "${SERVICE_LOG_FILE}" 2>&1 &

pid=$!
echo "$pid" > "${PID_FILE}"
log_info "Service started with PID $pid"
EOF
}

create_install_script() {
cat << 'EOF'
#!/bin/bash
set -euo pipefail

echo "--- WhatsApp Service Installation ---"

# Auto-configuration from environment variables
if [[ -n "${PCODE:-}" ]] && [[ -n "${KEY:-}" ]]; then
    echo "✅ Environment variables detected. Creating configuration..."
    cat > "/data/whatsapp-server/.env" << EOL
PORT=${PORT:-443}
PCODE=$PCODE
KEY=$KEY
EOL
elif [[ ! -f "/data/whatsapp-server/.env" ]]; then
    echo "⚠️ No configuration found. Starting interactive setup..."
    /usr/local/bin/config-wa
fi

# Setup cron for auto-restart
echo "🕒 Configuring auto-restart service..."
if command -v crond >/dev/null 2>&1; then
    crond -b
    sleep 2

    # Add cron jobs
    (crontab -l 2>/dev/null || true; echo "* * * * * /usr/local/bin/autostart-wa >/dev/null 2>&1") | \
        sort -u | crontab -

    echo "✅ Auto-restart configured"
else
    echo "⚠️ Cron not available. Manual restart required"
fi

# Start the service
echo "🚀 Starting service..."
/usr/local/bin/autostart-wa
sleep 3
/usr/local/bin/status-wa
EOF
}

create_config_script() {
cat << 'EOF'
#!/bin/bash
set -euo pipefail

echo "--- Interactive Configuration ---"

# Load existing configuration if available
if [[ -f "/data/whatsapp-server/.env" ]]; then
    set -a; source "/data/whatsapp-server/.env"; set +a
fi

# Interactive configuration
read -p "Enter PORT [${PORT:-443}]: " port_input
PORT="${port_input:-${PORT:-443}}"

read -p "Enter PCODE [${PCODE:-}]: " pcode_input
PCODE="${pcode_input:-${PCODE:-}}"

read -p "Enter KEY [${KEY:-}]: " key_input
KEY="${key_input:-${KEY:-}}"

# Validate inputs
if [[ -z "$PCODE" ]] || [[ -z "$KEY" ]]; then
    echo "❌ PCODE and KEY are required"
    exit 1
fi

# Save configuration
cat > "/data/whatsapp-server/.env" << EOL
PORT=$PORT
PCODE=$PCODE
KEY=$KEY
EOL

echo "✅ Configuration saved. Run 'restart-wa' to apply changes."
EOF
}

create_stop_script() {
cat << 'EOF'
#!/bin/bash
set -euo pipefail

readonly PID_FILE="/data/whatsapp-server/service.pid"
readonly EXECUTABLE_NAME="titansys-whatsapp-linux"

echo "🛑 Stopping WhatsApp service..."

if [[ ! -f "${PID_FILE}" ]]; then
    echo "No PID file found. Attempting graceful shutdown..."
    pkill -f "${EXECUTABLE_NAME}" 2>/dev/null || true
    echo "Service stopped"
    exit 0
fi

pid=$(cat "${PID_FILE}")

if ! kill -0 "$pid" 2>/dev/null; then
    echo "Process $pid not running. Cleaning up..."
    rm -f "${PID_FILE}"
    exit 0
fi

# Graceful shutdown
echo "Sending SIGTERM to process $pid..."
kill "$pid"

# Wait for graceful shutdown
for i in {1..15}; do
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Process stopped gracefully"
        rm -f "${PID_FILE}"
        exit 0
    fi
    echo -n "."
    sleep 1
done

# Force kill if needed
echo ""
echo "Process did not stop gracefully. Force killing..."
kill -9 "$pid" 2>/dev/null || true
rm -f "${PID_FILE}"
echo "Process force stopped"
EOF
}

create_restart_script() {
cat << 'EOF'
#!/bin/bash
set -euo pipefail

echo "🔄 Restarting WhatsApp service..."
/usr/local/bin/stop-wa
sleep 3
/usr/local/bin/autostart-wa
sleep 2
/usr/local/bin/status-wa
EOF
}

create_update_script() {
cat << 'EOF'
#!/bin/bash
set -euo pipefail

readonly DOWNLOAD_URL="${DOWNLOAD_URL_OVERRIDE:-https://raw.anycdn.link/wa/linux.zip}"
readonly BASE_DIR="/data/whatsapp-server"

echo "--- Binary Update ---"

# Stop service
/usr/local/bin/stop-wa

# Backup current binary
if [[ -f "${BASE_DIR}/titansys-whatsapp-linux" ]]; then
    cp "${BASE_DIR}/titansys-whatsapp-linux" "${BASE_DIR}/titansys-whatsapp-linux.backup"
fi

# Download with retry logic
echo "Downloading from ${DOWNLOAD_URL}..."
cd "$BASE_DIR"

for attempt in {1..3}; do
    if curl -fsSL --connect-timeout 30 "${DOWNLOAD_URL}" -o linux.zip; then
        break
    fi
    echo "Download attempt $attempt failed. Retrying..."
    sleep 5
done

if [[ ! -f linux.zip ]]; then
    echo "❌ Download failed after 3 attempts"
    exit 1
fi

# Verify and extract
if unzip -tq linux.zip; then
    unzip -oq linux.zip
    rm linux.zip
    chmod +x "titansys-whatsapp-linux"
    echo "✅ Update successful"
else
    echo "❌ Downloaded file is corrupted"
    rm -f linux.zip
    exit 1
fi

# Start service
/usr/local/bin/autostart-wa
/usr/local/bin/status-wa
EOF
}

create_status_script() {
cat << 'EOF'
#!/bin/bash

readonly PID_FILE="/data/whatsapp-server/service.pid"
readonly SERVICE_LOG_FILE="/data/whatsapp-server/service.log"
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

echo "--- WhatsApp Service Status ---"

if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
    pid=$(cat "${PID_FILE}")
    uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || echo "unknown")

    echo -e "${GREEN}${BOLD}✅ Service is RUNNING${NC}"
    echo -e "   PID: $pid"
    echo -e "   Uptime: $uptime"
else
    echo -e "${RED}${BOLD}❌ Service is STOPPED${NC}"
fi

echo
echo -e "📊 System Information:"
echo -e "   Memory: $(free -h 2>/dev/null | awk '/^Mem:/ {print $3"/"$2}' || echo 'N/A')"
echo -e "   Disk: $(df -h /data 2>/dev/null | awk 'NR==2 {print $3"/"$2" ("$5")"}' || echo 'N/A')"

echo
echo -e "📋 Log Commands:"
echo -e "   Service logs: ${YELLOW}tail -f ${SERVICE_LOG_FILE}${NC}"
echo -e "   Error logs:   ${YELLOW}tail -f /data/whatsapp-server/error.log${NC}"
EOF
}

# --- Signal Handling ---
cleanup() {
    log_info "Received shutdown signal. Cleaning up..."
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping service with PID $pid"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 5
        fi
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT

# --- Main Execution ---
main() {
    print_header
    validate_environment
    cleanup_old_logs
    generate_management_scripts

    log_info "Container initialization complete"

    # Display usage instructions
    echo -e "${LIGHT_RED}${BOLD}🔴 Next Steps:${NC}"
    echo -e "   1. Access container shell: ${GREEN}docker exec -it <container> bash${NC}"
    echo -e "   2. Run setup: ${GREEN}install-wa${NC}"
    echo
    echo -e "${LIGHT_CYAN}${BOLD}📖 Available Commands:${NC}"
    echo -e "   ${GREEN}install-wa${NC}  - Initial setup and configuration"
    echo -e "   ${GREEN}config-wa${NC}   - Modify configuration interactively"
    echo -e "   ${GREEN}update-wa${NC}   - Update to latest binary version"
    echo -e "   ${GREEN}restart-wa${NC}  - Restart the service"
    echo -e "   ${GREEN}stop-wa${NC}     - Stop the service"
    echo -e "   ${GREEN}status-wa${NC}   - Check service status and health"
    echo

    # Keep container alive
    exec sleep infinity
}

# Execute main function
main "$@"