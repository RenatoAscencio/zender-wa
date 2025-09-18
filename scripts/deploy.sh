#!/bin/bash
# Quick deployment script for Zender WhatsApp Server

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Configuration
DEFAULT_IMAGE="renatoascencio/zender-wa:latest"
DEFAULT_CONTAINER_NAME="zender-wa"
DEFAULT_PORT="443"

show_help() {
    cat << EOF
Zender WhatsApp Server Deployment Script

Usage: $0 [OPTIONS] COMMAND

Commands:
    deploy      Deploy the container
    start       Start existing container
    stop        Stop running container
    restart     Restart container
    logs        Show container logs
    status      Show container status
    clean       Remove container and image
    monitor     Deploy with full monitoring stack

Options:
    -p, --pcode PCODE       Purchase code (required for deploy)
    -k, --key KEY           API key (required for deploy)
    -n, --name NAME         Container name (default: $DEFAULT_CONTAINER_NAME)
    -P, --port PORT         Host port (default: $DEFAULT_PORT)
    -i, --image IMAGE       Docker image (default: $DEFAULT_IMAGE)
    -m, --monitoring        Include monitoring stack
    -h, --help              Show this help

Examples:
    $0 deploy -p "YOUR_PCODE" -k "YOUR_KEY"
    $0 deploy -p "YOUR_PCODE" -k "YOUR_KEY" -m
    $0 monitor
    $0 restart
    $0 logs -f

EOF
}

# Parse arguments
PCODE=""
KEY=""
CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
PORT="$DEFAULT_PORT"
IMAGE="$DEFAULT_IMAGE"
MONITORING=false
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--pcode)
            PCODE="$2"
            shift 2
            ;;
        -k|--key)
            KEY="$2"
            shift 2
            ;;
        -n|--name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -P|--port)
            PORT="$2"
            shift 2
            ;;
        -i|--image)
            IMAGE="$2"
            shift 2
            ;;
        -m|--monitoring)
            MONITORING=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        deploy|start|stop|restart|logs|status|clean|monitor)
            COMMAND="$1"
            shift
            break
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check Docker
if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

# Deploy function
deploy_container() {
    if [[ -z "$PCODE" ]] || [[ -z "$KEY" ]]; then
        log_error "PCODE and KEY are required for deployment"
        exit 1
    fi

    log_info "Deploying Zender WhatsApp Server..."

    # Stop existing container if running
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        log_warn "Stopping existing container..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi

    # Pull latest image
    log_info "Pulling image: $IMAGE"
    docker pull "$IMAGE"

    # Run container
    log_info "Starting container: $CONTAINER_NAME"
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$PORT:443" \
        -e PCODE="$PCODE" \
        -e KEY="$KEY" \
        -v whatsapp_data:/data/whatsapp-server \
        --restart unless-stopped \
        --memory=1g \
        --cpus=1.0 \
        "$IMAGE"

    # Wait for container to start
    log_info "Waiting for container to start..."
    sleep 10

    # Check status
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        log_success "Container deployed successfully!"
        log_info "Container name: $CONTAINER_NAME"
        log_info "Access URL: https://localhost:$PORT"

        # Show management commands
        log_info "Management commands:"
        echo "  docker exec -it $CONTAINER_NAME status-wa"
        echo "  docker exec -it $CONTAINER_NAME restart-wa"
        echo "  docker logs -f $CONTAINER_NAME"
    else
        log_error "Container failed to start"
        docker logs "$CONTAINER_NAME" || true
        exit 1
    fi
}

# Monitor deployment
deploy_monitoring() {
    log_info "Deploying full monitoring stack..."

    if [[ ! -f "docker-compose.monitoring.yml" ]]; then
        log_error "docker-compose.monitoring.yml not found"
        exit 1
    fi

    if [[ -z "$PCODE" ]] || [[ -z "$KEY" ]]; then
        log_error "PCODE and KEY are required for monitoring deployment"
        exit 1
    fi

    # Create .env file for compose
    cat > .env << EOF
PCODE=$PCODE
KEY=$KEY
PORT=$PORT
GRAFANA_PASSWORD=admin123
EOF

    # Deploy with docker-compose
    docker-compose -f docker-compose.monitoring.yml up -d

    log_success "Monitoring stack deployed!"
    log_info "Services available at:"
    echo "  Grafana: http://localhost:3000 (admin/admin123)"
    echo "  Prometheus: http://localhost:9091"
    echo "  AlertManager: http://localhost:9093"
    echo "  WhatsApp Service: https://localhost:$PORT"
}

# Main command handler
case "${COMMAND:-}" in
    deploy)
        if [[ "$MONITORING" == true ]]; then
            deploy_monitoring
        else
            deploy_container
        fi
        ;;
    start)
        log_info "Starting container: $CONTAINER_NAME"
        docker start "$CONTAINER_NAME"
        log_success "Container started"
        ;;
    stop)
        log_info "Stopping container: $CONTAINER_NAME"
        docker stop "$CONTAINER_NAME"
        log_success "Container stopped"
        ;;
    restart)
        log_info "Restarting container: $CONTAINER_NAME"
        docker restart "$CONTAINER_NAME"
        log_success "Container restarted"
        ;;
    logs)
        docker logs "$@" "$CONTAINER_NAME"
        ;;
    status)
        if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
            log_success "Container $CONTAINER_NAME is running"
            docker exec "$CONTAINER_NAME" status-wa 2>/dev/null || true
        else
            log_warn "Container $CONTAINER_NAME is not running"
        fi
        ;;
    clean)
        log_warn "Removing container and cleaning up..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rmi "$IMAGE" >/dev/null 2>&1 || true
        log_success "Cleanup completed"
        ;;
    monitor)
        if [[ -z "$PCODE" ]] || [[ -z "$KEY" ]]; then
            log_error "PCODE and KEY are required for monitoring deployment"
            exit 1
        fi
        deploy_monitoring
        ;;
    *)
        log_error "No command specified"
        show_help
        exit 1
        ;;
esac