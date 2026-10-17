#!/bin/bash
# Report healthy when the panel web server answers on its configured port.
# The login page lives behind the security entrance, so /login is often 404
# until the entrance path is used. Any completed HTTP response means the
# process is accepting connections.

set -euo pipefail

port_file="/www/server/panel/data/port.pl"
port="${AAPANEL_PORT:-8888}"

if [ -s "$port_file" ]; then
  port="$(tr -d '[:space:]' <"$port_file")"
fi

http_code() {
  local scheme="$1"
  curl -sk -o /dev/null -w '%{http_code}' --max-time 4 \
    "${scheme}://127.0.0.1:${port}/login" || true
}

code="$(http_code http)"
if [ -z "$code" ] || [ "$code" = "000" ]; then
  code="$(http_code https)"
fi

case "$code" in
  200 | 201 | 204 | 301 | 302 | 303 | 307 | 308 | 401 | 403 | 404)
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
