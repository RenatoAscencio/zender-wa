#!/bin/bash
# Script para registrar deployments automáticamente

set -e

DEPLOYMENT_FILE="DEPLOYMENT_HISTORY.json"
TEMP_FILE="/tmp/deployment_temp.json"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_deployment() {
    local version="$1"
    local status="$2"
    local duration="$3"
    local type="$4"
    local description="$5"
    local changes="$6"

    local deploy_id="deploy-$(date +%s)"
    local deploy_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo -e "${BLUE}📝 Registrando deployment...${NC}"

    # Crear entrada del nuevo deployment
    local new_deployment=$(cat <<EOF
{
  "id": "$deploy_id",
  "date": "$deploy_date",
  "version": "$version",
  "status": "$status",
  "duration": "$duration",
  "type": "$type",
  "description": "$description",
  "changes": $changes
}
EOF
)

    # Si el archivo no existe, crearlo
    if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
        cat > "$DEPLOYMENT_FILE" <<EOF
{
  "deployments": [],
  "statistics": {
    "total_deployments": 0,
    "successful": 0,
    "failed": 0,
    "average_duration": "0 seconds",
    "last_deployment": "$deploy_date"
  }
}
EOF
    fi

    # Leer el archivo actual y agregar el nuevo deployment
    python3 -c "
import json
import sys

# Leer archivo existente
with open('$DEPLOYMENT_FILE', 'r') as f:
    data = json.load(f)

# Agregar nuevo deployment al inicio
new_deployment = $new_deployment
data['deployments'].insert(0, new_deployment)

# Actualizar estadísticas
data['statistics']['total_deployments'] = len(data['deployments'])
data['statistics']['last_deployment'] = '$deploy_date'

if '$status' == 'success':
    data['statistics']['successful'] = data['statistics'].get('successful', 0) + 1
else:
    data['statistics']['failed'] = data['statistics'].get('failed', 0) + 1

# Mantener solo los últimos 20 deployments
if len(data['deployments']) > 20:
    data['deployments'] = data['deployments'][:20]

# Escribir archivo actualizado
with open('$DEPLOYMENT_FILE', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
"

    if [[ "$status" == "success" ]]; then
        echo -e "${GREEN}✅ Deployment registrado exitosamente${NC}"
        echo -e "   📦 Versión: $version"
        echo -e "   ⏱️  Duración: $duration"
        echo -e "   🏷️  Tipo: $type"
    else
        echo -e "${RED}❌ Deployment fallido registrado${NC}"
        echo -e "   📦 Versión: $version"
        echo -e "   ⏱️  Duración: $duration"
        echo -e "   🏷️  Tipo: $type"
    fi
}

show_history() {
    echo -e "${BLUE}📋 Historial de Deployments${NC}"
    echo "================================"

    if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
        echo "No hay historial de deployments disponible."
        return
    fi

    python3 -c "
import json
from datetime import datetime

with open('$DEPLOYMENT_FILE', 'r') as f:
    data = json.load(f)

print('\\n📊 Estadísticas:')
stats = data['statistics']
print(f'   Total: {stats[\"total_deployments\"]}')
print(f'   Exitosos: {stats.get(\"successful\", 0)}')
print(f'   Fallidos: {stats.get(\"failed\", 0)}')
print(f'   Último: {stats[\"last_deployment\"]}')

print('\\n📝 Deployments recientes:')
for i, deploy in enumerate(data['deployments'][:10]):
    status_icon = '✅' if deploy['status'] == 'success' else '❌'
    type_icon = {'release': '🚀', 'feature': '✨', 'security': '🔒', 'config': '⚙️', 'hotfix': '🔥'}.get(deploy['type'], '📦')

    print(f'{status_icon} {type_icon} {deploy[\"version\"]} - {deploy[\"description\"]}')
    print(f'     Duración: {deploy[\"duration\"]} | Fecha: {deploy[\"date\"]}')
    if i < len(data['deployments']) - 1:
        print()
"
}

generate_report() {
    local output_file="deployment-report.md"

    echo -e "${BLUE}📄 Generando reporte de deployments...${NC}"

    python3 -c "
import json
from datetime import datetime

with open('$DEPLOYMENT_FILE', 'r') as f:
    data = json.load(f)

report = '''# 📋 Deployment Report - Zender WhatsApp Server

## 📊 Estadísticas Generales

| Métrica | Valor |
|---------|-------|
| Total Deployments | {total} |
| Deployments Exitosos | {successful} |
| Deployments Fallidos | {failed} |
| Tasa de Éxito | {success_rate}% |
| Último Deployment | {last_date} |

## 📝 Historial de Deployments

'''.format(
    total=data['statistics']['total_deployments'],
    successful=data['statistics'].get('successful', 0),
    failed=data['statistics'].get('failed', 0),
    success_rate=round((data['statistics'].get('successful', 0) / max(1, data['statistics']['total_deployments'])) * 100, 1),
    last_date=data['statistics']['last_deployment']
)

for deploy in data['deployments']:
    status_icon = '✅' if deploy['status'] == 'success' else '❌'
    type_icon = {'release': '🚀', 'feature': '✨', 'security': '🔒', 'config': '⚙️', 'hotfix': '🔥'}.get(deploy['type'], '📦')

    report += f'''
### {status_icon} {type_icon} {deploy['version']} - {deploy['description']}

**Fecha:** {deploy['date']}
**Duración:** {deploy['duration']}
**Tipo:** {deploy['type']}

**Cambios:**
'''
    for change in deploy['changes']:
        report += f'- {change}\\n'

    report += '\\n---\\n'

with open('$output_file', 'w') as f:
    f.write(report)
"

    echo -e "${GREEN}✅ Reporte generado: $output_file${NC}"
}

# Función principal
case "$1" in
    "log")
        if [[ $# -lt 6 ]]; then
            echo "Uso: $0 log <version> <status> <duration> <type> <description> <changes_json>"
            echo "Ejemplo: $0 log 'v2.1.4' 'success' '35 seconds' 'feature' 'Nueva característica' '[\"Feature 1\", \"Fix 2\"]'"
            exit 1
        fi
        log_deployment "$2" "$3" "$4" "$5" "$6" "$7"
        ;;
    "history"|"show")
        show_history
        ;;
    "report")
        generate_report
        ;;
    *)
        echo "Uso: $0 {log|history|report}"
        echo ""
        echo "Comandos:"
        echo "  log     - Registrar un nuevo deployment"
        echo "  history - Mostrar historial de deployments"
        echo "  report  - Generar reporte markdown"
        exit 1
        ;;
esac