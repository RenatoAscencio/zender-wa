#!/bin/bash
set -e

# --- Environment and File Definitions ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
EXECUTABLE_NAME="titansys-whatsapp-linux"
EXECUTABLE_PATH="${BASE_DIR}/${EXECUTABLE_NAME}"
DOWNLOAD_URL="https://raw.anycdn.link/wa/linux.zip"

# --- Management Commands Creation ---
# These commands are always created so they are available in the console.

# install-wa (The main setup and first-run command)
cat << EOG > /usr/local/bin/install-wa
#!/bin/bash
set -e
echo "--- WhatsApp Service Initial Installation ---"

# Logic to create .env: either from environment variables or interactively
if [ -n "\$PCODE" ] && [ -n "\$KEY" ]; then
    echo "✅ Environment variables found. Creating .env file automatically..."
    {
        echo "PORT=\${PORT:-443}"
        echo "PCODE=\$PCODE"
        echo "KEY=\$KEY"
    } > "${ENV_FILE}"
else
    if [ ! -f "${ENV_FILE}" ]; then
        echo "⚠️ No .env file or environment variables found. Starting interactive setup..."
        config-wa
    else
        echo "✅ Existing .env file found."
    fi
fi

# Load variables from the .env file
set -a; source "${ENV_FILE}"; set +a

# Configure cron job
echo "🕒 Configuring cron job for auto-restart..."
# Start the cron daemon in the background
service cron start
AUTOSTART_SCRIPT_PATH="/usr/local/bin/autostart-wa"
# Create a more robust autostart script with logging
cat << EOG_AUTO > "\$AUTOSTART_SCRIPT_PATH"
#!/bin/bash
# Log execution to a file for debugging
exec >> ${BASE_DIR}/cron.log 2>&1
echo "---"
echo "Cron job ran at: \$(date)"

# Source the environment file to get variables
if [ -f ${ENV_FILE} ]; then
  set -a; source ${ENV_FILE}; set +a
else
  echo "Error: .env file not found. Cannot start service."
  exit 1
fi

# Check if service is running using absolute path for pgrep
if ! /usr/bin/pgrep -f "${EXECUTABLE_NAME}" > /dev/null; then
  echo "Service not running. Attempting to start..."
  cd "${BASE_DIR}" && ./"${EXECUTABLE_NAME}" --pcode="\$PCODE" --key="\$KEY" --host="0.0.0.0" --port="\$PORT" &
  echo "Start command issued."
else
  echo "Service is already running."
fi
EOG_AUTO
chmod +x "\$AUTOSTART_SCRIPT_PATH"
# Clean up old cron jobs and add the new ones
(crontab -l 2>/dev/null | grep -v autostart-wa ; echo "* * * * * \${AUTOSTART_SCRIPT_PATH}" ; echo "@reboot \${AUTOSTART_SCRIPT_PATH}") | crontab -
echo "✅ Cron job configured."

# Start the service
echo "🚀 Starting WhatsApp service..."
cd "${BASE_DIR}" && ./"${EXECUTABLE_NAME}" --pcode="\$PCODE" --key="\$KEY" --host="0.0.0.0" --port="\$PORT" &
echo "✅ Service started in the background. Use 'docker logs' or check the panel for output."
EOG

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

# stop-wa
cat << EOG > /usr/local/bin/stop-wa
#!/bin/bash
echo "🛑 Stopping the WhatsApp service..."; pkill -f "${EXECUTABLE_NAME}" || true; echo "Service stopped. The cron job will restart it within a minute."
EOG

# restart-wa
cat << EOG > /usr/local/bin/restart-wa
#!/bin/bash
echo "🔄 Restarting the WhatsApp service..."; pkill -f "${EXECUTABLE_NAME}" || true; sleep 2
echo "Service stopped. The cron job will restart it automatically."
EOG

# update-wa
cat << EOG > /usr/local/bin/update-wa
#!/bin/bash
set -e
echo "--- Updating WhatsApp Service Binary ---"; pkill -f "${EXECUTABLE_NAME}" || true; sleep 2
echo "Downloading latest binary..."; cd "${BASE_DIR}"
curl -fsSL "${DOWNLOAD_URL}" -o linux.zip && unzip -o linux.zip && rm linux.zip && chmod +x "${EXECUTABLE_NAME}"
echo "✅ Update complete. Service will be restarted by cron."
EOG

chmod +x /usr/local/bin/install-wa /usr/local/bin/stop-wa /usr/local/bin/restart-wa /usr/local/bin/update-wa /usr/local/bin/config-wa

# --- Main Entrypoint Logic ---
# This part only prepares the environment and then waits.

echo "📦 Preparing environment..."
# Download binary only if it doesn't exist in the volume
if [ ! -f "$EXECUTABLE_PATH" ]; then
  echo "Downloading binary for the first time..."
  cd "$BASE_DIR" && curl -fsSL "$DOWNLOAD_URL" -o linux.zip && unzip -o linux.zip && rm linux.zip && chmod +x "$EXECUTABLE_NAME"
fi

echo "--------------------------------------------------------"
echo "🔴 ACTION REQUIRED: Environment is ready for setup."
echo "--------------------------------------------------------"
echo "The container is now in standby mode."
echo ""
echo "   1. Open the console for this container."
echo "   2. Run the command: install-wa"
echo ""
echo "Available Commands:"
echo "   - install-wa : Performs the first-time setup or starts the service."
echo "   - config-wa  : Edits the .env variables interactively."
echo "   - update-wa  : Downloads the latest version of the binary."
echo "   - restart-wa : Restarts the service."
echo "   - stop-wa    : Stops the service."
echo "--------------------------------------------------------"

# Keep the container alive indefinitely
exec sleep infinity
