#!/bin/bash
# Start aaPanel as the container's main process.
# A volume mounted at /www hides the install baked into the image, so the
# first boot unpacks a seed archive and then applies the Coolify environment.

set -euo pipefail

#* Paths
PANEL_DIR="/www/server/panel"
SEED="/opt/aapanel/www-seed.tar.gz"
MARKER="/www/.aapanel-initialized"
CREDENTIALS="/www/.aapanel-credentials"

# shellcheck disable=SC1091
source /opt/aapanel/lib.sh

log() {
  printf '[aapanel] %s\n' "$*"
}

panel_python() {
  if [ -x "${PANEL_DIR}/pyenv/bin/python3" ]; then
    printf '%s\n' "${PANEL_DIR}/pyenv/bin/python3"
    return 0
  fi
  if [ -x "${PANEL_DIR}/pyenv/bin/python" ]; then
    printf '%s\n' "${PANEL_DIR}/pyenv/bin/python"
    return 0
  fi
  echo "aaPanel Python was not found in ${PANEL_DIR}/pyenv" >&2
  return 1
}

panel_running() {
  local process=""
  local cmdline=""

  # The panel is a Python script, so the process command starts with the
  # interpreter path and only contains BT-Panel as an argument.
  for process in /proc/[0-9]*; do
    if [ ! -r "${process}/cmdline" ]; then
      continue
    fi
    cmdline="$(tr '\0' ' ' <"${process}/cmdline" 2>/dev/null || printf '')"
    case "$cmdline" in
      *BT-Panel*)
        return 0
        ;;
    esac
  done

  return 1
}

stop_panel() {
  if [ -x /etc/init.d/bt ]; then
    /etc/init.d/bt stop || true
  fi
}

prepare_timezone() {
  local zone="${TZ:-UTC}"
  if [ -f "/usr/share/zoneinfo/${zone}" ]; then
    ln -sfn "/usr/share/zoneinfo/${zone}" /etc/localtime
    printf '%s\n' "$zone" >/etc/timezone
  fi
}

seed_panel() {
  if [ -x "${PANEL_DIR}/BT-Panel" ]; then
    return 0
  fi

  if [ ! -s "$SEED" ]; then
    log "panel files are missing and the seed archive was not found"
    exit 1
  fi

  log "preparing /www from the image seed"
  mkdir -p /www
  tar xzf "$SEED" -C /
}

ensure_runtime_user() {
  if id www >/dev/null 2>&1; then
    return 0
  fi
  groupadd www
  useradd --system --gid www --shell /usr/sbin/nologin www
}

strip_ipv6_listeners() {
  local file=""
  for file in \
    "${PANEL_DIR}/webserver/tpls/webserver_listen.conf" \
    "${PANEL_DIR}/webserver/tpls/webserver_listen_ssl.conf" \
    "${PANEL_DIR}/webserver/conf/webserver.conf" \
    "${PANEL_DIR}/class/webserver.py"
  do
    if [ -f "$file" ]; then
      sed -i '/\[::\]/d' "$file"
    fi
  done
}

apply_port() {
  local port="$1"
  mkdir -p "${PANEL_DIR}/data"
  printf '%s\n' "$port" >"${PANEL_DIR}/data/port.pl"
}

apply_ssl() {
  local mode="$1"
  local python=""
  python="$(panel_python)"

  if [ "$mode" = "on" ]; then
    if [ ! -s "${PANEL_DIR}/ssl/certificate.pem" ] || [ ! -s "${PANEL_DIR}/ssl/privateKey.pem" ]; then
      log "creating a panel certificate"
      (
        cd "$PANEL_DIR"
        "$python" tools.py ssl
      ) || true
    fi
    if [ -s "${PANEL_DIR}/ssl/certificate.pem" ] && [ -s "${PANEL_DIR}/ssl/privateKey.pem" ]; then
      printf 'True\n' >"${PANEL_DIR}/data/ssl.pl"
      return 0
    fi
    rm -f "${PANEL_DIR}/data/ssl.pl"
    log "panel certificate was not created, so the panel stays on HTTP"
    return 0
  fi

  rm -f "${PANEL_DIR}/data/ssl.pl"
}

configure_first_run() {
  local username=""
  local password=""
  local entry=""
  local python=""
  local password_output=""
  local username_output=""

  if [ -n "${AAPANEL_USERNAME:-}" ]; then
    username="$AAPANEL_USERNAME"
  else
    username="panel$(generate_token 6 | tr '[:upper:]' '[:lower:]')"
  fi

  if [ -n "${AAPANEL_PASSWORD:-}" ]; then
    password="$AAPANEL_PASSWORD"
  else
    password="$(generate_token 20)"
  fi

  if [ -n "${AAPANEL_ENTRY:-}" ]; then
    entry="$(normalize_entry "$AAPANEL_ENTRY")"
  else
    entry="/$(generate_token 10 | tr '[:upper:]' '[:lower:]')"
  fi

  validate_username "$username"
  validate_password "$password"

  python="$(panel_python)"
  log "writing the initial panel login"

  password_output="$(
    cd "$PANEL_DIR"
    AAPANEL_PASSWORD="$password" "$python" -c 'import os, tools; tools.set_panel_pwd(os.environ["AAPANEL_PASSWORD"])'
  )"
  if printf '%s\n' "$password_output" | grep -q 'Error:'; then
    log "$password_output"
    exit 1
  fi

  username_output="$(
    cd "$PANEL_DIR"
    AAPANEL_USERNAME="$username" "$python" -c 'import os, tools; tools.set_panel_username(os.environ["AAPANEL_USERNAME"])'
  )"
  if printf '%s\n' "$username_output" | grep -q 'Error:'; then
    log "$username_output"
    exit 1
  fi

  printf '%s\n' "$entry" >"${PANEL_DIR}/data/admin_path.pl"
  chmod 600 "${PANEL_DIR}/data/admin_path.pl"

  set +e
  ssl_requested "${AAPANEL_SSL:-off}"
  ssl_status=$?
  set -e
  case "$ssl_status" in
    0) apply_ssl on ;;
    1) apply_ssl off ;;
    *)
      log "AAPANEL_SSL must be on or off"
      exit 1
      ;;
  esac

  umask 077
  cat >"$CREDENTIALS" <<EOF
username: ${username}
password: ${password}
entrance: ${entry}
port: ${AAPANEL_PORT:-8888}
EOF
  chmod 600 "$CREDENTIALS"
  printf '%s\n' "$password" >"${PANEL_DIR}/default.pl"
  chmod 600 "${PANEL_DIR}/default.pl"
  touch "$MARKER"
  log "saved the initial login to ${CREDENTIALS}"
}

print_login() {
  local port="$1"
  local entry=""
  local username=""
  local scheme="http"

  entry="$(tr -d '[:space:]' <"${PANEL_DIR}/data/admin_path.pl" 2>/dev/null || true)"
  username="$(awk -F ': ' '/^username: / { print $2 }' "$CREDENTIALS" 2>/dev/null || true)"
  if [ -f "${PANEL_DIR}/data/ssl.pl" ]; then
    scheme="https"
  fi

  if [ ! -f "$MARKER" ]; then
    return 0
  fi

  cat <<EOF

============================================================
aaPanel is ready.
Open the security entrance below. The site root hides the login page.

  ${scheme}://<your-domain>:${port}${entry}

Username: ${username}
The password is stored in ${CREDENTIALS}
Inside this container, run: bt default
============================================================

EOF

  if [ -f "$CREDENTIALS" ] && [ ! -f /www/.aapanel-credentials-printed ]; then
    awk -F ': ' '/^password: / { printf "Password: %s\n", $2 }' "$CREDENTIALS"
    touch /www/.aapanel-credentials-printed
  fi
}

wait_until_ready() {
  local attempt=0

  while [ "$attempt" -lt 60 ]; do
    attempt=$((attempt + 1))
    if /opt/aapanel/healthcheck.sh; then
      return 0
    fi
    sleep 2
  done

  log "the panel did not accept connections"
  if [ -f "${PANEL_DIR}/logs/error.log" ]; then
    tail -n 80 "${PANEL_DIR}/logs/error.log" || true
  fi
  return 1
}

start_cron() {
  if [ -x /usr/sbin/cron ]; then
    /usr/sbin/cron || true
  fi
}

on_stop() {
  log "stopping aaPanel"
  stop_panel
  exit 0
}

main() {
  local port="${AAPANEL_PORT:-8888}"

  validate_port "$port"
  prepare_timezone
  seed_panel
  ensure_runtime_user

  mkdir -p \
    /www/wwwroot \
    /www/wwwlogs \
    /www/backup/database \
    /www/backup/site \
    "${PANEL_DIR}/logs" \
    "${PANEL_DIR}/data" \
    /tmp

  rm -f "${PANEL_DIR}/aliyun.pl" "${PANEL_DIR}/php_mysql_auto.pl"
  if command -v chattr >/dev/null 2>&1; then
    chattr -i "${PANEL_DIR}/default.pl" 2>/dev/null || true
  fi

  if [ ! -f "$MARKER" ]; then
    configure_first_run
  fi

  apply_port "$port"
  strip_ipv6_listeners
  start_cron

  trap on_stop SIGTERM SIGINT

  log "starting aaPanel on port ${port}"
  /etc/init.d/bt start || true
  if ! wait_until_ready; then
    log "aaPanel failed to start"
    exit 1
  fi

  print_login "$port"
  log "aaPanel is running"

  while true; do
    if ! panel_running; then
      log "aaPanel stopped; starting it again"
      /etc/init.d/bt start || true
    fi
    sleep 15 &
    wait $! || true
  done
}

main "$@"
