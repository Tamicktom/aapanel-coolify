#!/bin/bash
# Shared checks for the aaPanel container configuration.
# This file only defines functions. Callers decide shell options.

#* Reserved entrances
# aaPanel rejects these security-entrance paths and rewrites them.
AAPANEL_RESERVED_ENTRIES="
/
/san
/bak
/monitor
/abnormal
/close
/task
/login
/config
/site
/sites
/ftp
/public
/database
/data
/download_file
/control
/crontab
/firewall
/files
/soft
/ajax
/system
/panel_data
/code
/ssl
/plugin
/wxapp
/hook
/safe
/yield
/downloadApi
/pluginApi
/auth
/download
/cloud
/webssh
/connect_event
/panel
/acme
/down
/api
/tips
/message
/warning
/userRegister
/userLang
/docker
/btdocker
/breaking_through
"

#* Token generation
# Prints one line of letters and digits. aaPanel rejects other password characters.
generate_token() {
  local length="$1"
  local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  local token=""
  local index=""
  local max="${#alphabet}"

  if ! [[ "$length" =~ ^[0-9]+$ ]] || [ "$length" -lt 1 ]; then
    echo "token length must be a positive number" >&2
    return 1
  fi

  while [ "${#token}" -lt "$length" ]; do
    index="$(od -An -N2 -tu2 /dev/urandom | tr -d '[:space:]')"
    index=$((index % max))
    token="${token}${alphabet:index:1}"
  done

  printf '%s\n' "$token"
}

#* Port
validate_port() {
  local port="$1"

  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    echo "AAPANEL_PORT must be a number from 1 to 65535" >&2
    return 1
  fi

  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "AAPANEL_PORT must be a number from 1 to 65535" >&2
    return 1
  fi
}

#* Username
validate_username() {
  local username="$1"

  if ! [[ "$username" =~ ^[A-Za-z0-9_.,]{3,32}$ ]]; then
    echo "AAPANEL_USERNAME must be 3 to 32 characters and use only letters, numbers, underscore, comma, or period" >&2
    return 1
  fi

  if [ "$username" = "admin" ] || [ "$username" = "root" ]; then
    echo "AAPANEL_USERNAME cannot be admin or root" >&2
    return 1
  fi
}

#* Password
validate_password() {
  local password="$1"

  if ! [[ "$password" =~ ^[A-Za-z0-9_.,]{8,64}$ ]]; then
    echo "AAPANEL_PASSWORD must be 8 to 64 characters and use only letters, numbers, underscore, comma, or period" >&2
    return 1
  fi
}

#* Security entrance
normalize_entry() {
  local entry="$1"
  local reserved=""

  entry="${entry#"${entry%%[![:space:]]*}"}"
  entry="${entry%"${entry##*[![:space:]]}"}"

  if [ -z "$entry" ]; then
    echo "AAPANEL_ENTRY cannot be empty" >&2
    return 1
  fi

  if [ "${entry#/}" = "$entry" ]; then
    entry="/${entry}"
  fi

  while [ "${entry%/}" != "$entry" ] && [ "$entry" != "/" ]; do
    entry="${entry%/}"
  done

  if ! [[ "$entry" =~ ^/[A-Za-z0-9_-]{6,32}$ ]]; then
    echo "AAPANEL_ENTRY must start with / and then use 6 to 32 letters, numbers, underscore, or hyphen" >&2
    return 1
  fi

  for reserved in $AAPANEL_RESERVED_ENTRIES; do
    if [ "$entry" = "$reserved" ]; then
      echo "AAPANEL_ENTRY ${entry} is reserved by aaPanel" >&2
      return 1
    fi
  done

  printf '%s\n' "$entry"
}

#* Panel SSL switch
# Returns 0 when SSL is requested, 1 when it is off, 2 when the value is invalid.
ssl_requested() {
  local value=""
  value="$(printf '%s' "${1:-off}" | tr '[:upper:]' '[:lower:]')"

  case "$value" in
    1 | on | true | yes) return 0 ;;
    0 | off | false | no | "") return 1 ;;
    *) return 2 ;;
  esac
}
