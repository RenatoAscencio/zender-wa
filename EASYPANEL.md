# 🚀 Instalación en EasyPanel

## Método 1: Un Solo Clic (Recomendado)

[![Deploy on EasyPanel](https://easypanel.io/img/deploy-on-easypanel.svg)](https://easypanel.io/deploy?template=https://raw.githubusercontent.com/RenatoAscencio/zender-wa/main/easypanel.json)

## Método 2: Configuración Manual

### 📋 Requisitos Previos

- **EasyPanel** instalado y configurado
- **Credenciales válidas:**
  - `PCODE`: Código de compra del servidor WhatsApp
  - `KEY`: Clave API del servidor WhatsApp
- **Recursos mínimos:**
  - 256MB RAM (recomendado: 1GB)
  - 1 CPU core
  - Puerto 443 disponible

### 🔧 Configuración Paso a Paso

#### 1. Crear Nuevo Proyecto

```bash
# En EasyPanel, crear nuevo proyecto llamado "zender-wa"
```

#### 2. Agregar Servicio

**Configuración del Servicio:**

- **Nombre:** `zender-wa`
- **Imagen:** `renatoascencio/zender-wa:latest`
- **Puerto:** `443:443`
- **Restart Policy:** `unless-stopped`

#### 3. Variables de Entorno

```env
PCODE=tu_codigo_de_compra_aqui
KEY=tu_clave_api_aqui
PORT=443
```

#### 4. Volúmenes

```yaml
whatsapp_data:/data/whatsapp-server
```

#### 5. Configuración de Recursos

```yaml
Límites:
  - Memoria: 1GB
  - CPU: 1.0

Reservas:
  - Memoria: 256MB
  - CPU: 0.25
```

### 🌐 Configuración de Dominio (Opcional)

Si usas un dominio personalizado, configura las siguientes etiquetas:

```yaml
traefik.http.routers.zender-wa.rule: Host(`tu-dominio.com`)
traefik.http.routers.zender-wa.tls: true
traefik.http.routers.zender-wa.tls.certresolver: letsencrypt
```

## Método 3: Docker Compose

```bash
# 1. Descargar configuración
wget https://raw.githubusercontent.com/RenatoAscencio/zender-wa/main/docker-compose.easypanel.yml

# 2. Crear archivo .env
cat > .env << EOF
PCODE=tu_codigo_de_compra
KEY=tu_clave_api
PORT=443
DOMAIN=tu-dominio.com
EOF

# 3. Desplegar
docker-compose -f docker-compose.easypanel.yml up -d
```

## 📊 Monitoreo Avanzado (Opcional)

Para habilitar el stack de monitoreo completo:

```yaml
# Agregar servicio adicional en EasyPanel
Nombre: zender-wa-monitoring
Imagen: prom/prometheus:latest
Puertos:
  - 9090:9090
  - 3000:3000 (Grafana)

Variables de entorno:
  - GRAFANA_PASSWORD=admin123
```

**Servicios incluidos:**
- **Prometheus:** `http://tu-servidor:9090`
- **Grafana:** `http://tu-servidor:3000` (admin/admin123)
- **AlertManager:** Notificaciones automáticas

## 🔧 Configuración Post-Instalación

1. **Acceder al contenedor:**
   ```bash
   docker exec -it zender-wa bash
   ```

2. **Ejecutar configuración inicial:**
   ```bash
   install-wa
   ```

3. **Verificar estado:**
   ```bash
   status-wa
   ```

## 📱 Comandos de Gestión

```bash
# Ver estado del servicio
docker exec zender-wa status-wa

# Reiniciar servicio
docker exec zender-wa restart-wa

# Ver logs en tiempo real
docker logs -f zender-wa

# Actualizar binario
docker exec zender-wa update-wa

# Configuración interactiva
docker exec -it zender-wa config-wa
```

## 🔒 Consideraciones de Seguridad

- ✅ Imagen optimizada con usuario no-root
- ✅ Escaneo automático de vulnerabilidades
- ✅ Configuración SSL/TLS incluida
- ✅ Logs estructurados y rotación automática
- ✅ Healthchecks integrados

## 📈 Optimizaciones Incluidas

- **62% menor tamaño** de imagen (152MB vs 398MB)
- **56% arranque más rápido** (20s vs 45s)
- **29% menos uso de memoria** (138MB vs 195MB)
- **Arquitecturas múltiples:** AMD64, ARM64, ARMv7
- **CI/CD automatizado** con GitHub Actions

## 🆘 Resolución de Problemas

### El contenedor no inicia

1. Verificar variables de entorno:
   ```bash
   docker exec zender-wa printenv | grep -E "(PCODE|KEY)"
   ```

2. Revisar logs:
   ```bash
   docker logs zender-wa --tail 50
   ```

### Problemas de conectividad

1. Verificar puerto:
   ```bash
   docker port zender-wa
   ```

2. Probar healthcheck:
   ```bash
   docker exec zender-wa /usr/local/bin/status-wa
   ```

### Rendimiento lento

1. Verificar recursos:
   ```bash
   docker stats zender-wa
   ```

2. Aumentar límites de memoria si es necesario

## 📞 Soporte

- **GitHub Issues:** [Reportar problema](https://github.com/RenatoAscencio/zender-wa/issues)
- **Documentación:** [README completo](https://github.com/RenatoAscencio/zender-wa#readme)
- **Releases:** [Notas de versión](https://github.com/RenatoAscencio/zender-wa/releases)

---

**⚡ Optimizado para EasyPanel | v2.1.0**