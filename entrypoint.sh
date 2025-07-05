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
# (Aquí van las funciones autostart-wa, install-wa, config-wa, etc.)
# ...
# Lógica principal del entrypoint anterior ...

# --- Mensaje de acción requerida con diseño mejorado ---
echo -e "\n${CYAN}┌──────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC} ${RED}🔴 ACTION REQUIRED:${NC} Please run ${GREEN}install-wa${NC} ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────────┘${NC}\n"

# --- Instrucciones de uso con recuadro ---
echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC} ${YELLOW}Usage:${NC}                                     ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  1) ${GREEN}docker exec -it <container> bash${NC}        ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  2) ${GREEN}install-wa${NC}                              ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────────┘${NC}\n"

# --- Lista de comandos disponibles ---
echo -e "${CYAN}Available commands:${NC}"
echo -e "  ${GREEN}• install-wa${NC}     - First-time setup"
echo -e "  ${GREEN}• config-wa${NC}      - Edit .env interactively"
echo -e "  ${GREEN}• update-wa${NC}      - Download latest binary"
echo -e "  ${GREEN}• restart-wa${NC}     - Restart the service"
echo -e "  ${GREEN}• stop-wa${NC}        - Stop the service"
echo -e "  ${GREEN}• status-wa${NC}      - Show service status"

exec sleep infinity
