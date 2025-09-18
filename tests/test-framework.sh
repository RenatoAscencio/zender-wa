#!/bin/bash
# Test Framework for Zender WhatsApp Server
# Provides common testing utilities and assertions

set -euo pipefail

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
CURRENT_TEST=""

# Test suite tracking
SUITE_NAME=""
SUITE_START_TIME=""

# Logging functions
test_log() { echo -e "${BLUE}[TEST]${NC} $*"; }
test_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
test_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
test_error() { echo -e "${RED}[ERROR]${NC} $*"; }
test_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Test suite functions
test_suite_start() {
    SUITE_NAME="$1"
    SUITE_START_TIME=$(date +%s)
    echo
    echo "=========================================="
    echo "Test Suite: $SUITE_NAME"
    echo "Started: $(date)"
    echo "=========================================="
    echo
}

test_suite_end() {
    local end_time=$(date +%s)
    local duration=$((end_time - SUITE_START_TIME))

    echo
    echo "=========================================="
    echo "Test Suite: $SUITE_NAME - COMPLETED"
    echo "Duration: ${duration}s"
    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_RUN total"
    echo "Success Rate: $(( TESTS_PASSED * 100 / TESTS_RUN ))%"
    echo "=========================================="
    echo

    if [[ $TESTS_FAILED -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# Individual test functions
test_start() {
    CURRENT_TEST="$1"
    ((TESTS_RUN++))
    test_log "Running: $CURRENT_TEST"
}

test_pass() {
    local message="${1:-$CURRENT_TEST}"
    ((TESTS_PASSED++))
    test_success "✅ PASS: $message"
}

test_fail() {
    local message="${1:-$CURRENT_TEST}"
    local error_detail="${2:-}"
    ((TESTS_FAILED++))
    test_error "❌ FAIL: $message"
    if [[ -n "$error_detail" ]]; then
        test_error "   Detail: $error_detail"
    fi
}

test_skip() {
    local message="${1:-$CURRENT_TEST}"
    local reason="${2:-No reason provided}"
    test_warn "⏭️  SKIP: $message (Reason: $reason)"
}

# Assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    if [[ "$expected" == "$actual" ]]; then
        test_pass "$message"
        return 0
    else
        test_fail "$message" "Expected: '$expected', Actual: '$actual'"
        return 1
    fi
}

assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"

    if [[ "$expected" != "$actual" ]]; then
        test_pass "$message"
        return 0
    else
        test_fail "$message" "Both values are: '$expected'"
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-Condition should be true}"

    if [[ "$condition" == "true" ]] || [[ "$condition" == "0" ]]; then
        test_pass "$message"
        return 0
    else
        test_fail "$message" "Condition evaluated to: '$condition'"
        return 1
    fi
}

assert_false() {
    local condition="$1"
    local message="${2:-Condition should be false}"

    if [[ "$condition" == "false" ]] || [[ "$condition" != "0" && "$condition" != "true" ]]; then
        test_pass "$message"
        return 0
    else
        test_fail "$message" "Condition evaluated to: '$condition'"
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local message="${2:-File should exist}"

    if [[ -f "$file_path" ]]; then
        test_pass "$message: $file_path"
        return 0
    else
        test_fail "$message" "File not found: $file_path"
        return 1
    fi
}

assert_file_not_exists() {
    local file_path="$1"
    local message="${2:-File should not exist}"

    if [[ ! -f "$file_path" ]]; then
        test_pass "$message: $file_path"
        return 0
    else
        test_fail "$message" "File exists: $file_path"
        return 1
    fi
}

assert_directory_exists() {
    local dir_path="$1"
    local message="${2:-Directory should exist}"

    if [[ -d "$dir_path" ]]; then
        test_pass "$message: $dir_path"
        return 0
    else
        test_fail "$message" "Directory not found: $dir_path"
        return 1
    fi
}

assert_executable() {
    local file_path="$1"
    local message="${2:-File should be executable}"

    if [[ -x "$file_path" ]]; then
        test_pass "$message: $file_path"
        return 0
    else
        test_fail "$message" "File not executable: $file_path"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    if [[ "$haystack" == *"$needle"* ]]; then
        test_pass "$message"
        return 0
    else
        test_fail "$message" "String '$haystack' does not contain '$needle'"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"

    if [[ "$haystack" != *"$needle"* ]]; then
        test_pass "$message"
        return 0
    else
        test_fail "$message" "String '$haystack' contains '$needle'"
        return 1
    fi
}

assert_matches_regex() {
    local string="$1"
    local pattern="$2"
    local message="${3:-String should match regex pattern}"

    if [[ "$string" =~ $pattern ]]; then
        test_pass "$message"
        return 0
    else
        test_fail "$message" "String '$string' does not match pattern '$pattern'"
        return 1
    fi
}

assert_command_success() {
    local command="$1"
    local message="${2:-Command should succeed}"

    if eval "$command" >/dev/null 2>&1; then
        test_pass "$message: $command"
        return 0
    else
        test_fail "$message" "Command failed: $command"
        return 1
    fi
}

assert_command_failure() {
    local command="$1"
    local message="${2:-Command should fail}"

    if ! eval "$command" >/dev/null 2>&1; then
        test_pass "$message: $command"
        return 0
    else
        test_fail "$message" "Command succeeded: $command"
        return 1
    fi
}

assert_docker_image_exists() {
    local image_name="$1"
    local message="${2:-Docker image should exist}"

    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image_name}$"; then
        test_pass "$message: $image_name"
        return 0
    else
        test_fail "$message" "Docker image not found: $image_name"
        return 1
    fi
}

assert_docker_container_running() {
    local container_name="$1"
    local message="${2:-Docker container should be running}"

    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        test_pass "$message: $container_name"
        return 0
    else
        test_fail "$message" "Container not running: $container_name"
        return 1
    fi
}

assert_port_open() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    local message="${4:-Port should be open}"

    if timeout "$timeout" bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        test_pass "$message: $host:$port"
        return 0
    else
        test_fail "$message" "Port not accessible: $host:$port"
        return 1
    fi
}

assert_http_response() {
    local url="$1"
    local expected_code="${2:-200}"
    local message="${3:-HTTP request should succeed}"

    local actual_code
    actual_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")

    if [[ "$actual_code" == "$expected_code" ]]; then
        test_pass "$message: $url (HTTP $actual_code)"
        return 0
    else
        test_fail "$message" "Expected HTTP $expected_code, got $actual_code for $url"
        return 1
    fi
}

# Mock and stub functions
mock_command() {
    local command_name="$1"
    local mock_behavior="$2"
    local mock_script="/tmp/mock_${command_name}_$$"

    cat > "$mock_script" << EOF
#!/bin/bash
$mock_behavior
EOF
    chmod +x "$mock_script"

    # Add to PATH
    export PATH="/tmp:$PATH"
    ln -sf "$mock_script" "/tmp/$command_name"

    test_info "Mocked command: $command_name"
}

cleanup_mocks() {
    rm -f /tmp/mock_*_$$
    rm -f /tmp/docker /tmp/curl /tmp/systemctl 2>/dev/null || true
}

# Test data helpers
create_test_file() {
    local file_path="$1"
    local content="${2:-test content}"

    mkdir -p "$(dirname "$file_path")"
    echo "$content" > "$file_path"
}

create_test_env_file() {
    local file_path="$1"
    local pcode="${2:-test-pcode}"
    local key="${3:-test-key}"
    local port="${4:-443}"

    mkdir -p "$(dirname "$file_path")"
    cat > "$file_path" << EOF
PORT=$port
PCODE=$pcode
KEY=$key
EOF
}

cleanup_test_files() {
    rm -rf /tmp/test_* 2>/dev/null || true
}

# Performance measurement
start_timer() {
    TEST_TIMER_START=$(date +%s%N)
}

end_timer() {
    local end_time=$(date +%s%N)
    local duration_ns=$((end_time - TEST_TIMER_START))
    local duration_ms=$((duration_ns / 1000000))
    echo "$duration_ms"
}

assert_performance() {
    local max_duration_ms="$1"
    local actual_duration_ms="$2"
    local message="${3:-Performance should be within threshold}"

    if [[ $actual_duration_ms -le $max_duration_ms ]]; then
        test_pass "$message (${actual_duration_ms}ms <= ${max_duration_ms}ms)"
        return 0
    else
        test_fail "$message" "Too slow: ${actual_duration_ms}ms > ${max_duration_ms}ms"
        return 1
    fi
}

# Test environment setup
setup_test_environment() {
    export TEST_MODE=true
    export BASE_DIR="/tmp/test-whatsapp-server"
    mkdir -p "$BASE_DIR"

    # Create minimal test structure
    mkdir -p "$BASE_DIR"/{monitoring,utils,backups}

    test_info "Test environment set up in $BASE_DIR"
}

cleanup_test_environment() {
    rm -rf "$BASE_DIR" 2>/dev/null || true
    cleanup_mocks
    cleanup_test_files

    test_info "Test environment cleaned up"
}

# Trap to ensure cleanup
trap cleanup_test_environment EXIT