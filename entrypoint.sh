#!/bin/bash
set -e

# --- Environment and File Definitions ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
EXECUTABLE_NAME="titansys-whatsapp-linux"
EXECUTABLE_PATH="${BASE_DIR}/${EXECUTABLE_NAME}"
DOWNLOAD_URL="https://raw.anycdn.link/wa/linux.zip"

# --- Force Command Refresh on Every Start ---
# This ensures that on every redeploy, the latest versions of the scripts are installed.
echo "🔄 Refreshing management commands..."
rm -f /usr/local/bin/install-wa \
      /usr/local/bin/config-wa \
      /usr/local/bin/stop-wa \
      /usr/local/bin/restart-wa \
      /usr/local/bin/update-wa \
      /usr/local/bin/autostart-wa

# --- Main Logic: Check for environment variables first ---

if [ -n "$PCODE" ] && [ -n "$KEY" ]; then
  # --- MODE 1: Automated Deployment (Environment variables are set) ---
  echo "✅ Environment variables for PCODE and KEY found. Configuring service..."

  # For debugging, print the received variables to the log
  echo "   - PCODE received: $PCODE"
  echo "   - KEY received:   $KEY"
  echo "   - PORT set to:    ${PORT:-443}"

  # Create/overwrite the .env file using the environment variables.
  echo "✍️  Creating/updating .env file from environment variables..."
  {
    echo "PORT=${PORT:-443}"
    echo "PCODE=$PCODE"
    echo "KEY=$KEY"
  } > "$ENV_FILE"
  echo "✅ .env file created successfully."

  # Create management commands for this mode
  cat << EOG > /usr/local/bin/stop-wa
#!/bin/bash
echo "🛑 Stopping the WhatsApp service..."; pkill -f "${EXECUTABLE_NAME}" || true; echo "Service stopped."
EOG
  cat << EOG > /usr/local/bin/restart-wa
#!/bin/bash
echo "🔄 Restarting the WhatsApp service..."; pkill -f "${EXECUTABLE_NAME}" || true; sleep 2; echo "Service stopped. The cron job will restart it automatically."
EOG
  cat << EOG > /usr/local/bin/update-wa
#!/bin/bash
set -e
echo "--- Updating WhatsApp Service Binary ---"; pkill -f "${EXECUTABLE_NAME}" || true; sleep 2
echo "Downloading latest binary..."; cd "${BASE_DIR}" && curl -fsSL "${DOWNLOAD_URL}" -o linux.zip && unzip -o linux.zip && rm linux.zip && chmod +x "${EXECUTABLE_NAME}"
echo "✅ Update complete. Service will be restarted by cron."
EOG
  chmod +x /usr/local/bin/stop-wa /usr/local/bin/restart-wa /usr/local/bin/update-wa

  # Download binary if it doesn't exist
  if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "Downloading binary for the first time..."
    cd "$BASE_DIR" && curl -fsSL "$DOWNLOAD_URL" -o linux.zip && unzip -o linux.zip && rm linux.zip && chmod +x "$EXECUTABLE_NAME"
  fi

  # Configure cron and start the service
  service cron start
  AUTOSTART_SCRIPT_PATH="/usr/local/bin/autostart-wa"
  cat << EOG > "\$AUTOSTART_SCRIPT_PATH"
#!/usr/bin/env bash
if [ -f ${ENV_FILE} ]; then set -a; source ${ENV_FILE}; set +a; fi
if ! pgrep -f "${EXECUTABLE_NAME}" > /dev/null; then
  cd "${BASE_DIR}" && ./"${EXECUTABLE_NAME}" --pcode="\$PCODE" --key="\$KEY" --host="0.0.0.0" --port="\$PORT" &
fi
EOG
  chmod +x "\$AUTOSTART_SCRIPT_PATH"
  (crontab -l 2>/dev/null | grep -v autostart-wa ; echo "* * * * * \${AUTOSTART_SCRIPT_PATH}" ; echo "@reboot \${AUTOSTART_SCRIPT_PATH}") | crontab -

  echo "🚀 Starting WhatsApp service with the synchronized configuration..."
  exec ./"${EXECUTABLE_NAME}" --pcode="\$PCODE" --key="\$KEY" --host="0.0.0.0" --port="\$PORT"

else
  # --- MODE 2: Manual Deployment (No environment variables found) ---
  echo "⚠️ Environment variables not set. Starting in manual .env setup mode."
  
  # Create all management commands for manual mode
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
  cat << EOG > /usr/local/bin/install-wa
#!/bin/bash
set -e
echo "--- WhatsApp Service Initial Installation ---"
if [ ! -f "${ENV_FILE}" ]; then echo "No .env file found. Running initial configuration..."; config-wa; fi
echo "Starting WhatsApp service..."; set -a; source "${ENV_FILE}"; set +a
cd "${BASE_DIR}" && ./"${EXECUTABLE_NAME}" --pcode="\$PCODE" --key="\$KEY" --host="0.0.0.0" --port="\$PORT" &
echo "✅ Service started in the background. Run 'restart-wa' to apply cron."
EOG
  cat << EOG > /usr/local/bin/stop-wa
#!/bin/bash
echo "🛑 Stopping the WhatsApp service..."; pkill -f "${EXECUTABLE_NAME}" || true; echo "Service stopped."
EOG
  cat << EOG > /usr/local/bin/restart-wa
#!/bin/bash
echo "🔄 Restarting the WhatsApp service..."; pkill -f "${EXECUTABLE_NAME}" || true; sleep 2
echo "Service stopped. The cron job will restart it automatically."
EOG
  cat << EOG > /usr/local/bin/update-wa
#!/bin/bash
set -e
echo "--- Updating WhatsApp Service Binary ---"; pkill -f "${EXECUTABLE_NAME}" || true; sleep 2
echo "Downloading latest binary..."; cd "${BASE_DIR}"
curl -fsSL "${DOWNLOAD_URL}" -o linux.zip && unzip -o linux.zip && rm linux.zip && chmod +x "${EXECUTABLE_NAME}"
echo "✅ Update complete. Service will be restarted by cron."
EOG
  chmod +x /usr/local/bin/install-wa /usr/local/bin/stop-wa /usr/local/bin/restart-wa /usr/local/bin/update-wa /usr/local/bin/config-wa

  # Download binary if it doesn't exist
  if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "Downloading binary..."
    cd "$BASE_DIR" && curl -fsSL "$DOWNLOAD_URL" -o linux.zip && unzip -o linux.zip && rm linux.zip && chmod +x "$EXECUTABLE_NAME"
  fi

  # Go into standby mode and show instructions for manual setup
  echo "--------------------------------------------------------"
  echo "🔴 ACTION REQUIRED: Environment is ready for manual setup."
  echo "--------------------------------------------------------"
  echo "The container is now in standby mode."
  echo ""
  echo "   1. Open the console for this container."
  echo "   2. Run the command: install-wa"
  echo ""
  echo "Available Commands:"
  echo "   - install-wa, config-wa, update-wa, restart-wa, stop-wa"
  echo "--------------------------------------------------------"
  exec sleep infinity
fi
