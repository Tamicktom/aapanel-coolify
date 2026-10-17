#!/bin/bash
# Behavioral checks for the panel configuration helpers.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/scripts/lib.sh"

FAILURES=0

describe() {
  printf '\n%s\n' "$1"
}

it() {
  printf '  it %s\n' "$1"
}

pass() {
  it "$1"
}

fail() {
  it "$1"
  printf '    failed: %s\n' "$2"
  FAILURES=$((FAILURES + 1))
}

expect_success() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name" "command failed"
  fi
}

expect_failure() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$name" "command succeeded"
  else
    pass "$name"
  fi
}

expect_output() {
  local name="$1"
  local expected="$2"
  shift 2
  local actual=""
  actual="$("$@" 2>/dev/null || true)"
  if [ "$actual" = "$expected" ]; then
    pass "$name"
  else
    fail "$name" "expected ${expected}, got ${actual}"
  fi
}

describe "panel configuration"
describe "validate_port"
expect_success "accepts the default panel port" validate_port 8888
expect_success "accepts the highest TCP port" validate_port 65535
expect_failure "rejects port 0" validate_port 0
expect_failure "rejects a port above 65535" validate_port 70000
expect_failure "rejects a word as a port" validate_port panel

describe "validate_username"
expect_success "accepts a normal username" validate_username paneladmin
expect_failure "rejects a username shorter than 3 characters" validate_username ab
expect_failure "rejects the username admin" validate_username admin
expect_failure "rejects the username root" validate_username root
expect_failure "rejects a username with a hyphen" validate_username panel-admin

describe "validate_password"
expect_success "accepts a letter and number password" validate_password PanelPass123
expect_failure "rejects a password shorter than 8 characters" validate_password short1
expect_failure "rejects a password with a hyphen" validate_password panel-password
expect_failure "rejects a password with a space" validate_password "panel password"

describe "normalize_entry"
expect_output "adds a leading slash" "/panelentry" normalize_entry panelentry
expect_output "keeps a valid entrance" "/panelentry" normalize_entry /panelentry
expect_failure "rejects an entrance shorter than 6 characters" normalize_entry /abcd
expect_failure "rejects the reserved entrance /login" normalize_entry /login
expect_failure "rejects the reserved entrance /panel" normalize_entry /panel
expect_failure "rejects an entrance with a space" normalize_entry "/panel entry"

describe "generate_token"
token="$(generate_token 20)"
if [[ "$token" =~ ^[A-Za-z0-9]{20}$ ]]; then
  pass "returns 20 letters and digits"
else
  fail "returns 20 letters and digits" "got ${token}"
fi

describe "ssl_requested"
if ssl_requested off; then
  fail "treats off as disabled" "returned success"
else
  pass "treats off as disabled"
fi
if ssl_requested on; then
  pass "treats on as enabled"
else
  fail "treats on as enabled" "returned failure"
fi
if ssl_requested maybe; then
  fail "rejects an unknown SSL value" "returned success"
else
  status=$?
  if [ "$status" -eq 2 ]; then
    pass "rejects an unknown SSL value"
  else
    fail "rejects an unknown SSL value" "status ${status}"
  fi
fi

printf '\n'
if [ "$FAILURES" -gt 0 ]; then
  printf '%s failed\n' "$FAILURES"
  exit 1
fi

printf 'all panel configuration checks passed\n'
