#!/bin/bash
set -e
set -o pipefail

# --- Color Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Display Build Information on Every Start ---
echo -e "\n${CYAN}--------------------------------------------------------${NC}"
echo -e "${CYAN}🚀 Starting WhatsApp Server Container${NC}"
echo -e "${CYAN}   Version:    ${VERSION:-unknown}${NC}"
echo -e "${CYAN}   Build Date: ${BUILD_DATE:-not specified}${NC}"
echo -e "${CYAN}   Author:     @RenatoAscencio${NC}"
echo -e "${CYAN}   Repository: https://github.com/RenatoAscencio/zender-wa${NC}"
echo -e "${CYAN}--------------------------------------------------------${NC}\n"

# --- Environment and File Definitions ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
PID_FILE="${BASE_DIR}/service.pid" # File to store the Process ID
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
EXECUTABLE_NAME="titansys-whatsapp-linux"
EXECUTABLE_PATH="${BASE_DIR}/${EXECUTABLE_NAME}"
DOWNLOAD_URL="${DOWNLOAD_URL_OVERRIDE:-https://raw.anycdn.link/wa/linux.zip}"

# --- Clean Up Logs on Every Start ---
echo -e "${YELLOW}🧹 Clearing previous log files...${NC}"
rm -f "${SERVICE_LOG_FILE}" "${CRON_LOG_FILE}" || true

# --- Management Commands Creation (Robust Method) ---
echo -e "${YELLOW}🔧 Creating management commands...${NC}"

# autostart-wa
AUTOSTART_SCRIPT_PATH="/usr/local/bin/autostart-wa"
cat << 'EOG_AUTO' > /tmp/autostart-wa.tmp
#!/bin/bash
# --- Shared Paths ---
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
set -a; source "${ENV_FILE}"; set +a
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
# --- Shared Paths ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
PID_FILE="${BASE_DIR}/service.pid"
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
EXECUTABLE_NAME="titansys-whatsapp-linux"
AUTOSTART_SCRIPT_PATH="/usr/local/bin/autostart-wa"
set -e
echo "--- WhatsApp Service Initial Installation ---"
if [ -n "$PCODE" ] && [ -n "$KEY" ]; then
    echo "✅ Environment variables found. Creating .env file automatically..."
    {
        echo "PORT=${PORT:-443}"
        echo "PCODE=$PCODE"
        echo "KEY=$KEY"
    } > "${ENV_FILE}"
elif [ ! -f "${ENV_FILE}" ]; then
    echo "⚠️ No .env file or environment variables found. Starting interactive setup..."
    /usr/local/bin/config-wa
fi
echo "🕒 Configuring and starting cron job for auto-restart..."
service cron start
# Update crontab, ensuring no duplicates and redirecting output to /dev/null
(crontab -l 2>/dev/null | grep -v "autostart-wa" ; echo "@reboot ${AUTOSTART_SCRIPT_PATH} >/dev/null 2>&1" ; echo "* * * * * ${AUTOSTART_SCRIPT_PATH} >/dev/null 2>&1") | crontab -
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
# --- Shared Paths ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
PID_FILE="${BASE_DIR}/service.pid"
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
EXECUTABLE_NAME="titansys-whatsapp-linux"
set -e
echo "--- Interactive .env Configuration ---"
if [ -f "${ENV_FILE}" ]; then set -a; source "${ENV_FILE}"; set +a; fi
read -p "Enter PORT [current: ${PORT:-443}]: " PORT_INPUT; PORT=${PORT_INPUT:-$PORT}
read -p "Enter your PCODE [current: ${PCODE}]: " PCODE_INPUT; PCODE=${PCODE_INPUT:-$PCODE}
read -p "Enter your KEY [current: ${KEY}]: " KEY_INPUT; KEY=${KEY_INPUT:-$KEY}
echo "Creating/updating .env file..."; { echo "PORT=$PORT"; echo "PCODE=$PCODE"; echo "KEY=$KEY"; } > "${ENV_FILE}"
echo "✅ .env file updated. Please run 'restart-wa' to apply the changes."
EOG_CONFIG
tr -d '\r' < /tmp/config-wa.tmp > /usr/local/bin/config-wa
rm /tmp/config-wa.tmp

# stop-wa
cat << 'EOG_STOP' > /tmp/stop-wa.tmp
#!/bin/bash
# --- Shared Paths ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
PID_FILE="${BASE_DIR}/service.pid"
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
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
# --- Shared Paths ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
PID_FILE="${BASE_DIR}/service.pid"
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
EXECUTABLE_NAME="titansys-whatsapp-linux"
AUTOSTART_SCRIPT_PATH="/usr/local/bin/autostart-wa"
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
# --- Shared Paths ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
PID_FILE="${BASE_DIR}/service.pid"
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
EXECUTABLE_NAME="titansys-whatsapp-linux"
DOWNLOAD_URL="${DOWNLOAD_URL_OVERRIDE:-https://raw.anycdn.link/wa/linux.zip}"
set -e
echo "--- Updating WhatsApp Service Binary ---"
/usr/local/bin/stop-wa
echo "Downloading latest binary from ${DOWNLOAD_URL}..."
cd "${BASE_DIR}"
curl -fsSL "${DOWNLOAD_URL}" -o linux.zip && unzip -oq linux.zip && rm linux.zip && chmod +x "${EXECUTABLE_NAME}"
echo "✅ Update complete. Triggering immediate restart...";
/usr/local/bin/autostart-wa
EOG_UPDATE
tr -d '\r' < /tmp/update-wa.tmp > /usr/local/bin/update-wa
rm /tmp/update-wa.tmp

# status-wa
cat << 'EOG_STATUS' > /tmp/status-wa.tmp
#!/bin/bash
# --- Shared Paths ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
PID_FILE="${BASE_DIR}/service.pid"
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m';
echo "--- WhatsApp Service Status ---"
if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}")" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Service is RUNNING${NC} with PID $(cat "${PID_FILE}")."
else
    echo -e "${RED}❌ Service is STOPPED.${NC}"
fi
echo -e "To see detailed logs, run: ${YELLOW}tail -f ${SERVICE_LOG_FILE}${NC}"
EOG_STATUS
tr -d '\r' < /tmp/status-wa.tmp > /usr/local/bin/status-wa
rm /tmp/status-wa.tmp

# Make all scripts executable
chmod +x /usr/local/bin/install-wa /usr/local/bin/stop-wa /usr/local/bin/restart-wa /usr/local/bin/update-wa /usr/local/bin/config-wa /usr/local/bin/status-wa /usr/local/bin/autostart-wa

echo -e "${GREEN}✅ All management commands created successfully.${NC}"

# --- Main Entrypoint Logic ---
echo -e "${YELLOW}📦 Preparing environment...${NC}"
if [ ! -f "${EXECUTABLE_PATH}" ]; then
  echo "Downloading binary for the first time from ${DOWNLOAD_URL}..."
  cd "${BASE_DIR}" && curl -fsSL "${DOWNLOAD_URL}" -o linux.zip && unzip -oq linux.zip && rm linux.zip && chmod +x "${EXECUTABLE_NAME}"
fi

echo -e "\n${CYAN}--------------------------------------------------------${NC}"
echo -e "${RED}🔴 ACTION REQUIRED: Environment is ready for setup.${NC}"
echo -e "${CYAN}--------------------------------------------------------${NC}"
echo "The container is now in standby mode."
echo ""
echo -e "   1. Open a shell into this container."
echo -e "   2. Run the command: ${GREEN}install-wa${NC}"
echo ""
echo -e "${CYAN}Available Commands:${NC}"
echo -e "   - ${GREEN}install-wa${NC} : Performs the first-time setup."
echo -e "   - ${GREEN}config-wa${NC}  : Edits the .env variables interactively."
echo -e "   - ${GREEN}update-wa${NC}  : Downloads the latest version of the binary."
echo -e "   - ${GREEN}restart-wa${NC} : Restarts the service."
echo -e "   - ${GREEN}stop-wa${NC}    : Stops the service."
echo -e "   - ${GREEN}status-wa${NC}  : Checks the current status of the service."
echo -e "${CYAN}--------------------------------------------------------${NC}"

# Keep the container alive indefinitely
exec sleep infinity
