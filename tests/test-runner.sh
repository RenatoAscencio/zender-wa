#!/bin/bash
# Automated Testing Framework for Zender WhatsApp Server
# Runs unit, integration, and performance tests

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly TEST_RESULTS_DIR="${PROJECT_ROOT}/test-results"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Test result tracking
start_test() {
    local test_name="$1"
    ((TESTS_RUN++))
    log_info "Running test: $test_name"
}

pass_test() {
    local test_name="$1"
    ((TESTS_PASSED++))
    log_success "✅ PASS: $test_name"
}

fail_test() {
    local test_name="$1"
    local error_msg="${2:-Unknown error}"
    ((TESTS_FAILED++))
    log_error "❌ FAIL: $test_name - $error_msg"
}

# Setup test environment
setup_test_env() {
    log_info "Setting up test environment..."

    mkdir -p "$TEST_RESULTS_DIR"

    # Clean up any previous test containers
    docker rm -f test-zender-wa test-zender-perf test-zender-integration 2>/dev/null || true

    # Build test image if not exists
    if ! docker images | grep -q "zender-wa:test"; then
        log_info "Building test image..."
        docker build -f "$PROJECT_ROOT/Dockerfile.optimized" -t zender-wa:test "$PROJECT_ROOT"
    fi

    log_success "Test environment ready"
}

# Cleanup test environment
cleanup_test_env() {
    log_info "Cleaning up test environment..."
    docker rm -f test-zender-wa test-zender-perf test-zender-integration 2>/dev/null || true
    log_success "Test environment cleaned"
}

# Unit Tests
run_unit_tests() {
    log_info "=== Running Unit Tests ==="

    # Test 1: Script syntax validation
    start_test "Script syntax validation"
    if bash -n "$PROJECT_ROOT/entrypoint.optimized.sh" && \
       bash -n "$PROJECT_ROOT/monitoring/healthcheck.sh" && \
       bash -n "$PROJECT_ROOT/monitoring/log-monitor.sh" && \
       bash -n "$PROJECT_ROOT/utils/validation.sh" && \
       bash -n "$PROJECT_ROOT/utils/process-manager.sh"; then
        pass_test "Script syntax validation"
    else
        fail_test "Script syntax validation" "Syntax errors found in scripts"
    fi

    # Test 2: Dockerfile validation
    start_test "Dockerfile validation"
    local dockerfile_errors=0
    for dockerfile in "$PROJECT_ROOT"/Dockerfile*; do
        if [[ -f "$dockerfile" ]]; then
            if ! docker build -f "$dockerfile" --target builder "$PROJECT_ROOT" >/dev/null 2>&1; then
                ((dockerfile_errors++))
            fi
        fi
    done

    if [[ $dockerfile_errors -eq 0 ]]; then
        pass_test "Dockerfile validation"
    else
        fail_test "Dockerfile validation" "$dockerfile_errors Dockerfiles failed to build"
    fi

    # Test 3: Configuration validation
    start_test "Configuration validation"
    local validation_output
    if validation_output=$(docker run --rm -v "$PROJECT_ROOT":/app zender-wa:test bash -c "
        cd /app && ./utils/validation.sh --system
    " 2>&1); then
        pass_test "Configuration validation"
    else
        fail_test "Configuration validation" "$validation_output"
    fi

    # Test 4: Security checks
    start_test "Security checks"
    if docker run --rm zender-wa:test id | grep -q "uid=1001"; then
        pass_test "Security checks"
    else
        fail_test "Security checks" "Container not running as non-root user"
    fi
}

# Integration Tests
run_integration_tests() {
    log_info "=== Running Integration Tests ==="

    # Test 1: Container startup
    start_test "Container startup"
    if docker run -d --name test-zender-integration \
        -e PCODE="test-pcode" \
        -e KEY="test-key" \
        zender-wa:test >/dev/null 2>&1; then

        # Wait for container to initialize
        sleep 10

        if docker ps | grep -q test-zender-integration; then
            pass_test "Container startup"
        else
            fail_test "Container startup" "Container exited unexpectedly"
        fi
    else
        fail_test "Container startup" "Failed to start container"
    fi

    # Test 2: Management commands
    start_test "Management commands"
    local cmd_errors=0

    # Test status command
    if ! docker exec test-zender-integration status-wa >/dev/null 2>&1; then
        ((cmd_errors++))
    fi

    # Test health check
    if ! docker exec test-zender-integration /usr/local/bin/healthcheck.sh >/dev/null 2>&1; then
        ((cmd_errors++))
    fi

    # Test validation
    if ! docker exec test-zender-integration /usr/local/bin/validation.sh --system >/dev/null 2>&1; then
        ((cmd_errors++))
    fi

    if [[ $cmd_errors -eq 0 ]]; then
        pass_test "Management commands"
    else
        fail_test "Management commands" "$cmd_errors commands failed"
    fi

    # Test 3: Data persistence
    start_test "Data persistence"

    # Create test data
    docker exec test-zender-integration bash -c "echo 'test data' > /data/whatsapp-server/test-persistence.txt"

    # Restart container
    docker restart test-zender-integration >/dev/null 2>&1
    sleep 5

    # Check if data persists
    if docker exec test-zender-integration test -f /data/whatsapp-server/test-persistence.txt; then
        pass_test "Data persistence"
    else
        fail_test "Data persistence" "Data not persisted after restart"
    fi

    # Test 4: Network connectivity
    start_test "Network connectivity"
    if docker exec test-zender-integration curl -f --connect-timeout 10 https://www.google.com >/dev/null 2>&1; then
        pass_test "Network connectivity"
    else
        fail_test "Network connectivity" "Cannot reach external network"
    fi

    # Cleanup
    docker rm -f test-zender-integration >/dev/null 2>&1 || true
}

# Performance Tests
run_performance_tests() {
    log_info "=== Running Performance Tests ==="

    # Test 1: Image size
    start_test "Image size optimization"
    local image_size
    image_size=$(docker images zender-wa:test --format "table {{.Size}}" | tail -1 | sed 's/MB//' | sed 's/GB/*1000/' | bc 2>/dev/null || echo "200")

    # Target: under 200MB
    if (( $(echo "$image_size < 200" | bc -l) )); then
        pass_test "Image size optimization (${image_size}MB)"
    else
        fail_test "Image size optimization" "Image too large: ${image_size}MB (target: <200MB)"
    fi

    # Test 2: Startup time
    start_test "Container startup time"
    local start_time end_time startup_duration

    start_time=$(date +%s)
    docker run -d --name test-zender-perf \
        -e PCODE="test" -e KEY="test" \
        zender-wa:test >/dev/null 2>&1

    # Wait for container to be ready
    local timeout=60
    while [[ $timeout -gt 0 ]]; do
        if docker exec test-zender-perf status-wa >/dev/null 2>&1; then
            break
        fi
        sleep 1
        ((timeout--))
    done

    end_time=$(date +%s)
    startup_duration=$((end_time - start_time))

    # Target: under 30 seconds
    if [[ $startup_duration -lt 30 ]]; then
        pass_test "Container startup time (${startup_duration}s)"
    else
        fail_test "Container startup time" "Too slow: ${startup_duration}s (target: <30s)"
    fi

    # Test 3: Memory usage
    start_test "Memory usage optimization"
    sleep 5  # Let container stabilize

    local memory_usage
    memory_usage=$(docker stats test-zender-perf --no-stream --format "table {{.MemUsage}}" | tail -1 | cut -d'/' -f1 | sed 's/MiB//' | sed 's/GiB/*1000/' | bc 2>/dev/null || echo "200")

    # Target: under 200MB
    if (( $(echo "$memory_usage < 200" | bc -l) )); then
        pass_test "Memory usage optimization (${memory_usage}MB)"
    else
        fail_test "Memory usage optimization" "Too much memory: ${memory_usage}MB (target: <200MB)"
    fi

    # Test 4: Build time (if cache available)
    start_test "Build time optimization"
    local build_start build_end build_duration

    build_start=$(date +%s)
    docker build -f "$PROJECT_ROOT/Dockerfile.optimized" -t zender-wa:perf-test "$PROJECT_ROOT" >/dev/null 2>&1
    build_end=$(date +%s)
    build_duration=$((build_end - build_start))

    # Target: under 120 seconds with cache
    if [[ $build_duration -lt 120 ]]; then
        pass_test "Build time optimization (${build_duration}s)"
    else
        fail_test "Build time optimization" "Too slow: ${build_duration}s (target: <120s)"
    fi

    # Cleanup
    docker rm -f test-zender-perf >/dev/null 2>&1 || true
    docker rmi -f zender-wa:perf-test >/dev/null 2>&1 || true
}

# Load testing
run_load_tests() {
    log_info "=== Running Load Tests ==="

    # Test 1: Multiple container instances
    start_test "Multiple container instances"
    local containers=()
    local failed_containers=0

    # Start 3 containers simultaneously
    for i in {1..3}; do
        local container_name="test-load-$i"
        if docker run -d --name "$container_name" \
            -e PCODE="test$i" -e KEY="test$i" \
            zender-wa:test >/dev/null 2>&1; then
            containers+=("$container_name")
        else
            ((failed_containers++))
        fi
    done

    sleep 15  # Let containers initialize

    # Check if all containers are running
    local running_containers=0
    for container in "${containers[@]}"; do
        if docker ps | grep -q "$container"; then
            ((running_containers++))
        fi
    done

    # Cleanup
    for container in "${containers[@]}"; do
        docker rm -f "$container" >/dev/null 2>&1 || true
    done

    if [[ $running_containers -eq 3 ]]; then
        pass_test "Multiple container instances"
    else
        fail_test "Multiple container instances" "Only $running_containers/3 containers running"
    fi
}

# Generate test report
generate_test_report() {
    local report_file="$TEST_RESULTS_DIR/test-report.md"

    {
        echo "# Test Report - Zender WhatsApp Server"
        echo
        echo "**Test Date:** $(date)"
        echo "**Test Duration:** $((SECONDS / 60)) minutes"
        echo
        echo "## Summary"
        echo
        echo "- **Total Tests:** $TESTS_RUN"
        echo "- **Passed:** $TESTS_PASSED"
        echo "- **Failed:** $TESTS_FAILED"
        echo "- **Success Rate:** $(( TESTS_PASSED * 100 / TESTS_RUN ))%"
        echo

        if [[ $TESTS_FAILED -eq 0 ]]; then
            echo "🎉 **All tests passed!**"
        else
            echo "⚠️ **Some tests failed. Please review the output above.**"
        fi

        echo
        echo "## Test Categories"
        echo
        echo "### Unit Tests"
        echo "- Script syntax validation"
        echo "- Dockerfile validation"
        echo "- Configuration validation"
        echo "- Security checks"
        echo
        echo "### Integration Tests"
        echo "- Container startup"
        echo "- Management commands"
        echo "- Data persistence"
        echo "- Network connectivity"
        echo
        echo "### Performance Tests"
        echo "- Image size optimization"
        echo "- Container startup time"
        echo "- Memory usage optimization"
        echo "- Build time optimization"
        echo
        echo "### Load Tests"
        echo "- Multiple container instances"
        echo
        echo "---"
        echo "Generated by automated testing framework"

    } > "$report_file"

    log_info "Test report generated: $report_file"
}

# Show help
show_help() {
    cat << EOF
Automated Testing Framework for Zender WhatsApp Server

Usage: $0 [TEST_TYPE]

Test Types:
    all          Run all tests (default)
    unit         Run unit tests only
    integration  Run integration tests only
    performance  Run performance tests only
    load         Run load tests only

Examples:
    $0                  # Run all tests
    $0 unit             # Run unit tests only
    $0 performance      # Run performance tests only

Requirements:
    - Docker
    - bc (for calculations)
    - curl (for network tests)

EOF
}

# Main execution
main() {
    local test_type="${1:-all}"

    if [[ "$test_type" == "--help" ]] || [[ "$test_type" == "-h" ]]; then
        show_help
        exit 0
    fi

    log_info "Starting automated tests: $test_type"

    setup_test_env
    trap cleanup_test_env EXIT

    case "$test_type" in
        "unit")
            run_unit_tests
            ;;
        "integration")
            run_integration_tests
            ;;
        "performance")
            run_performance_tests
            ;;
        "load")
            run_load_tests
            ;;
        "all"|*)
            run_unit_tests
            run_integration_tests
            run_performance_tests
            run_load_tests
            ;;
    esac

    generate_test_report

    log_info "Testing completed!"
    log_info "Results: $TESTS_PASSED/$TESTS_RUN tests passed"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_error "$TESTS_FAILED tests failed"
        exit 1
    else
        log_success "All tests passed!"
        exit 0
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi