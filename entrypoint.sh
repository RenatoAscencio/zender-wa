#!/bin/bash
set -e

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
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
EXECUTABLE_NAME="titansys-whatsapp-linux"
EXECUTABLE_PATH="${BASE_DIR}/${EXECUTABLE_NAME}"
DOWNLOAD_URL="https://raw.anycdn.link/wa/linux.zip"

# --- Clean Up Logs on Every Start ---
echo -e "${YELLOW}🧹 Clearing previous log files...${NC}"
rm -f "${SERVICE_LOG_FILE}" "${CRON_LOG_FILE}" || true

# --- Management Commands Creation ---
echo -e "${YELLOW}🔧 Creating management commands...${NC}"

# autostart-wa (The cron watchdog script)
AUTOSTART_SCRIPT_PATH="/usr/local/bin/autostart-wa"
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
  cd "${BASE_DIR}" && ./"${EXECUTABLE_NAME}" --pcode="\$PCODE" --key="\$KEY" --host="0.0.0.0" --port="\$PORT" >> "${SERVICE_LOG_FILE}" 2>&1 &
  echo "Start command issued."
else
  echo "Service is already running."
fi
EOG_AUTO
chmod +x "\$AUTOSTART_SCRIPT_PATH"

# install-wa (The main setup and first-run command)
cat << EOG > /usr/local/bin/install-wa
#!/bin/bash
set -e
echo "--- WhatsApp Service Initial Installation ---"
if [ -n "\$PCODE" ] && [ -n "\$KEY" ]; then
    echo "✅ Environment variables found. Creating .env file automatically..."
    {
        echo "PORT=\${PORT:-443}"
        echo "PCODE=\$PCODE"
        echo "KEY=\$KEY"
    } > "${ENV_FILE}"
elif [ ! -f "${ENV_FILE}" ]; then
    echo "⚠️ No .env file or environment variables found. Starting interactive setup..."
    /usr/local/bin/config-wa
fi
echo "🕒 Configuring and starting cron job for auto-restart..."
service cron start
(crontab -l 2>/dev/null | grep -v autostart-wa ; echo "* * * * * ${AUTOSTART_SCRIPT_PATH}" ; echo "@reboot ${AUTOSTART_SCRIPT_PATH}") | crontab -
echo "✅ Cron job configured."
echo "🚀 Triggering service start..."
/usr/local/bin/autostart-wa
sleep 3
/usr/local/bin/status-wa
EOG
chmod +x /usr/local/bin/install-wa

# config-wa (Interactive .env editor)
cat << EOG > /usr/local/bin/config-wa
#!/bin/bash
set -e
echo "--- Interactive .env Configuration ---"
if [ -f "${ENV_FILE}" ]; then set -a; source "${ENV_FILE}"; set +a; fi
read -p "Enter PORT [current: \${PORT:-443}]: " PORT_INPUT; PORT=\${PORT_INPUT:-\$PORT}
read -p "Enter your PCODE [current: \${PCODE}]: " PCODE_INPUT; PCODE=\${PCODE_INPUT:-\$PCODE}
read -p "Enter your KEY [current: \${KEY}]: " KEY_INPUT; KEY=\${KEY_INPUT:-\$KEY}
echo "Creating/updating .env file..."; { echo "PORT=\$PORT"; echo "PCODE=\$PCODE"; echo "KEY=\$KEY"; } > "${ENV_FILE}"
echo "✅ .env file updated. Please run 'restart-wa' to apply the changes."
EOG
chmod +x /usr/local/bin/config-wa

# stop-wa
cat << EOG > /usr/local/bin/stop-wa
#!/bin/bash
echo "🛑 Stopping the WhatsApp service..."; pkill -f "${EXECUTABLE_NAME}" || true; echo "Service stopped. The cron job will restart it within a minute."
EOG
chmod +x /usr/local/bin/stop-wa

# restart-wa
cat << EOG > /usr/local/bin/restart-wa
#!/bin/bash
echo "🔄 Restarting the WhatsApp service...";
pkill -f "${EXECUTABLE_NAME}" || true;
sleep 2;
echo "Service stopped. Triggering immediate restart...";
/usr/local/bin/autostart-wa
sleep 3
/usr/local/bin/status-wa
EOG
chmod +x /usr/local/bin/restart-wa

# update-wa
cat << EOG > /usr/local/bin/update-wa
#!/bin/bash
set -e
echo "--- Updating WhatsApp Service Binary ---"; pkill -f "${EXECUTABLE_NAME}" || true; sleep 2
echo "Downloading latest binary..."; cd "${BASE_DIR}"
# Use -sS for silent curl and -q for quiet unzip
curl -sSL "${DOWNLOAD_URL}" -o linux.zip
unzip -oq linux.zip
rm linux.zip
chmod +x "${EXECUTABLE_NAME}"
echo "✅ Update complete. Triggering immediate restart...";
/usr/local/bin/autostart-wa
EOG
chmod +x /usr/local/bin/update-wa

# status-wa
cat << EOG > /usr/local/bin/status-wa
#!/bin/bash
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m';
echo "--- WhatsApp Service Status ---"
if pgrep -f "${EXECUTABLE_NAME}" > /dev/null; then
    echo -e "\${GREEN}✅ Service is RUNNING.\${NC}"
else
    echo -e "\${RED}❌ Service is STOPPED.\${NC}"
fi
echo -e "To see detailed logs, run: \${YELLOW}tail -f ${SERVICE_LOG_FILE}\${NC}"
EOG
chmod +x /usr/local/bin/status-wa

echo -e "${GREEN}✅ All management commands created successfully.${NC}"

# --- Main Entrypoint Logic ---
echo -e "${YELLOW}📦 Preparing environment...${NC}"
# Download binary only if it doesn't exist in the volume
if [ ! -f "$EXECUTABLE_PATH" ]; then
  echo "Downloading binary for the first time..."
  cd "$BASE_DIR"
  # Use -sS for silent curl and -q for quiet unzip
  curl -sSL "$DOWNLOAD_URL" -o linux.zip
  unzip -oq linux.zip
  rm linux.zip
  chmod +x "$EXECUTABLE_NAME"
  echo -e "${GREEN}✅ Binary downloaded successfully.${NC}"
fi

echo -e "\n${CYAN}--------------------------------------------------------${NC}"
echo -e "${RED}🔴 ACTION REQUIRED: Environment is ready for setup.${NC}"
echo -e "${CYAN}--------------------------------------------------------${NC}"
echo "The container is now in standby mode."
echo ""
echo -e "   1. Open the console for this container."
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
