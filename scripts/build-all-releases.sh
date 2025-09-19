#!/bin/bash
# Script para construir y publicar todas las versiones de Docker

set -e

echo "🚀 Construyendo y publicando todas las versiones de Zender WA"
echo "============================================="

# Configuración
DOCKER_REPO="renatoascencio/zender-wa"
PLATFORMS="linux/amd64,linux/arm64,linux/arm/v7"

# Verificar login en Docker Hub
echo "📋 Verificando autenticación en Docker Hub..."
if ! docker info 2>/dev/null | grep -q "Username"; then
    echo "⚠️  No estás autenticado en Docker Hub"
    echo "Por favor ejecuta: docker login"
    exit 1
fi

# Configurar Docker buildx para multi-arquitectura
echo "🔧 Configurando Docker buildx..."
docker buildx create --name zender-builder --use 2>/dev/null || docker buildx use zender-builder
docker buildx inspect --bootstrap

# Obtener todos los tags
TAGS=$(git tag -l | sort -V)
echo "📦 Tags encontrados: $TAGS"

# Construir cada versión
for TAG in $TAGS; do
    echo ""
    echo "🏗️  Construyendo versión $TAG..."
    echo "------------------------------------"

    # Checkout al tag específico
    git checkout $TAG

    # Actualizar VERSION file
    echo "$TAG" > VERSION

    # Build y push multi-arquitectura
    docker buildx build \
        --platform $PLATFORMS \
        --tag $DOCKER_REPO:$TAG \
        --build-arg VERSION=$TAG \
        --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
        --push \
        .

    echo "✅ Versión $TAG publicada"
done

# Volver a main/master
git checkout main || git checkout master

# Construir y publicar latest
echo ""
echo "🏗️  Construyendo versión latest..."
echo "------------------------------------"

# Obtener el último tag
LATEST_TAG=$(git tag -l | sort -V | tail -n1)
echo "Latest apuntará a: $LATEST_TAG"

# Checkout al último tag
git checkout $LATEST_TAG

# Build y push latest
docker buildx build \
    --platform $PLATFORMS \
    --tag $DOCKER_REPO:latest \
    --tag $DOCKER_REPO:$LATEST_TAG \
    --build-arg VERSION=$LATEST_TAG \
    --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
    --push \
    .

echo "✅ Tag 'latest' publicado"

# Crear también tags adicionales
echo ""
echo "🏗️  Creando tags adicionales..."
echo "------------------------------------"

# Tag 'stable' apunta al último release
docker buildx imagetools create \
    --tag $DOCKER_REPO:stable \
    $DOCKER_REPO:$LATEST_TAG

# Tag 'edge' apunta a latest
docker buildx imagetools create \
    --tag $DOCKER_REPO:edge \
    $DOCKER_REPO:latest

# Volver a main
git checkout main || git checkout master

echo ""
echo "📊 Resumen de imágenes publicadas:"
echo "=================================="
echo "✅ Versiones específicas:"
for TAG in $TAGS; do
    echo "   - $DOCKER_REPO:$TAG"
done
echo "✅ Tags especiales:"
echo "   - $DOCKER_REPO:latest (última versión estable)"
echo "   - $DOCKER_REPO:stable (última versión estable)"
echo "   - $DOCKER_REPO:edge (última construcción)"
echo ""
echo "🎉 ¡Todas las versiones han sido publicadas exitosamente!"
echo ""
echo "Para usar en Docker:"
echo "  docker pull $DOCKER_REPO:latest"
echo "  docker pull $DOCKER_REPO:v2.1.3"
echo "  docker pull $DOCKER_REPO:stable"