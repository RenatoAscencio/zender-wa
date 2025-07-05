#!/bin/bash
set -e

# --- Definiciones de Colores ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin Color

# --- Mostrar Información de Build al Iniciar ---
echo -e "\n${CYAN}--------------------------------------------------------${NC}"
echo -e "${CYAN}? Iniciando Contenedor del Servidor WhatsApp${NC}"
echo -e "${CYAN}   Versión:    ${VERSION:-unknown}${NC}"
echo -e "${CYAN}   Fecha Build: ${BUILD_DATE:-not specified}${NC}"
echo -e "${CYAN}   Autor:      @RenatoAscencio${NC}"
echo -e "${CYAN}   Repositorio: https://github.com/RenatoAscencio/zender-wa${NC}"
echo -e "${CYAN}--------------------------------------------------------${NC}\n"

# --- Definiciones de Entorno y Archivos ---
BASE_DIR="/data/whatsapp-server"
ENV_FILE="${BASE_DIR}/.env"
PID_FILE="${BASE_DIR}/service.pid" # Archivo para guardar el Process ID
SERVICE_LOG_FILE="${BASE_DIR}/service.log"
CRON_LOG_FILE="${BASE_DIR}/cron.log"
EXECUTABLE_NAME="titansys-whatsapp-linux"
EXECUTABLE_PATH="${BASE_DIR}/${EXECUTABLE_NAME}"
# URL de descarga por defecto, puede ser sobreescrita por una variable de entorno
DOWNLOAD_URL="${DOWNLOAD_URL_OVERRIDE:-https://raw.anycdn.link/wa/linux.zip}"

# --- Limpiar Logs en Cada Inicio ---
echo -e "${YELLOW}? Limpiando archivos de log anteriores...${NC}"
rm -f "${SERVICE_LOG_FILE}" "${CRON_LOG_FILE}" || true

# --- Creación de Comandos de Gestión ---
echo -e "${YELLOW}? Creando comandos de gestión...${NC}"

# autostart-wa (Script de vigilancia de cron, ahora usa PID)
AUTOSTART_SCRIPT_PATH="/usr/local/bin/autostart-wa"
cat << 'EOG_AUTO' > "${AUTOSTART_SCRIPT_PATH}"
#!/bin/bash
# Redirigir toda la salida a un archivo de log
exec >> ${CRON_LOG_FILE} 2>&1
echo "---"
echo "Cron job ejecutado en: $(date)"

# Verificar si el servicio ya está corriendo usando el archivo PID
if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}")" > /dev/null 2>&1; then
  echo "Servicio ya está en ejecución con PID $(cat "${PID_FILE}")."
  exit 0
fi

# Verificar si el servicio está configurado
if [ ! -f ${ENV_FILE} ]; then
  echo "Info: Archivo .env no encontrado. El servicio aún no está configurado para ejecutarse."
  exit 0
fi

# Si el archivo PID quedó obsoleto, eliminarlo
rm -f "${PID_FILE}"

echo "Servicio no está en ejecución. Intentando iniciar..."
set -a; source ${ENV_FILE}; set +a
cd "${BASE_DIR}"
# Iniciar el proceso en segundo plano con nohup y capturar su PID
nohup ./${EXECUTABLE_NAME} --pcode="$PCODE" --key="$KEY" --host="0.0.0.0" --port="$PORT" >> "${SERVICE_LOG_FILE}" 2>&1 &
PID=$!
# Guardar el PID en el archivo
echo "${PID}" > "${PID_FILE}"
echo "Comando de inicio emitido. Servicio corriendo con PID ${PID}."
EOG_AUTO

# install-wa (Comando de configuración inicial)
cat << 'EOG' > /usr/local/bin/install-wa
#!/bin/bash
set -e
echo "--- Instalación Inicial del Servicio WhatsApp ---"
# Lógica para crear .env: desde variables de entorno o interactivamente
if [ -n "$PCODE" ] && [ -n "$KEY" ]; then
    echo "? Variables de entorno encontradas. Creando archivo .env automáticamente..."
    {
        echo "PORT=${PORT:-443}"
        echo "PCODE=$PCODE"
        echo "KEY=$KEY"
    } > "${ENV_FILE}"
elif [ ! -f "${ENV_FILE}" ]; then
    echo "?? No se encontró archivo .env o variables de entorno. Iniciando configuración interactiva..."
    /usr/local/bin/config-wa
fi
# Configurar e iniciar cron
echo "? Configurando e iniciando tarea de cron para reinicio automático..."
service cron start
(crontab -l 2>/dev/null | grep -v autostart-wa ; echo "* * * * * ${AUTOSTART_SCRIPT_PATH}" ; echo "@reboot ${AUTOSTART_SCRIPT_PATH}") | crontab -
echo "? Tarea de cron configurada."
# Disparar el primer inicio
echo "? Disparando inicio del servicio..."
/usr/local/bin/autostart-wa
sleep 3
/usr/local/bin/status-wa
EOG

# config-wa (Editor interactivo de .env)
cat << 'EOG' > /usr/local/bin/config-wa
#!/bin/bash
set -e
echo "--- Configuración Interactiva de .env ---"
if [ -f "${ENV_FILE}" ]; then set -a; source "${ENV_FILE}"; set +a; fi
read -p "Ingresa el PUERTO [actual: ${PORT:-443}]: " PORT_INPUT; PORT=${PORT_INPUT:-$PORT}
read -p "Ingresa tu PCODE [actual: ${PCODE}]: " PCODE_INPUT; PCODE=${PCODE_INPUT:-$PCODE}
read -p "Ingresa tu KEY [actual: ${KEY}]: " KEY_INPUT; KEY=${KEY_INPUT:-$KEY}
echo "Creando/actualizando archivo .env..."; { echo "PORT=$PORT"; echo "PCODE=$PCODE"; echo "KEY=$KEY"; } > "${ENV_FILE}"
echo "? Archivo .env actualizado. Por favor, ejecuta 'restart-wa' para aplicar los cambios."
EOG

# stop-wa (Ahora usa PID para detener el servicio)
cat << 'EOG' > /usr/local/bin/stop-wa
#!/bin/bash
echo -e "? Deteniendo el servicio de WhatsApp..."
if [ ! -f "${PID_FILE}" ]; then
    echo "Archivo PID no encontrado. ¿Está el servicio en ejecución? Intentando detener por nombre como alternativa."
    pkill -f "${EXECUTABLE_NAME}" || true
else
    PID=$(cat "${PID_FILE}")
    if ps -p $PID > /dev/null; then
        echo "Deteniendo proceso con PID ${PID}..."
        kill "${PID}"
        # Esperar a que el proceso termine
        while kill -0 "${PID}" > /dev/null 2>&1; do
            echo -n "."
            sleep 1
        done
        echo -e "\nProceso detenido."
    else
        echo "El proceso con PID ${PID} no existe. Limpiando archivo PID."
    fi
    rm -f "${PID_FILE}"
fi
echo "Servicio detenido. La tarea de cron lo reiniciará en un minuto."
EOG

# restart-wa (Utiliza los nuevos stop y autostart)
cat << 'EOG' > /usr/local/bin/restart-wa
#!/bin/bash
echo "? Reiniciando el servicio de WhatsApp...";
/usr/local/bin/stop-wa
sleep 2;
echo "Disparando reinicio inmediato...";
/usr/local/bin/autostart-wa
sleep 1
/usr/local/bin/status-wa
EOG

# update-wa (Utiliza el nuevo stop-wa)
cat << 'EOG' > /usr/local/bin/update-wa
#!/bin/bash
set -e
echo "--- Actualizando Binario del Servicio WhatsApp ---"
/usr/local/bin/stop-wa
echo "Descargando el último binario desde ${DOWNLOAD_URL}..."
cd "${BASE_DIR}"
curl -fsSL "${DOWNLOAD_URL}" -o linux.zip && unzip -oq linux.zip && rm linux.zip && chmod +x "${EXECUTABLE_NAME}"
echo "? Actualización completa. Disparando reinicio inmediato...";
/usr/local/bin/autostart-wa
EOG

# status-wa (Ahora usa PID para verificar el estado)
cat << 'EOG' > /usr/local/bin/status-wa
#!/bin/bash
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m';
echo "--- Estado del Servicio WhatsApp ---"
if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}")" > /dev/null 2>&1; then
    echo -e "${GREEN}? El servicio está CORRIENDO${NC} con PID $(cat "${PID_FILE}")."
else
    echo -e "${RED}? El servicio está DETENIDO.${NC}"
fi
echo -e "Para ver los logs detallados, ejecuta: ${YELLOW}tail -f ${SERVICE_LOG_FILE}${NC}"
EOG

# Hacer todos los scripts ejecutables
chmod +x /usr/local/bin/install-wa /usr/local/bin/stop-wa /usr/local/bin/restart-wa /usr/local/bin/update-wa /usr/local/bin/config-wa /usr/local/bin/status-wa /usr/local/bin/autostart-wa

echo -e "${GREEN}? Todos los comandos de gestión fueron creados exitosamente.${NC}"

# --- Lógica Principal del Entrypoint ---
# Esta parte solo prepara el entorno y luego espera.

echo -e "${YELLOW}? Preparando el entorno...${NC}"
# Descargar el binario solo si no existe en el volumen
if [ ! -f "${EXECUTABLE_PATH}" ]; then
  echo "Descargando binario por primera vez desde ${DOWNLOAD_URL}..."
  cd "${BASE_DIR}" && curl -sSL "${DOWNLOAD_URL}" -o linux.zip && unzip -oq linux.zip && rm linux.zip && chmod +x "${EXECUTABLE_NAME}"
fi

echo -e "\n${CYAN}--------------------------------------------------------${NC}"
echo -e "${RED}? ACCIÓN REQUERIDA: El entorno está listo para la configuración.${NC}"
echo -e "${CYAN}--------------------------------------------------------${NC}"
echo "El contenedor está ahora en modo de espera."
echo ""
echo -e "   1. Abre una consola para este contenedor."
echo -e "   2. Ejecuta el comando: ${GREEN}install-wa${NC}"
echo ""
echo -e "${CYAN}Comandos Disponibles:${NC}"
echo -e "   - ${GREEN}install-wa${NC} : Realiza la configuración inicial."
echo -e "   - ${GREEN}config-wa${NC}  : Edita las variables de .env interactivamente."
echo -e "   - ${GREEN}update-wa${NC}  : Descarga la última versión del binario."
echo -e "   - ${GREEN}restart-wa${NC} : Reinicia el servicio."
echo -e "   - ${GREEN}stop-wa${NC}    : Detiene el servicio."
echo -e "   - ${GREEN}status-wa${NC}  : Verifica el estado actual del servicio."
echo -e "${CYAN}--------------------------------------------------------${NC}"

# Mantener el contenedor vivo indefinidamente
exec sleep infinity
