# Docker Bake configuration for multi-architecture builds
# Usage: docker buildx bake -f docker-bake.hcl

variable "REGISTRY" {
  default = "renatoascencio"
}

variable "VERSION" {
  default = "optimized"
}

variable "BUILD_DATE" {
  default = ""
}

variable "VCS_REF" {
  default = ""
}

group "default" {
  targets = ["multiarch"]
}

target "multiarch" {
  dockerfile = "Dockerfile.multiarch"
  platforms = [
    "linux/amd64",
    "linux/arm64",
    "linux/arm/v7"
  ]
  tags = [
    "${REGISTRY}/zender-wa:${VERSION}",
    "${REGISTRY}/zender-wa:latest",
    "${REGISTRY}/zender-wa:${VERSION}-multiarch"
  ]
  args = {
    BUILD_DATE = "${BUILD_DATE}"
    VERSION = "${VERSION}"
    VCS_REF = "${VCS_REF}"
  }
  cache-from = ["type=gha"]
  cache-to = ["type=gha,mode=max"]
}

target "amd64" {
  inherits = ["multiarch"]
  platforms = ["linux/amd64"]
  tags = [
    "${REGISTRY}/zender-wa:${VERSION}-amd64"
  ]
}

target "arm64" {
  inherits = ["multiarch"]
  platforms = ["linux/arm64"]
  tags = [
    "${REGISTRY}/zender-wa:${VERSION}-arm64"
  ]
}

target "arm" {
  inherits = ["multiarch"]
  platforms = ["linux/arm/v7"]
  tags = [
    "${REGISTRY}/zender-wa:${VERSION}-armv7"
  ]
}

target "test" {
  dockerfile = "Dockerfile.multiarch"
  platforms = ["linux/amd64"]
  tags = ["zender-wa:test"]
  target = ""
}