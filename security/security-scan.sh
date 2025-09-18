#!/bin/bash
# Comprehensive Security Scanning Script
# Scans containers and images for vulnerabilities

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Security scan results
SCAN_RESULTS_DIR="${PROJECT_ROOT}/security-reports"
mkdir -p "$SCAN_RESULTS_DIR"

# Trivy security scanning
scan_with_trivy() {
    local image="$1"
    local report_file="$2"

    log_info "Running Trivy security scan on $image..."

    if command -v trivy >/dev/null 2>&1; then
        # Scan for vulnerabilities
        trivy image \
            --format json \
            --output "$report_file" \
            --severity HIGH,CRITICAL \
            --ignore-unfixed \
            "$image"

        # Generate human-readable report
        trivy image \
            --format table \
            --severity HIGH,CRITICAL \
            --ignore-unfixed \
            "$image" | tee "${report_file%.json}.txt"

        # Check if critical vulnerabilities found
        local critical_count
        critical_count=$(jq -r '.Results[]? | .Vulnerabilities[]? | select(.Severity == "CRITICAL") | .VulnerabilityID' "$report_file" 2>/dev/null | wc -l)

        if [[ $critical_count -gt 0 ]]; then
            log_error "Found $critical_count CRITICAL vulnerabilities in $image"
            return 1
        else
            log_success "No critical vulnerabilities found in $image"
            return 0
        fi
    else
        log_warn "Trivy not installed. Skipping vulnerability scan."
        return 0
    fi
}

# Docker Bench for Security
run_docker_bench() {
    log_info "Running Docker Bench for Security..."

    if [[ -d "/tmp/docker-bench-security" ]]; then
        rm -rf /tmp/docker-bench-security
    fi

    git clone https://github.com/docker/docker-bench-security.git /tmp/docker-bench-security 2>/dev/null || {
        log_warn "Could not clone docker-bench-security. Skipping."
        return 0
    }

    cd /tmp/docker-bench-security
    sudo ./docker-bench-security.sh -l "$SCAN_RESULTS_DIR/docker-bench.log" || {
        log_warn "Docker Bench completed with warnings"
    }

    log_success "Docker Bench scan completed"
    cd "$PROJECT_ROOT"
}

# Hadolint Dockerfile linting
lint_dockerfile() {
    local dockerfile="$1"

    log_info "Linting Dockerfile: $dockerfile"

    if command -v hadolint >/dev/null 2>&1; then
        hadolint "$dockerfile" > "$SCAN_RESULTS_DIR/hadolint-$(basename "$dockerfile").txt" 2>&1 || {
            log_warn "Hadolint found issues in $dockerfile"
        }
        log_success "Dockerfile linting completed"
    else
        log_warn "Hadolint not installed. Skipping Dockerfile linting."
    fi
}

# Container runtime security scan
scan_container_runtime() {
    local container_name="$1"

    log_info "Scanning container runtime security: $container_name"

    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log_warn "Container $container_name not running. Skipping runtime scan."
        return 0
    fi

    local report_file="$SCAN_RESULTS_DIR/runtime-$container_name.txt"

    {
        echo "=== Container Runtime Security Report ==="
        echo "Container: $container_name"
        echo "Scan Time: $(date)"
        echo

        echo "=== User and Permissions ==="
        docker exec "$container_name" id 2>/dev/null || echo "Could not get user info"
        echo

        echo "=== Process List ==="
        docker exec "$container_name" ps aux 2>/dev/null || echo "Could not get process list"
        echo

        echo "=== Network Connections ==="
        docker exec "$container_name" netstat -tuln 2>/dev/null || \
        docker exec "$container_name" ss -tuln 2>/dev/null || \
        echo "Could not get network info"
        echo

        echo "=== File Permissions ==="
        docker exec "$container_name" find /data -type f -perm /022 2>/dev/null | head -20 || \
        echo "Could not check file permissions"
        echo

        echo "=== Environment Variables ==="
        docker exec "$container_name" env | grep -v -E '^(PCODE|KEY)=' 2>/dev/null || \
        echo "Could not get environment"
        echo

        echo "=== Capabilities ==="
        docker inspect "$container_name" --format '{{.HostConfig.CapAdd}}' 2>/dev/null || \
        echo "Could not get capabilities"

    } > "$report_file"

    log_success "Container runtime scan completed: $report_file"
}

# Secret scanning
scan_secrets() {
    log_info "Scanning for secrets and sensitive data..."

    local report_file="$SCAN_RESULTS_DIR/secrets-scan.txt"

    {
        echo "=== Secret Scanning Report ==="
        echo "Scan Time: $(date)"
        echo

        echo "=== Potential Secrets in Files ==="
        find "$PROJECT_ROOT" -type f -name "*.sh" -o -name "*.yml" -o -name "*.yaml" -o -name "*.env*" | \
        xargs grep -l -E "(password|secret|key|token)" 2>/dev/null | \
        while read -r file; do
            echo "File: $file"
            grep -n -E "(password|secret|key|token)" "$file" 2>/dev/null | \
            sed 's/\(password\|secret\|key\|token\).*$/\1=***REDACTED***/gi' || true
            echo
        done

        echo "=== Environment Files ==="
        find "$PROJECT_ROOT" -name "*.env*" -type f | while read -r file; do
            echo "File: $file"
            if [[ -f "$file" ]]; then
                grep -v '^#' "$file" 2>/dev/null | \
                sed 's/=.*/=***REDACTED***/' || true
            fi
            echo
        done

    } > "$report_file"

    log_success "Secret scanning completed: $report_file"
}

# Compliance check
check_compliance() {
    log_info "Running compliance checks..."

    local report_file="$SCAN_RESULTS_DIR/compliance.txt"

    {
        echo "=== Security Compliance Report ==="
        echo "Scan Time: $(date)"
        echo

        echo "=== CIS Docker Benchmark Checks ==="

        # Check 1: Non-root user
        echo "✓ Checking non-root user execution..."
        if grep -q "USER nonroot\|USER whatsapp" "$PROJECT_ROOT"/Dockerfile* 2>/dev/null; then
            echo "✅ PASS: Non-root user specified in Dockerfile"
        else
            echo "❌ FAIL: No non-root user specified"
        fi

        # Check 2: Read-only root filesystem
        echo "✓ Checking read-only filesystem..."
        if grep -q "readOnlyRootFilesystem.*true" "$PROJECT_ROOT"/*.yml 2>/dev/null; then
            echo "✅ PASS: Read-only root filesystem enabled"
        else
            echo "⚠️  WARN: Read-only root filesystem not explicitly enabled"
        fi

        # Check 3: No privileged containers
        echo "✓ Checking privileged execution..."
        if grep -q "privileged.*true" "$PROJECT_ROOT"/*.yml 2>/dev/null; then
            echo "❌ FAIL: Privileged container detected"
        else
            echo "✅ PASS: No privileged containers found"
        fi

        # Check 4: Resource limits
        echo "✓ Checking resource limits..."
        if grep -q "memory:\|cpus:" "$PROJECT_ROOT"/*.yml 2>/dev/null; then
            echo "✅ PASS: Resource limits specified"
        else
            echo "⚠️  WARN: No resource limits specified"
        fi

        # Check 5: Health checks
        echo "✓ Checking health checks..."
        if grep -q "HEALTHCHECK\|healthcheck:" "$PROJECT_ROOT"/Dockerfile* "$PROJECT_ROOT"/*.yml 2>/dev/null; then
            echo "✅ PASS: Health checks implemented"
        else
            echo "❌ FAIL: No health checks found"
        fi

        echo
        echo "=== Security Features Summary ==="
        echo "- Multi-stage builds: $(grep -q "FROM.*AS" "$PROJECT_ROOT"/Dockerfile* && echo "✅ Yes" || echo "❌ No")"
        echo "- Distroless option: $(ls "$PROJECT_ROOT"/Dockerfile.secure >/dev/null 2>&1 && echo "✅ Yes" || echo "❌ No")"
        echo "- Multi-architecture: $(grep -q "TARGETPLATFORM" "$PROJECT_ROOT"/Dockerfile* && echo "✅ Yes" || echo "❌ No")"
        echo "- Security scanning: $(ls "$PROJECT_ROOT"/.github/workflows/*.yml >/dev/null 2>&1 && echo "✅ Yes" || echo "❌ No")"
        echo "- Monitoring: $(ls "$PROJECT_ROOT"/monitoring/*.sh >/dev/null 2>&1 && echo "✅ Yes" || echo "❌ No")"

    } > "$report_file"

    log_success "Compliance check completed: $report_file"
}

# Generate security summary
generate_summary() {
    log_info "Generating security summary..."

    local summary_file="$SCAN_RESULTS_DIR/security-summary.md"

    {
        echo "# Security Scan Summary"
        echo
        echo "**Scan Date:** $(date)"
        echo "**Project:** Zender WhatsApp Server"
        echo
        echo "## Scan Results"
        echo

        # Count vulnerabilities if trivy reports exist
        if ls "$SCAN_RESULTS_DIR"/*.json >/dev/null 2>&1; then
            echo "### Vulnerability Summary"
            for json_file in "$SCAN_RESULTS_DIR"/*.json; do
                local image_name
                image_name=$(basename "$json_file" .json)
                local critical high medium low
                critical=$(jq -r '.Results[]? | .Vulnerabilities[]? | select(.Severity == "CRITICAL") | .VulnerabilityID' "$json_file" 2>/dev/null | wc -l)
                high=$(jq -r '.Results[]? | .Vulnerabilities[]? | select(.Severity == "HIGH") | .VulnerabilityID' "$json_file" 2>/dev/null | wc -l)
                medium=$(jq -r '.Results[]? | .Vulnerabilities[]? | select(.Severity == "MEDIUM") | .VulnerabilityID' "$json_file" 2>/dev/null | wc -l)
                low=$(jq -r '.Results[]? | .Vulnerabilities[]? | select(.Severity == "LOW") | .VulnerabilityID' "$json_file" 2>/dev/null | wc -l)

                echo "- **$image_name:** Critical: $critical, High: $high, Medium: $medium, Low: $low"
            done
            echo
        fi

        echo "### Files Generated"
        ls -la "$SCAN_RESULTS_DIR"/ | tail -n +2 | while read -r line; do
            echo "- $(echo "$line" | awk '{print $9}')"
        done

        echo
        echo "### Recommendations"
        echo "1. Review all CRITICAL and HIGH severity vulnerabilities"
        echo "2. Update base images to latest versions"
        echo "3. Implement additional security controls as needed"
        echo "4. Regular security scans in CI/CD pipeline"

    } > "$summary_file"

    log_success "Security summary generated: $summary_file"
}

# Main execution
main() {
    local mode="${1:-all}"

    log_info "Starting security scan in mode: $mode"

    case "$mode" in
        "dockerfile")
            lint_dockerfile "$PROJECT_ROOT/Dockerfile.optimized"
            lint_dockerfile "$PROJECT_ROOT/Dockerfile.multiarch"
            lint_dockerfile "$PROJECT_ROOT/Dockerfile.secure"
            ;;
        "image")
            local image="${2:-zender-wa:test}"
            scan_with_trivy "$image" "$SCAN_RESULTS_DIR/trivy-$image.json"
            ;;
        "container")
            local container="${2:-zender-wa-optimized}"
            scan_container_runtime "$container"
            ;;
        "secrets")
            scan_secrets
            ;;
        "compliance")
            check_compliance
            ;;
        "all"|*)
            lint_dockerfile "$PROJECT_ROOT/Dockerfile.optimized"
            lint_dockerfile "$PROJECT_ROOT/Dockerfile.multiarch"
            lint_dockerfile "$PROJECT_ROOT/Dockerfile.secure"
            scan_secrets
            check_compliance
            run_docker_bench
            generate_summary
            ;;
    esac

    log_success "Security scan completed. Results in: $SCAN_RESULTS_DIR"
}

# Help function
show_help() {
    cat << EOF
Security Scanning Tool for Zender WhatsApp Server

Usage: $0 [MODE] [OPTIONS]

Modes:
    all          Run all security scans (default)
    dockerfile   Lint Dockerfiles only
    image        Scan specific image for vulnerabilities
    container    Scan running container
    secrets      Scan for secrets and sensitive data
    compliance   Check security compliance

Examples:
    $0                           # Run all scans
    $0 dockerfile                # Lint all Dockerfiles
    $0 image zender-wa:optimized # Scan specific image
    $0 container my-container    # Scan running container
    $0 secrets                   # Scan for secrets
    $0 compliance                # Check compliance

Requirements:
    - trivy (for vulnerability scanning)
    - hadolint (for Dockerfile linting)
    - docker (for container inspection)
    - jq (for JSON processing)

EOF
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        show_help
        exit 0
    fi

    main "$@"
fi