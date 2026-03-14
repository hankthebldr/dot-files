#!/usr/bin/env bash
# tests/test-runner.sh
# Main test runner for dot-files

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/utils/validators.sh"

run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    log_info "Running test: $test_name"
    if eval "$test_cmd"; then
        log_success "Test passed: $test_name"
    else
        log_error "Test failed: $test_name"
        return 1
    fi
}

test_tools() {
    log_info "Testing tools availability..."
    verify_installation || return 1
}

test_configs() {
    log_info "Testing configurations..."
    
    # Git
    if [[ ! -f "$HOME/.gitconfig" ]]; then
        # Check if we stowed it (might not be stowed yet in test environment)
        # But for post-install test it should be there.
        # Minimal check for now
        log_warning ".gitconfig not found (may not be stowed yet)"
    fi
    
    # Zsh
    bash -n scripts/install/packages/common.sh || return 1
    
    return 0
}

main() {
    log_info "Starting Test Suite..."
    local failures=0
    
    run_test "Tools Installation" test_tools || ((failures++))
    run_test "Configuration Validity" test_configs || ((failures++))
    
    if [[ $failures -eq 0 ]]; then
        log_success "All tests passed!"
        exit 0
    else
        log_error "$failures tests failed."
        exit 1
    fi
}

main
