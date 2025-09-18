#!/bin/bash
# Unit Tests for Shell Scripts
# Tests individual script functionality

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test framework
source "$SCRIPT_DIR/../test-framework.sh"

# Test entrypoint script validation
test_entrypoint_validation() {
    test_start "Entrypoint script validation"

    # Test syntax
    if bash -n "$PROJECT_ROOT/entrypoint.optimized.sh"; then
        test_pass "Entrypoint syntax valid"
    else
        test_fail "Entrypoint syntax error"
        return 1
    fi

    # Test function definitions
    if grep -q "print_header" "$PROJECT_ROOT/entrypoint.optimized.sh" && \
       grep -q "validate_environment" "$PROJECT_ROOT/entrypoint.optimized.sh" && \
       grep -q "cleanup_old_logs" "$PROJECT_ROOT/entrypoint.optimized.sh"; then
        test_pass "Required functions defined"
    else
        test_fail "Missing required functions"
        return 1
    fi

    # Test error handling
    if grep -q "set -euo pipefail" "$PROJECT_ROOT/entrypoint.optimized.sh"; then
        test_pass "Error handling enabled"
    else
        test_fail "Error handling not enabled"
        return 1
    fi
}

# Test healthcheck script
test_healthcheck_script() {
    test_start "Healthcheck script validation"

    local healthcheck_script="$PROJECT_ROOT/monitoring/healthcheck.sh"

    # Test syntax
    if bash -n "$healthcheck_script"; then
        test_pass "Healthcheck syntax valid"
    else
        test_fail "Healthcheck syntax error"
        return 1
    fi

    # Test required functions
    if grep -q "check_process" "$healthcheck_script" && \
       grep -q "check_memory" "$healthcheck_script" && \
       grep -q "check_cpu" "$healthcheck_script"; then
        test_pass "Health check functions defined"
    else
        test_fail "Missing health check functions"
        return 1
    fi

    # Test metrics generation
    if grep -q "generate_metrics" "$healthcheck_script"; then
        test_pass "Metrics generation implemented"
    else
        test_fail "Metrics generation missing"
        return 1
    fi
}

# Test validation script
test_validation_script() {
    test_start "Validation script testing"

    local validation_script="$PROJECT_ROOT/utils/validation.sh"

    # Test syntax
    if bash -n "$validation_script"; then
        test_pass "Validation syntax valid"
    else
        test_fail "Validation syntax error"
        return 1
    fi

    # Test validation functions
    if grep -q "validate_env_vars" "$validation_script" && \
       grep -q "validate_config_file" "$validation_script" && \
       grep -q "validate_system_resources" "$validation_script"; then
        test_pass "Validation functions defined"
    else
        test_fail "Missing validation functions"
        return 1
    fi

    # Test recovery functions
    if grep -q "recover_from_config_error" "$validation_script" && \
       grep -q "recover_from_binary_error" "$validation_script"; then
        test_pass "Recovery functions defined"
    else
        test_fail "Missing recovery functions"
        return 1
    fi
}

# Test process manager
test_process_manager() {
    test_start "Process manager testing"

    local process_script="$PROJECT_ROOT/utils/process-manager.sh"

    # Test syntax
    if bash -n "$process_script"; then
        test_pass "Process manager syntax valid"
    else
        test_fail "Process manager syntax error"
        return 1
    fi

    # Test process functions
    if grep -q "start_service" "$process_script" && \
       grep -q "stop_service" "$process_script" && \
       grep -q "is_service_running" "$process_script"; then
        test_pass "Process management functions defined"
    else
        test_fail "Missing process management functions"
        return 1
    fi

    # Test monitoring
    if grep -q "monitor_process" "$process_script" && \
       grep -q "start_monitoring" "$process_script"; then
        test_pass "Process monitoring implemented"
    else
        test_fail "Process monitoring missing"
        return 1
    fi
}

# Test log monitor
test_log_monitor() {
    test_start "Log monitor testing"

    local log_script="$PROJECT_ROOT/monitoring/log-monitor.sh"

    # Test syntax
    if bash -n "$log_script"; then
        test_pass "Log monitor syntax valid"
    else
        test_fail "Log monitor syntax error"
        return 1
    fi

    # Test monitoring functions
    if grep -q "analyze_logs" "$log_script" && \
       grep -q "check_specific_patterns" "$log_script" && \
       grep -q "monitor_realtime" "$log_script"; then
        test_pass "Log monitoring functions defined"
    else
        test_fail "Missing log monitoring functions"
        return 1
    fi

    # Test alerting
    if grep -q "send_alert" "$log_script"; then
        test_pass "Alert system implemented"
    else
        test_fail "Alert system missing"
        return 1
    fi
}

# Test script permissions
test_script_permissions() {
    test_start "Script permissions testing"

    local scripts=(
        "$PROJECT_ROOT/entrypoint.optimized.sh"
        "$PROJECT_ROOT/monitoring/healthcheck.sh"
        "$PROJECT_ROOT/monitoring/log-monitor.sh"
        "$PROJECT_ROOT/utils/validation.sh"
        "$PROJECT_ROOT/utils/process-manager.sh"
    )

    local permission_errors=0

    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            # Check if script has execute permission
            if [[ -x "$script" ]]; then
                continue
            else
                ((permission_errors++))
            fi
        else
            ((permission_errors++))
        fi
    done

    if [[ $permission_errors -eq 0 ]]; then
        test_pass "All scripts have correct permissions"
    else
        test_fail "$permission_errors scripts have permission issues"
        return 1
    fi
}

# Test script configuration
test_script_configuration() {
    test_start "Script configuration testing"

    # Test if scripts use consistent base directory
    local base_dir_issues=0
    local scripts=(
        "$PROJECT_ROOT/entrypoint.optimized.sh"
        "$PROJECT_ROOT/monitoring/healthcheck.sh"
        "$PROJECT_ROOT/utils/validation.sh"
        "$PROJECT_ROOT/utils/process-manager.sh"
    )

    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if ! grep -q 'BASE_DIR="/data/whatsapp-server"' "$script"; then
                ((base_dir_issues++))
            fi
        fi
    done

    if [[ $base_dir_issues -eq 0 ]]; then
        test_pass "Consistent base directory configuration"
    else
        test_fail "$base_dir_issues scripts have inconsistent base directory"
        return 1
    fi

    # Test if scripts use consistent executable name
    local exec_name_issues=0
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if ! grep -q 'EXECUTABLE_NAME="titansys-whatsapp-linux"' "$script"; then
                ((exec_name_issues++))
            fi
        fi
    done

    if [[ $exec_name_issues -eq 0 ]]; then
        test_pass "Consistent executable name configuration"
    else
        test_fail "$exec_name_issues scripts have inconsistent executable name"
        return 1
    fi
}

# Run all unit tests
run_all_tests() {
    test_suite_start "Script Unit Tests"

    test_entrypoint_validation
    test_healthcheck_script
    test_validation_script
    test_process_manager
    test_log_monitor
    test_script_permissions
    test_script_configuration

    test_suite_end
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi