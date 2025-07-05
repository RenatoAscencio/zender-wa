#!/bin/bash
set -e

# --- Color Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Environment and File Definitions ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
EXECUTABLE_NAME="titansys-whatsapp-linux"
EXECUTABLE_PATH="${BASE_DIR}/${EXECUTABLE_NAME}"
DOWNLOAD_URL="https://raw.anycdn.link/wa/linux.zip"

# --- Clean Up Logs on Every Start ---
# This ensures a fresh log file on every redeploy.
echo -e "${YELLOW}🧹 Clearing previous log files...${NC}"
rm -f "${SERVICE_LOG_FILE}" "${CRON_LOG_FILE}" || true

# --- Display Build Information on Every Start ---
echo -e "\n${CYAN}--------------------------------------------------------${NC}"
echo -e "${CYAN}🚀 Starting WhatsApp Server Container${NC}"
echo -e "${CYAN}   Version:    ${VERSION:-unknown}${NC}"
echo -e "${CYAN}   Build Date: ${BUILD_DATE:-not specified}${NC}"
echo -e "${CYAN}--------------------------------------------------------${NC}\n"

# --- Always-on Services and Commands ---
echo -e "${YELLOW}🕒 Starting and configuring cron daemon...${NC}"
service cron start
AUTOSTART_SCRIPT_PATH="/usr/local/bin/autostart-wa"
# Create a robust autostart script with logging
cat << EOG_AUTO > "\$AUTOSTART_SCRIPT_PATH"
#!/bin/bash
exec >> ${CRON_LOG_FILE} 2>&1
echo "---"
echo "Cron job ran at: \$(date)"
if [ ! -f ${ENV_FILE} ]; then
  echo "Info: .env file not found. Service is not configured to run yet."
  exit 0
fi
set -a; source ${ENV_FILE}; set +a
if ! /usr/bin/pgrep -f "${EXECUTABLE_NAME}" > /dev/null; then
  echo "Service not running. Attempting to start..."
  # Start the service and redirect its output to the service log file
  cd "${BASE_DIR}" && ./"${EXECUTABLE_NAME}" --pcode="\$PCODE" --key="\$KEY" --host="0.0.0.0" --port="\$PORT" >> "${SERVICE_LOG_FILE}" 2>&1 &
  echo "Start command issued."
else
  echo "Service is already running."
fi
EOG_AUTO
chmod +x "\$AUTOSTART_SCRIPT_PATH"
(crontab -l 2>/dev/null | grep -v autostart-wa ; echo "* * * * * \${AUTOSTART_SCRIPT_PATH}" ; echo "@reboot \${AUTOSTART_SCRIPT_PATH}") | crontab -
echo -e "${GREEN}✅ Cron job for auto-restart is active.${NC}"

# --- Management Commands Creation ---
# (install-wa, config-wa, stop-wa, restart-wa, update-wa, status-wa)
# ... (El resto de la creación de comandos sigue igual)

# --- Main Entrypoint Logic ---
# Download binary only if it doesn't exist in the volume
if [ ! -f "$EXECUTABLE_PATH" ]; then
  echo -e "${YELLOW}📦 Binary not found. Performing first-time download...${NC}"
  cd "$BASE_DIR" && curl -fsSL "$DOWNLOAD_URL" -o linux.zip && unzip -o linux.zip && rm linux.zip && chmod +x "$EXECUTABLE_NAME"
fi

# Check if the service is configured (i.e., .env file exists)
if [ -f "$ENV_FILE" ]; then
  echo -e "${GREEN}✅ Configuration file found. Starting service in the background...${NC}"
  autostart-wa
  sleep 3
  status-wa
else
  # If not configured, go into standby mode
  echo -e "\n${CYAN}--------------------------------------------------------${NC}"
  echo -e "${RED}🔴 ACTION REQUIRED: Service is not configured.${NC}"
  echo -e "${CYAN}--------------------------------------------------------${NC}"
  echo "The container is now in standby mode."
  echo ""
  echo "   1. Open the console for this container."
  echo "   2. Run the command: ${GREEN}install-wa${NC}"
  echo ""
  echo -e "${CYAN}Available Commands:${NC}"
  echo "   - ${GREEN}install-wa${NC}, ${GREEN}config-wa${NC}, ${GREEN}update-wa${NC}, ${GREEN}restart-wa${NC}, ${GREEN}stop-wa${NC}, ${GREEN}status-wa${NC}"
  echo -e "${CYAN}--------------------------------------------------------${NC}"
fi

# Keep the container alive indefinitely
exec sleep infinity
