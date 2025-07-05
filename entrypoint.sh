#!/bin/bash
set -e

# --- Display Build Information on Every Start ---
echo ""
echo "--------------------------------------------------------"
echo "🚀 Starting WhatsApp Server Container"
echo "   Version:    ${VERSION:-unknown}"
echo "   Build Date: ${BUILD_DATE:-not specified}"
echo "--------------------------------------------------------"
echo ""

# --- Environment and File Definitions ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
EXECUTABLE_NAME="titansys-whatsapp-linux"
EXECUTABLE_PATH="${BASE_DIR}/${EXECUTABLE_NAME}"
DOWNLOAD_URL="https://raw.anycdn.link/wa/linux.zip"

# --- Always-on Services and Commands ---
echo "🕒 Starting cron daemon..."
service cron start
AUTOSTART_SCRIPT_PATH="/usr/local/bin/autostart-wa"
cat << EOG_AUTO > "\$AUTOSTART_SCRIPT_PATH"
#!/bin/bash
exec >> ${BASE_DIR}/cron.log 2>&1
echo "---"
echo "Cron job ran at: \$(date)"
if [ ! -f ${ENV_FILE} ]; then
  echo "Info: .env file not found. Service is not configured to run yet."
  exit 0
fi
set -a; source ${ENV_FILE}; set +a
if ! /usr/bin/pgrep -f "${EXECUTABLE_NAME}" > /dev/null; then
  echo "Service not running. Attempting to start..."
  cd "${BASE_DIR}" && ./"${EXECUTABLE_NAME}" --pcode="\$PCODE" --key="\$KEY" --host="0.0.0.0" --port="\$PORT" &
  echo "Start command issued."
else
  echo "Service is already running."
fi
EOG_AUTO
chmod +x "\$AUTOSTART_SCRIPT_PATH"
(crontab -l 2>/dev/null | grep -v autostart-wa ; echo "* * * * * \${AUTOSTART_SCRIPT_PATH}" ; echo "@reboot \${AUTOSTART_SCRIPT_PATH}") | crontab -
echo "✅ Cron job for auto-restart is active."

# --- Management Commands Creation ---
# (install-wa, config-wa, stop-wa, restart-wa, update-wa are created here)
# ... (El resto de la creación de comandos sigue igual)

# --- Main Entrypoint Logic ---
echo "📦 Preparing environment..."
if [ ! -f "$EXECUTABLE_PATH" ]; then
  echo "Downloading binary for the first time..."
  cd "$BASE_DIR" && curl -fsSL "$DOWNLOAD_URL" -o linux.zip && unzip -o linux.zip && rm linux.zip && chmod +x "$EXECUTABLE_NAME"
fi

echo "--------------------------------------------------------"
echo "🔴 ACTION REQUIRED: Environment is ready for setup."
echo "--------------------------------------------------------"
echo "The container is now in standby mode. The cron watchdog is active."
echo ""
echo "   1. Open the console for this container."
echo "   2. Run the command: install-wa"
echo ""
echo "Available Commands:"
echo "   - install-wa, config-wa, update-wa, restart-wa, stop-wa"
echo "--------------------------------------------------------"

exec sleep infinity
