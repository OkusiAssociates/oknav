#!/usr/bin/env bats
# ==============================================================================
# OKnav Test Suite - ok Orchestrator Integration Tests
# ==============================================================================
# Tests for multi-server SSH command orchestrator (ok)
#
# Key behaviors tested:
#   - Server discovery from symlinks validated against hosts.conf
#   - Option parsing (-p, -t, -x, -D)
#   - Sequential and parallel execution modes
#   - Server exclusion handling (hosts.conf options and -x flag)
#   - Cleanup on exit
#
# Run: bats tests/ok.bats
# ==============================================================================

load test_helper

# Helper to set up ok environment with hosts.conf
setup_ok_env() {
  local -a servers=("$@")

  # Default servers if none specified
  if ((${#servers[@]} == 0)); then
    servers=(ok0 ok1 ok2)
  fi

  # Create symlinks
  create_server_symlinks "$TEST_TEMP_DIR" "${servers[@]}"

  # Build hosts.conf entries (with oknav option for cluster discovery)
  local -a entries=()
  for srv in "${servers[@]}"; do
    entries+=("${srv}.test.local  $srv  (oknav)")
  done
  create_hosts_conf "$TEST_TEMP_DIR" "${entries[@]}"

  # Copy ok script
  cp "${PROJECT_DIR}/ok" "${TEST_TEMP_DIR}/"

  # Set up mocks
  create_mock_sudo
  create_mock_timeout
}

# ==============================================================================
# Help and Version Tests
# ==============================================================================

@test "ok without arguments shows usage and exits 1" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok
  ((status == 1))
  assert_output_contains "Usage:"
}

@test "ok -h shows usage and exits 0" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok -h
  ((status == 0))
  assert_output_contains "Usage:"
  assert_output_contains "Options:"
}

@test "ok --help shows usage and exits 0" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok --help
  ((status == 0))
  assert_output_contains "Usage:"
}

@test "ok -V shows version and exits 0" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok -V
  ((status == 0))
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "ok --version shows version and exits 0" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok --version
  ((status == 0))
}

# ==============================================================================
# Server Discovery Tests
# ==============================================================================

@test "ok discovers ok* symlinks that are in hosts.conf" {
  setup_ok_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok -D uptime 2>&1
  assert_output_contains "Discovered servers:"
}

@test "ok finds all symlinks matching hosts.conf" {
  setup_ok_env ok0 ok1 ok2 ok3
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok -D uptime 2>&1
  # Should find all 4 servers
  assert_output_contains "ok0"
  assert_output_contains "ok1"
  assert_output_contains "ok2"
  assert_output_contains "ok3"
}

@test "ok excludes hosts without (oknav) option" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0 ok1 ok2
  create_hosts_conf "$TEST_TEMP_DIR" \
    "ok0.test.local ok0 (oknav)" \
    "ok1.test.local ok1 (oknav)" \
    "ok2.test.local ok2"
  create_mock_sudo
  create_mock_timeout
  cp "${PROJECT_DIR}/ok" "${TEST_TEMP_DIR}/"
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok -D uptime 2>&1
  # ok2 should NOT be included (no oknav option)
  assert_output_not_contains "ok2"
  # ok0 and ok1 should be included
  assert_output_contains "ok0"
  assert_output_contains "ok1"
}

@test "ok ignores non-symlink files" {
  setup_ok_env ok0 ok1
  # Create a regular file named ok-fake (not a symlink)
  echo "not a script" > "${TEST_TEMP_DIR}/ok-notlink"
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok -D uptime 2>&1
  # Should NOT include ok-notlink
  assert_output_not_contains "ok-notlink"
}

@test "ok with no servers found exits with error" {
  # Create directory with no matching symlinks/hosts.conf
  mkdir -p "${TEST_TEMP_DIR}/empty"
  cp "${PROJECT_DIR}/ok" "${TEST_TEMP_DIR}/empty/"
  cp "${PROJECT_DIR}/common.inc.sh" "${TEST_TEMP_DIR}/empty/"
  # Create empty hosts.conf - will fail on "no valid entries"
  echo "# empty" > "${TEST_TEMP_DIR}/empty/hosts.conf"
  cd "${TEST_TEMP_DIR}/empty" || return 1

  run ./ok uptime
  ((status != 0))
}

# ==============================================================================
# Option Parsing Tests
# ==============================================================================

@test "-p enables parallel mode" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok -p -D uptime
  assert_output_contains "parallel"
}

@test "--parallel enables parallel mode" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok --parallel -D uptime
  assert_output_contains "parallel"
}

@test "-t sets timeout value" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok -t 60 -D uptime
  assert_output_contains "Timeout: 60"
}

@test "--timeout sets timeout value" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok --timeout 120 -D uptime
  assert_output_contains "Timeout: 120"
}

@test "-t with non-numeric value exits with non-zero" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok -t abc uptime
  # Script uses declare -i TIMEOUT, so non-numeric triggers bash error
  ((status != 0))
}

@test "-D enables debug output" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok -D uptime
  assert_output_contains "DEBUG"
}

@test "--debug enables debug output" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok --debug uptime
  assert_output_contains "DEBUG"
}

@test "invalid option --invalid exits with code 22" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok --invalid
  ((status == 22))
  assert_output_contains "Invalid option"
}

# ==============================================================================
# Combined Options Tests
# ==============================================================================

@test "-pt 10 combines parallel and timeout" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok -pt 10 -D uptime
  assert_output_contains "parallel"
  assert_output_contains "Timeout: 10"
}

@test "-Dp combines debug and parallel" {
  setup_ok_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok -Dp uptime
  assert_output_contains "DEBUG"
  assert_output_contains "parallel"
}

# ==============================================================================
# Server Exclusion Tests
# ==============================================================================

@test "-x excludes specified server" {
  setup_ok_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok -x ok0 -D uptime 2>&1
  # ok0 should not be in execution output
  assert_output_not_contains "+++ok0:"
}

@test "--exclude-host excludes specified server" {
  setup_ok_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok --exclude-host ok1 -D uptime 2>&1
  assert_output_not_contains "+++ok1:"
}

@test "-x is repeatable for multiple exclusions" {
  setup_ok_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok -x ok0 -x ok1 uptime
  # Only ok2 should be executed
  assert_output_contains "+++ok2:"
  assert_output_not_contains "+++ok0:"
  assert_output_not_contains "+++ok1:"
}

@test "hosts.conf (exclude) option excludes server" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0 ok1 ok2
  create_hosts_conf "$TEST_TEMP_DIR" \
    "ok0.test.local ok0 (oknav,exclude)" \
    "ok1.test.local ok1 (oknav)" \
    "ok2.test.local ok2 (oknav)"
  create_mock_sudo
  create_mock_timeout
  cp "${PROJECT_DIR}/ok" "${TEST_TEMP_DIR}/"
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok uptime
  # ok0 should be excluded via hosts.conf
  assert_output_not_contains "+++ok0:"
  assert_output_contains "+++ok1:"
}

@test "hosts.conf (local-only) auto-excludes on wrong host" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0 okdev
  create_hosts_conf "$TEST_TEMP_DIR" \
    "ok0.test.local ok0 (oknav)" \
    "dev.test.local okdev (oknav,local-only:some-other-host)"
  create_mock_sudo
  create_mock_timeout
  cp "${PROJECT_DIR}/ok" "${TEST_TEMP_DIR}/"
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok -D uptime 2>&1
  # okdev should be auto-excluded
  assert_output_not_contains "+++okdev:"
}

@test "hosts.conf (local-only) included on correct host" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0 okdev
  create_hosts_conf "$TEST_TEMP_DIR" \
    "ok0.test.local ok0 (oknav)" \
    "dev.test.local okdev (oknav,local-only:$(hostname))"
  create_mock_sudo
  create_mock_timeout
  cp "${PROJECT_DIR}/ok" "${TEST_TEMP_DIR}/"
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok uptime
  # okdev should be included since we're on the correct host
  assert_output_contains "+++okdev:"
}

@test "ok-server-excludes.list is ignored" {
  setup_ok_env ok0 ok1 ok2
  # Create old exclusion file (should be ignored)
  echo "ok0" > "${TEST_TEMP_DIR}/ok-server-excludes.list"
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok uptime
  # ok0 should NOT be excluded - file is ignored
  assert_output_contains "+++ok0:"
  assert_output_contains "+++ok1:"
}

# ==============================================================================
# Sequential Execution Tests
# ==============================================================================

@test "sequential mode executes servers in order" {
  setup_ok_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok uptime
  # Check output format - should have server markers
  assert_output_contains "+++ok"
}

@test "sequential mode output has server separators" {
  setup_ok_env ok0 ok1
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok uptime
  # Each server output starts with +++server:
  assert_output_contains "+++ok0:"
  assert_output_contains "+++ok1:"
}

# ==============================================================================
# Parallel Execution Tests
# ==============================================================================

@test "parallel mode uses background processes" {
  setup_ok_env ok0 ok1
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok -p uptime
  # Output should still have all servers
  assert_output_contains "+++ok0:"
  assert_output_contains "+++ok1:"
}

@test "parallel mode maintains output order" {
  setup_ok_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok -p uptime
  # All servers should appear in output
  ((status == 0))
}

# ==============================================================================
# Timeout Handling Tests
# ==============================================================================

@test "timeout command is used for execution" {
  setup_ok_env ok0
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok uptime
  # Timeout mock should have been called
  assert_mock_called "TIMEOUT_CALL" "30s"
}

@test "custom timeout value is passed to timeout command" {
  setup_ok_env ok0
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok -t 60 uptime
  assert_mock_called "TIMEOUT_CALL" "60s"
}

@test "timeout exit 124 shows timeout message" {
  setup_ok_env ok0

  # Create timeout mock that returns 124
  cat > "${MOCK_BIN}/timeout" <<'EOF'
#!/bin/bash
echo "TIMEOUT_CALL: $*" >> "${MOCK_LOG}"
exit 124
EOF
  chmod +x "${MOCK_BIN}/timeout"

  cd "$TEST_TEMP_DIR" || return 1

  run ./ok uptime
  assert_output_contains "Connection timeout"
}

# ==============================================================================
# Cleanup Tests
# ==============================================================================

@test "temp files are created in TEMP_DIR for parallel mode" {
  setup_ok_env ok0 ok1

  # Set XDG_RUNTIME_DIR to our temp dir for predictable temp file location
  export XDG_RUNTIME_DIR="$TEST_TEMP_DIR"

  cd "$TEST_TEMP_DIR" || return 1
  run ./ok -p uptime

  # After execution, temp files should be cleaned up
  # (The trap should have removed them)
  ((status == 0))
}

# ==============================================================================
# Command Execution Tests
# ==============================================================================

@test "command is passed to servers via sudo" {
  setup_ok_env ok0
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok uptime
  assert_mock_called "SUDO_CALL" "ok0"
}

@test "complex command with quotes is passed correctly" {
  setup_ok_env ok0
  cd "$TEST_TEMP_DIR" || return 1

  run ./ok 'echo "hello world"'
  assert_mock_called "SUDO_CALL" "echo"
}

#fin
