#!/bin/bash
# Robust Validation and Error Handling Utilities
# Provides comprehensive input validation and error recovery

set -euo pipefail

# Error codes
readonly ERR_INVALID_INPUT=1
readonly ERR_MISSING_CONFIG=2
readonly ERR_NETWORK_ERROR=3
readonly ERR_PERMISSION_ERROR=4
readonly ERR_RESOURCE_ERROR=5
readonly ERR_SERVICE_ERROR=6

# Configuration
readonly BASE_DIR="/data/whatsapp-server"
readonly LOG_FILE="${BASE_DIR}/validation.log"

# Logging functions
log_validation() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [VALIDATION] $*" | tee -a "$LOG_FILE" >&2
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

# Validate environment variables
validate_env_vars() {
    local errors=0

    log_validation "Validating environment variables..."

    # Check required variables
    local required_vars=("PCODE" "KEY")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Missing required environment variable: $var"
            ((errors++))
        elif [[ ${#!var} -lt 10 ]]; then
            log_error "Environment variable $var appears too short: ${#!var} characters"
            ((errors++))
        fi
    done

    # Validate PORT
    if [[ -n "${PORT:-}" ]]; then
        if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ $PORT -lt 1 ]] || [[ $PORT -gt 65535 ]]; then
            log_error "Invalid PORT value: $PORT (must be 1-65535)"
            ((errors++))
        fi
    fi

    # Check for potentially malicious patterns
    for var in "${required_vars[@]}" "PORT"; do
        if [[ -n "${!var:-}" ]] && echo "${!var}" | grep -E '[;&|`$()]' >/dev/null; then
            log_error "Potentially unsafe characters in $var"
            ((errors++))
        fi
    done

    if [[ $errors -gt 0 ]]; then
        log_error "Environment validation failed with $errors errors"
        return $ERR_INVALID_INPUT
    fi

    log_validation "Environment validation passed"
    return 0
}

# Validate configuration file
validate_config_file() {
    local config_file="${1:-${BASE_DIR}/.env}"

    log_validation "Validating configuration file: $config_file"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return $ERR_MISSING_CONFIG
    fi

    if [[ ! -r "$config_file" ]]; then
        log_error "Configuration file not readable: $config_file"
        return $ERR_PERMISSION_ERROR
    fi

    # Check file size (should not be empty or too large)
    local file_size
    file_size=$(stat -f%z "$config_file" 2>/dev/null || stat -c%s "$config_file" 2>/dev/null || echo 0)

    if [[ $file_size -eq 0 ]]; then
        log_error "Configuration file is empty: $config_file"
        return $ERR_INVALID_INPUT
    fi

    if [[ $file_size -gt 1024 ]]; then
        log_error "Configuration file too large: $file_size bytes"
        return $ERR_INVALID_INPUT
    fi

    # Validate file content
    if ! grep -q "^PCODE=" "$config_file" || ! grep -q "^KEY=" "$config_file"; then
        log_error "Configuration file missing required fields"
        return $ERR_INVALID_INPUT
    fi

    # Check for shell injection patterns
    if grep -E '[;&|`$(){}[\]\\]' "$config_file" >/dev/null; then
        log_error "Configuration file contains potentially unsafe characters"
        return $ERR_INVALID_INPUT
    fi

    log_validation "Configuration file validation passed"
    return 0
}

# Validate system resources
validate_system_resources() {
    log_validation "Validating system resources..."

    # Check available memory (minimum 512MB)
    local available_memory
    available_memory=$(free -m 2>/dev/null | awk '/^Mem:/ {print $7}' || echo "0")

    if [[ $available_memory -lt 512 ]]; then
        log_error "Insufficient memory: ${available_memory}MB available (minimum 512MB required)"
        return $ERR_RESOURCE_ERROR
    fi

    # Check disk space (minimum 1GB)
    local available_space
    available_space=$(df -m "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")

    if [[ $available_space -lt 1024 ]]; then
        log_error "Insufficient disk space: ${available_space}MB available (minimum 1GB required)"
        return $ERR_RESOURCE_ERROR
    fi

    # Check if required commands are available
    local required_commands=("curl" "unzip" "ps" "kill")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command not found: $cmd"
            return $ERR_RESOURCE_ERROR
        fi
    done

    log_validation "System resources validation passed"
    return 0
}

# Validate network connectivity
validate_network() {
    local test_url="${1:-https://www.google.com}"
    local timeout="${2:-10}"

    log_validation "Validating network connectivity..."

    # Test DNS resolution
    if ! nslookup google.com >/dev/null 2>&1; then
        log_error "DNS resolution failed"
        return $ERR_NETWORK_ERROR
    fi

    # Test HTTP connectivity
    if ! curl -f -s --connect-timeout "$timeout" "$test_url" >/dev/null; then
        log_error "Network connectivity test failed"
        return $ERR_NETWORK_ERROR
    fi

    log_validation "Network connectivity validation passed"
    return 0
}

# Validate service binary
validate_binary() {
    local binary_path="${1:-${BASE_DIR}/titansys-whatsapp-linux}"

    log_validation "Validating service binary: $binary_path"

    if [[ ! -f "$binary_path" ]]; then
        log_error "Service binary not found: $binary_path"
        return $ERR_MISSING_CONFIG
    fi

    if [[ ! -x "$binary_path" ]]; then
        log_error "Service binary not executable: $binary_path"
        return $ERR_PERMISSION_ERROR
    fi

    # Check binary size (should be reasonable)
    local binary_size
    binary_size=$(stat -f%z "$binary_path" 2>/dev/null || stat -c%s "$binary_path" 2>/dev/null || echo 0)

    if [[ $binary_size -lt 1048576 ]]; then  # Less than 1MB
        log_error "Service binary appears too small: $binary_size bytes"
        return $ERR_INVALID_INPUT
    fi

    if [[ $binary_size -gt 104857600 ]]; then  # More than 100MB
        log_error "Service binary appears too large: $binary_size bytes"
        return $ERR_INVALID_INPUT
    fi

    # Test binary execution (quick check)
    if ! timeout 5 "$binary_path" --help >/dev/null 2>&1; then
        log_error "Service binary failed basic execution test"
        return $ERR_SERVICE_ERROR
    fi

    log_validation "Service binary validation passed"
    return 0
}

# Error recovery functions
recover_from_config_error() {
    log_validation "Attempting configuration recovery..."

    # Backup corrupted config if exists
    if [[ -f "${BASE_DIR}/.env" ]]; then
        cp "${BASE_DIR}/.env" "${BASE_DIR}/.env.corrupted.$(date +%s)"
    fi

    # Create basic config from environment or defaults
    if [[ -n "${PCODE:-}" ]] && [[ -n "${KEY:-}" ]]; then
        cat > "${BASE_DIR}/.env" << EOF
PORT=${PORT:-443}
PCODE=$PCODE
KEY=$KEY
EOF
        log_validation "Configuration recovered from environment variables"
        return 0
    fi

    # Copy from example if available
    if [[ -f "${BASE_DIR}/.env.example" ]]; then
        cp "${BASE_DIR}/.env.example" "${BASE_DIR}/.env"
        log_validation "Configuration recovered from example file"
        return 0
    fi

    log_error "Configuration recovery failed"
    return $ERR_MISSING_CONFIG
}

recover_from_binary_error() {
    log_validation "Attempting binary recovery..."

    # Backup corrupted binary if exists
    if [[ -f "${BASE_DIR}/titansys-whatsapp-linux" ]]; then
        mv "${BASE_DIR}/titansys-whatsapp-linux" "${BASE_DIR}/titansys-whatsapp-linux.corrupted.$(date +%s)"
    fi

    # Attempt to re-download
    local download_url="${DOWNLOAD_URL_OVERRIDE:-https://raw.anycdn.link/wa/linux.zip}"

    if curl -fsSL --connect-timeout 30 "$download_url" -o "${BASE_DIR}/linux.zip"; then
        cd "$BASE_DIR"
        if unzip -oq linux.zip && chmod +x titansys-whatsapp-linux; then
            rm -f linux.zip
            log_validation "Binary recovered from download"
            return 0
        fi
    fi

    log_error "Binary recovery failed"
    return $ERR_SERVICE_ERROR
}

# Comprehensive validation function
validate_all() {
    local errors=0
    local recovery_attempted=false

    log_validation "Starting comprehensive validation..."

    # System resources check
    if ! validate_system_resources; then
        ((errors++))
    fi

    # Network connectivity check
    if ! validate_network; then
        ((errors++))
    fi

    # Configuration validation with recovery
    if ! validate_config_file; then
        if recover_from_config_error; then
            recovery_attempted=true
            if ! validate_config_file; then
                ((errors++))
            fi
        else
            ((errors++))
        fi
    fi

    # Environment variables validation
    if ! validate_env_vars; then
        ((errors++))
    fi

    # Binary validation with recovery
    if ! validate_binary; then
        if recover_from_binary_error; then
            recovery_attempted=true
            if ! validate_binary; then
                ((errors++))
            fi
        else
            ((errors++))
        fi
    fi

    # Summary
    if [[ $errors -eq 0 ]]; then
        log_validation "All validations passed successfully"
        if [[ $recovery_attempted == true ]]; then
            log_validation "Some issues were automatically recovered"
        fi
        return 0
    else
        log_error "Validation failed with $errors errors"
        return $ERR_INVALID_INPUT
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTION]

Validation options:
  --all              Run all validations
  --env              Validate environment variables only
  --config           Validate configuration file only
  --system           Validate system resources only
  --network          Validate network connectivity only
  --binary           Validate service binary only
  --recover-config   Attempt configuration recovery
  --recover-binary   Attempt binary recovery

Examples:
  $0 --all           # Run comprehensive validation
  $0 --config        # Check configuration file only
  $0 --recover-config # Recover corrupted configuration
EOF
}

# Main function
main() {
    local option="${1:---all}"

    case "$option" in
        "--all")
            validate_all
            ;;
        "--env")
            validate_env_vars
            ;;
        "--config")
            validate_config_file
            ;;
        "--system")
            validate_system_resources
            ;;
        "--network")
            validate_network
            ;;
        "--binary")
            validate_binary
            ;;
        "--recover-config")
            recover_from_config_error
            ;;
        "--recover-binary")
            recover_from_binary_error
            ;;
        "--help"|"-h")
            usage
            ;;
        *)
            echo "Invalid option: $option" >&2
            usage
            exit $ERR_INVALID_INPUT
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi