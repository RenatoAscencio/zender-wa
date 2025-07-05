#!/bin/bash
set -e

# --- Definiciones de color ---
GREEN='\033[0;32m'    # Éxito
YELLOW='\033[1;33m'   # Aviso
RED='\033[0;31m'      # Error
CYAN='\033[0;36m'     # Info
NC='\033[0m'          # Sin color

# --- Información de build ---
echo -e "\n${CYAN}--------------------------------------------------------${NC}"
echo -e "${CYAN}🚀 Starting WhatsApp Server Container${NC}"
echo -e "${CYAN}   Version:    ${VERSION:-unknown}${NC}"
echo -e "${CYAN}   Build Date: ${BUILD_DATE:-not specified}${NC}"
echo -e "${CYAN}   Author:     @RenatoAscencio${NC}"
echo -e "${CYAN}   Repository: https://github.com/RenatoAscencio/zender-wa${NC}"
echo -e "${CYAN}--------------------------------------------------------${NC}\n"

# --- Variables de entorno y rutas ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
EXECUTABLE_NAME="titansys-whatsapp-linux"
DOWNLOAD_URL="https://raw.anycdn.link/wa/linux.zip"
BIN_DIR="/usr/local/bin"

# --- Asegurar directorios y permisos ---
mkdir -p "${BASE_DIR}" "${BIN_DIR}"

# --- Limpiar logs ---
echo -e "${YELLOW}🧹 Clearing previous log files...${NC}"
rm -f "${SERVICE_LOG_FILE}" "${CRON_LOG_FILE}" || true

# --- Generar scripts de gestión ---
echo -e "${YELLOW}🔧 Creating management commands...${NC}"

# 1) autostart-wa
AUTOSTART_SCRIPT_PATH="${BIN_DIR}/autostart-wa"
cat << 'EOG_AUTO' > "${AUTOSTART_SCRIPT_PATH}"
#!/bin/bash
exec >> /data/whatsapp-server/cron.log 2>&1
echo "---"
echo "Cron job ran at: $(date)"

if [ ! -f /data/whatsapp-server/.env ]; then
  echo "Info: .env file not found. Service is not configured to run yet."
  exit 0
fi

set -a; source /data/whatsapp-server/.env; set +a

if ! pgrep -f "titansys-whatsapp-linux" >/dev/null; then
  echo "Service not running. Attempting to start..."
  cd /data/whatsapp-server && ./titansys-whatsapp-linux --pcode="$PCODE" --key="$KEY" --host="0.0.0.0" --port="$PORT" >> /data/whatsapp-server/service.log 2>&1 &
  echo "Start command issued."
else
  echo "Service is already running."
fi
EOG_AUTO
chmod +x "${AUTOSTART_SCRIPT_PATH}"

# 2) install-wa
cat << 'EOG_INSTALL' > "${BIN_DIR}/install-wa"
#!/bin/bash
set -e
echo "--- WhatsApp Service Initial Installation ---"

if [ -n "$PCODE" ] && [ -n "$KEY" ]; then
  echo "✅ Environment variables found. Creating .env file automatically..."
  {
    echo "PORT=${PORT:-443}"
    echo "PCODE=$PCODE"
    echo "KEY=$KEY"
  } > /data/whatsapp-server/.env
elif [ ! -f /data/whatsapp-server/.env ]; then
  echo "⚠️ No .env file or environment variables found. Starting interactive setup..."
  /usr/local/bin/config-wa
fi

echo "🕒 Configuring cron for auto-restart..."
service cron start
(crontab -l 2>/dev/null | grep -v autostart-wa; echo "* * * * * /usr/local/bin/autostart-wa"; echo "@reboot /usr/local/bin/autostart-wa") | crontab -

echo "🚀 Triggering service start..."
/usr/local/bin/autostart-wa
sleep 3
/usr/local/bin/status-wa
EOG_INSTALL
chmod +x "${BIN_DIR}/install-wa"

# 3) config-wa
cat << 'EOG_CONFIG' > "${BIN_DIR}/config-wa"
#!/bin/bash
set -e
echo "--- Interactive .env Configuration ---"

if [ -f /data/whatsapp-server/.env ]; then
  set -a; source /data/whatsapp-server/.env; set +a
fi

read -p "Enter PORT [${PORT:-443}]: " PORT_INPUT; PORT=${PORT_INPUT:-$PORT}
read -p "Enter your PCODE [${PCODE}]: " PCODE_INPUT; PCODE=${PCODE_INPUT:-$PCODE}
read -p "Enter your KEY [${KEY}]: " KEY_INPUT; KEY=${KEY_INPUT:-$KEY}

echo "Creating/updating .env file..."
cat > /data/whatsapp-server/.env << 'EOF_CONFIG'
PORT=$PORT
PCODE=$PCODE
KEY=$KEY
EOF_CONFIG

echo "✅ .env updated. Please run 'restart-wa' to apply changes."
EOG_CONFIG
chmod +x "${BIN_DIR}/config-wa"

# 4) stop-wa
cat << 'EOG_STOP' > "${BIN_DIR}/stop-wa"
#!/bin/bash
echo "🛑 Stopping the WhatsApp service..."
pkill -f "titansys-whatsapp-linux" || true
echo "Service stopped. Cron will restart it."
EOG_STOP
chmod +x "${BIN_DIR}/stop-wa"

# 5) restart-wa
cat << 'EOG_RESTART' > "${BIN_DIR}/restart-wa"
#!/bin/bash
echo "🔄 Restarting the WhatsApp service..."
pkill -f "titansys-whatsapp-linux" || true
sleep 2
/usr/local/bin/autostart-wa
sleep 3
/usr/local/bin/status-wa
EOG_RESTART
chmod +x "${BIN_DIR}/restart-wa"

# 6) update-wa
cat << 'EOG_UPDATE' > "${BIN_DIR}/update-wa"
#!/bin/bash
set -e
echo "--- Updating WhatsApp Service Binary ---"
pkill -f "titansys-whatsapp-linux" || true
sleep 2

echo "Downloading latest binary..."
cd /data/whatsapp-server
curl -fsSL "${DOWNLOAD_URL}" -o linux.zip
unzip -oq linux.zip && rm linux.zip
chmod +x "titansys-whatsapp-linux"

echo "✅ Update complete. Restarting..."
/usr/local/bin/autostart-wa
EOG_UPDATE
chmod +x "${BIN_DIR}/update-wa"

# 7) status-wa
cat << 'EOG_STATUS' > "${BIN_DIR}/status-wa"
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
echo "--- WhatsApp Service Status ---"
if pgrep -f "titansys-whatsapp-linux" >/dev/null; then
  echo -e "${GREEN}✅ Service is RUNNING.${NC}"
else
  echo -e "${RED}❌ Service is STOPPED.${NC}"
fi
echo -e "Logs: ${YELLOW}tail -f /data/whatsapp-server/service.log${NC}"
EOG_STATUS
chmod +x "${BIN_DIR}/status-wa"

echo -e "${GREEN}✅ All management commands created successfully.${NC}"

# --- Lógica principal del entrypoint ---
echo -e "${YELLOW}📦 Preparing environment...${NC}"
if [ ! -f "/data/whatsapp-server/titansys-whatsapp-linux" ]; then
  echo "Downloading binary for the first time..."
  cd /data/whatsapp-server
  curl -sSL "${DOWNLOAD_URL}" -o linux.zip
  unzip -oq linux.zip && rm linux.zip
  chmod +x "titansys-whatsapp-linux"
fi

cat << EOG_MSG

${CYAN}--------------------------------------------------------${NC}
${RED}🔴 ACTION REQUIRED:${NC} Please run ${GREEN}install-wa${NC}
${CYAN}--------------------------------------------------------${NC}

1) docker exec -it <container> bash
2) install-wa

Available commands:
  • install-wa
  • config-wa
  • update-wa
  • restart-wa
  • stop-wa
  • status-wa

EOG_MSG

exec sleep infinity
