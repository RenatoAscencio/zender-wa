#!/bin/bash
set -e
set -o pipefail

# --- Visual & Color Definitions ---
NC='\033[0m' # No Color
BOLD='\033[1m'
UNDERLINE='\033[4m'
# --- Standard Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
# --- Bright Colors ---
LIGHT_RED='\033[1;31m'
LIGHT_GREEN='\033[1;32m'
LIGHT_YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_MAGENTA='\033[1;35m'
LIGHT_CYAN='\033[1;36m'

# --- Box Drawing Characters ---
T_LEFT="╭"
T_RIGHT="╮"
B_LEFT="╰"
B_RIGHT="╯"
H_LINE="─"
V_LINE="│"
M_LEFT="├"
M_RIGHT="┤"

# --- Helper function for printing styled boxes ---
print_box() {
    local title=$1
    local color=$2
    local width=60
    local title_len=${#title}
    local padding_total=$((width - title_len - 4))
    local padding_left=$((padding_total / 2))
    local padding_right=$((padding_total - padding_left))

    echo -e "${color}${BOLD}${T_LEFT}$(printf '%*s' "$width" '' | tr ' ' "${H_LINE}")${T_RIGHT}${NC}"
    echo -e "${color}${BOLD}${V_LINE} $(printf '%*s' "$padding_left" '')${title}$(printf '%*s' "$padding_right" '') ${V_LINE}${NC}"
    echo -e "${color}${BOLD}${M_LEFT}$(printf '%*s' "$width" '' | tr ' ' "${H_LINE}")${M_RIGHT}${NC}"
}

# --- Display Build Information on Every Start ---
echo
print_box "🚀 WhatsApp Server Container" "${LIGHT_BLUE}"
echo -e "${LIGHT_BLUE}${BOLD}${V_LINE}${NC} ${CYAN}Version:${NC}    ${VERSION:-unknown}"
echo -e "${LIGHT_BLUE}${BOLD}${V_LINE}${NC} ${CYAN}Build Date:${NC} ${BUILD_DATE:-not specified}"
echo -e "${LIGHT_BLUE}${BOLD}${V_LINE}${NC} ${CYAN}Author:${NC}     @RenatoAscencio"
echo -e "${LIGHT_BLUE}${BOLD}${V_LINE}${NC} ${CYAN}Repository:${NC} https://github.com/RenatoAscencio/zender-wa"
echo -e "${LIGHT_BLUE}${BOLD}${B_LEFT}$(printf '%*s' 60 '' | tr ' ' "${H_LINE}")${B_RIGHT}${NC}\n"


# --- Environment and File Definitions ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
PID_FILE="${BASE_DIR}/service.pid"
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
EXECUTABLE_NAME="titansys-whatsapp-linux"
EXECUTABLE_PATH="${BASE_DIR}/${EXECUTABLE_NAME}"
DOWNLOAD_URL="${DOWNLOAD_URL_OVERRIDE:-https://raw.anycdn.link/wa/linux.zip}"

# --- Clean Up Logs on Every Start ---
echo -e "${YELLOW}${BOLD}🧹 Clearing previous log files...${NC}"
rm -f "${SERVICE_LOG_FILE}" "${CRON_LOG_FILE}" || true

# --- Management Commands Creation (Robust Method) ---
echo -e "${LIGHT_MAGENTA}${BOLD}🔧 Creating management commands...${NC}"

# autostart-wa
AUTOSTART_SCRIPT_PATH="/usr/local/bin/autostart-wa"
cat << 'EOG_AUTO' > /tmp/autostart-wa.tmp
#!/bin/bash
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
PID_FILE="${BASE_DIR}/service.pid"
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
EXECUTABLE_NAME="titansys-whatsapp-linux"
exec >> ${CRON_LOG_FILE} 2>&1
echo "---"
echo "Cron job ran at: $(date)"
if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}")" > /dev/null 2>&1; then
  echo "Service is already running with PID $(cat "${PID_FILE}")."
  exit 0
fi
if [ ! -f "${ENV_FILE}" ]; then
  echo "Info: .env file not found. Service is not configured to run yet."
  exit 0
fi
rm -f "${PID_FILE}"
echo "Service not running. Attempting to start..."
set -a; source ${ENV_FILE}; set +a
cd "${BASE_DIR}"
nohup ./${EXECUTABLE_NAME} --pcode="$PCODE" --key="$KEY" --host="0.0.0.0" --port="$PORT" >> "${SERVICE_LOG_FILE}" 2>&1 &
PID=$!
echo "${PID}" > "${PID_FILE}"
echo "Start command issued. Service running with PID ${PID}."
EOG_AUTO
tr -d '\r' < /tmp/autostart-wa.tmp > "${AUTOSTART_SCRIPT_PATH}"
rm /tmp/autostart-wa.tmp

# install-wa
cat << 'EOG_INSTALL' > /tmp/install-wa.tmp
#!/bin/bash
AUTOSTART_SCRIPT_PATH="/usr/local/bin/autostart-wa"
set -e
echo "--- WhatsApp Service Initial Installation ---"
if [ -n "$PCODE" ] && [ -n "$KEY" ]; then
    echo "✅ Environment variables found. Creating .env file automatically..."
    {
        echo "PORT=${PORT:-443}"
        echo "PCODE=$PCODE"
        echo "KEY=$KEY"
    } > "/data/whatsapp-server/.env"
elif [ ! -f "/data/whatsapp-server/.env" ]; then
    echo "⚠️ No .env file or environment variables found. Starting interactive setup..."
    /usr/local/bin/config-wa
fi
echo "🕒 Configuring and starting cron job for auto-restart..."
service cron start
( crontab -l 2>/dev/null; echo "@reboot ${AUTOSTART_SCRIPT_PATH} >/dev/null 2>&1"; echo "* * * * * ${AUTOSTART_SCRIPT_PATH} >/dev/null 2>&1" ) | crontab -
echo "✅ Cron job configured."
echo "🚀 Triggering service start..."
/usr/local/bin/autostart-wa
sleep 3
/usr/local/bin/status-wa
EOG_INSTALL
tr -d '\r' < /tmp/install-wa.tmp > /usr/local/bin/install-wa
rm /tmp/install-wa.tmp

# config-wa
cat << 'EOG_CONFIG' > /tmp/config-wa.tmp
#!/bin/bash
set -e
echo "--- Interactive .env Configuration ---"
if [ -f "/data/whatsapp-server/.env" ]; then set -a; source "/data/whatsapp-server/.env"; set +a; fi
read -p "Enter PORT [current: ${PORT:-443}]: " PORT_INPUT; PORT=${PORT_INPUT:-$PORT}
read -p "Enter your PCODE [current: ${PCODE}]: " PCODE_INPUT; PCODE=${PCODE_INPUT:-$PCODE}
read -p "Enter your KEY [current: ${KEY}]: " KEY_INPUT; KEY=${KEY_INPUT:-$KEY}
echo "Creating/updating .env file..."; { echo "PORT=$PORT"; echo "PCODE=$PCODE"; echo "KEY=$KEY"; } > "/data/whatsapp-server/.env"
echo "✅ .env file updated. Please run 'restart-wa' to apply the changes."
EOG_CONFIG
tr -d '\r' < /tmp/config-wa.tmp > /usr/local/bin/config-wa
rm /tmp/config-wa.tmp

# stop-wa
cat << 'EOG_STOP' > /tmp/stop-wa.tmp
#!/bin/bash
PID_FILE="/data/whatsapp-server/service.pid"
EXECUTABLE_NAME="titansys-whatsapp-linux"
echo -e "🛑 Stopping the WhatsApp service..."
if [ ! -f "${PID_FILE}" ]; then
    echo "PID file not found. Is the service running? Attempting to stop by name as a fallback."
    pkill -f "${EXECUTABLE_NAME}" || true
else
    PID=$(cat "${PID_FILE}")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Stopping process with PID ${PID}..."
        kill "${PID}"
        for i in {1..10}; do
            if ! kill -0 "${PID}" > /dev/null 2>&1; then
                echo -e "\nProcess stopped."
                break
            fi
            echo -n "."
            sleep 1
        done
        if kill -0 "${PID}" > /dev/null 2>&1; then
            echo -e "\nProcess did not stop with SIGTERM, forcing kill..."
            kill -9 "${PID}" || true
            sleep 1
        fi
    else
        echo "Process with PID ${PID} does not exist. Cleaning up PID file."
    fi
    rm -f "${PID_FILE}"
fi
echo "Service stopped. The cron job will restart it within a minute."
EOG_STOP
tr -d '\r' < /tmp/stop-wa.tmp > /usr/local/bin/stop-wa
rm /tmp/stop-wa.tmp

# restart-wa
cat << 'EOG_RESTART' > /tmp/restart-wa.tmp
#!/bin/bash
echo "🔄 Restarting the WhatsApp service...";
/usr/local/bin/stop-wa
sleep 2;
echo "Triggering immediate restart...";
/usr/local/bin/autostart-wa
sleep 1
/usr/local/bin/status-wa
EOG_RESTART
tr -d '\r' < /tmp/restart-wa.tmp > /usr/local/bin/restart-wa
rm /tmp/restart-wa.tmp

# update-wa
cat << 'EOG_UPDATE' > /tmp/update-wa.tmp
#!/bin/bash
DOWNLOAD_URL="${DOWNLOAD_URL_OVERRIDE:-https://raw.anycdn.link/wa/linux.zip}"
set -e
echo "--- Updating WhatsApp Service Binary ---"
/usr/local/bin/stop-wa
echo "Downloading latest binary from ${DOWNLOAD_URL}..."
cd "/data/whatsapp-server"
curl -fsSL "${DOWNLOAD_URL}" -o linux.zip && unzip -oq linux.zip && rm linux.zip && chmod +x "titansys-whatsapp-linux"
echo "✅ Update complete. Triggering immediate restart...";
/usr/local/bin/autostart-wa
EOG_UPDATE
tr -d '\r' < /tmp/update-wa.tmp > /usr/local/bin/update-wa
rm /tmp/update-wa.tmp

# status-wa
cat << 'EOG_STATUS' > /tmp/status-wa.tmp
#!/bin/bash
PID_FILE="/data/whatsapp-server/service.pid"
SERVICE_LOG_FILE="/data/whatsapp-server/service.log"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m';
echo "--- WhatsApp Service Status ---"
if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}")" > /dev/null 2>&1; then
    echo -e "${GREEN}${BOLD}✅ Service is RUNNING${NC} with PID $(cat "${PID_FILE}")."
else
    echo -e "${RED}${BOLD}❌ Service is STOPPED.${NC}"
fi
echo -e "To see detailed logs, run: ${YELLOW}tail -f ${SERVICE_LOG_FILE}${NC}"
EOG_STATUS
tr -d '\r' < /tmp/status-wa.tmp > /usr/local/bin/status-wa
rm /tmp/status-wa.tmp

# Make all scripts executable
chmod +x /usr/local/bin/install-wa /usr/local/bin/stop-wa /usr/local/bin/restart-wa /usr/local/bin/update-wa /usr/local/bin/config-wa /usr/local/bin/status-wa /usr/local/bin/autostart-wa

echo -e "${LIGHT_GREEN}${BOLD}✅ All management commands created successfully.${NC}\n"

# --- Main Entrypoint Logic ---
echo -e "${YELLOW}${BOLD}📦 Preparing environment...${NC}"
if [ ! -f "${EXECUTABLE_PATH}" ]; then
  echo "Downloading binary for the first time from ${DOWNLOAD_URL}..."
  cd "${BASE_DIR}" && curl -fsSL "${DOWNLOAD_URL}" -o linux.zip && unzip -oq linux.zip && rm linux.zip && chmod +x "${EXECUTABLE_NAME}"
fi

# --- Final Instructions ---
print_box "🔴 ACTION REQUIRED" "${LIGHT_RED}"
echo -e "${LIGHT_RED}${BOLD}${V_LINE}${NC} The container is ready for setup."
echo -e "${LIGHT_RED}${BOLD}${V_LINE}${NC}"
echo -e "${LIGHT_RED}${BOLD}${V_LINE}${NC}   1. Open a shell into this container."
echo -e "${LIGHT_RED}${BOLD}${V_LINE}${NC}   2. Run the command: ${LIGHT_GREEN}install-wa${NC}"
echo -e "${LIGHT_RED}${BOLD}${B_LEFT}$(printf '%*s' 60 '' | tr ' ' "${H_LINE}")${B_RIGHT}${NC}\n"

print_box "📖 Available Commands" "${LIGHT_CYAN}"
echo -e "${LIGHT_CYAN}${BOLD}${V_LINE}${NC} ${GREEN}install-wa${NC} : Performs the first-time setup."
echo -e "${LIGHT_CYAN}${BOLD}${V_LINE}${NC} ${GREEN}config-wa${NC}  : Edits the .env variables interactively."
echo -e "${LIGHT_CYAN}${BOLD}${V_LINE}${NC} ${GREEN}update-wa${NC}  : Downloads the latest version of the binary."
echo -e "${LIGHT_CYAN}${BOLD}${V_LINE}${NC} ${GREEN}restart-wa${NC} : Restarts the service."
echo -e "${LIGHT_CYAN}${BOLD}${V_LINE}${NC} ${GREEN}stop-wa${NC}    : Stops the service."
echo -e "${LIGHT_CYAN}${BOLD}${V_LINE}${NC} ${GREEN}status-wa${NC}  : Checks the current status of the service."
echo -e "${LIGHT_CYAN}${BOLD}${B_LEFT}$(printf '%*s' 60 '' | tr ' ' "${H_LINE}")${B_RIGHT}${NC}"

# Keep the container alive indefinitely
exec sleep infinity
