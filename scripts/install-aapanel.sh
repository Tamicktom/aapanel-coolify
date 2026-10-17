#!/bin/bash
# Install aaPanel while the image is built, then pack /www into a seed archive.
# Coolify mounts a volume on /www at runtime. An empty volume would hide files
# copied into the image, so the entrypoint unpacks this archive on first boot.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export NEEDRESTART_MODE=a

INSTALL_URL="https://www.aapanel.com/script/install_panel_en.sh"
PANEL_PORT="8888"
SEED="/opt/aapanel/www-seed.tar.gz"

echo "==> Installing base packages"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  wget \
  xz-utils \
  unzip \
  tar \
  gzip \
  procps \
  cron \
  iproute2 \
  lsof \
  locales \
  tzdata \
  openssl \
  sudo \
  sqlite3 \
  tini \
  e2fsprogs

sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 || true

if ! command -v tini >/dev/null 2>&1; then
  echo "tini is required so the container can stop child processes" >&2
  exit 1
fi

echo "==> Downloading the official aaPanel installer"
mkdir -p /tmp /opt/aapanel
curl -fL --retry 5 --retry-delay 2 -o /tmp/install_panel_en.sh "$INSTALL_URL" \
  || curl -fkL --retry 5 --retry-delay 2 -o /tmp/install_panel_en.sh "$INSTALL_URL"
chmod 755 /tmp/install_panel_en.sh

echo "==> Installing aaPanel"
set +e
timeout 45m bash /tmp/install_panel_en.sh -y --ssl-disable -P "$PANEL_PORT" \
  >/tmp/aapanel-installer.out 2>&1
install_rc=$?
set -e

if [ ! -x /www/server/panel/BT-Panel ] || [ ! -s /etc/init.d/bt ]; then
  echo "aaPanel installer failed with exit code ${install_rc}" >&2
  tail -n 200 /tmp/aapanel-installer.out >&2 || true
  exit 1
fi

echo "aaPanel installer finished (exit ${install_rc})"

python_bin="/www/server/panel/pyenv/bin/python3"
if [ ! -x "$python_bin" ]; then
  python_bin="/www/server/panel/pyenv/bin/python"
fi
if [ ! -x "$python_bin" ]; then
  echo "aaPanel Python environment is missing" >&2
  exit 1
fi

if ! grep -qx "$PANEL_PORT" /www/server/panel/data/port.pl; then
  echo "Panel port was not set to ${PANEL_PORT}" >&2
  exit 1
fi

echo "==> Stopping the installer processes"
/etc/init.d/bt stop || true
pkill -9 -f '/www/server/panel/BT-Panel' || true
pkill -9 -f '/www/server/panel/BT-Task' || true
pkill -9 -f '/www/server/panel/webserver/sbin/webserver' || true
sleep 2

if command -v ufw >/dev/null 2>&1; then
  ufw --force disable >/dev/null 2>&1 || true
fi
rm -f /www/swap
if [ -f /etc/fstab ]; then
  sed -i '\|/www/swap|d' /etc/fstab
fi

echo "==> Replacing the installer login before the seed is packed"
if command -v chattr >/dev/null 2>&1; then
  chattr -i /www/server/panel/default.pl 2>/dev/null || true
fi
rm -f \
  /www/server/panel/aliyun.pl \
  /www/server/panel/php_mysql_auto.pl \
  /www/server/panel/default.pl \
  /www/server/panel/data/iplist.txt \
  /www/server/panel/data/ssl.pl \
  /www/server/panel/data/domain.conf \
  /www/server/panel/data/limitip.conf

build_password="$(openssl rand -hex 16)"
rotate_log="$(
  cd /www/server/panel
  AAPANEL_PASSWORD="$build_password" "$python_bin" -c 'import os, tools; tools.set_panel_pwd(os.environ["AAPANEL_PASSWORD"])'
)"
if printf '%s\n' "$rotate_log" | grep -q 'Error:'; then
  echo "$rotate_log" >&2
  exit 1
fi
unset build_password
rm -f /www/server/panel/default.pl
printf '%s\n' '/initialize' >/www/server/panel/data/admin_path.pl
chmod 600 /www/server/panel/data/admin_path.pl

# Docker networks often have no IPv6. Drop those listeners before packaging.
ipv6_file=""
for ipv6_file in \
  /www/server/panel/webserver/tpls/webserver_listen.conf \
  /www/server/panel/webserver/tpls/webserver_listen_ssl.conf \
  /www/server/panel/class/webserver.py
do
  if [ -f "$ipv6_file" ]; then
    sed -i '/\[::\]/d' "$ipv6_file"
  fi
done

rm -rf /www/server/panel/logs/* /www/server/panel/temp/* /tmp/panel.sock || true
mkdir -p /www/server/panel/logs

echo "==> Packing /www"
rm -rf /opt/aapanel/stage
mkdir -p /opt/aapanel/stage
cp -a /www /opt/aapanel/stage/www
rm -rf /www
tar czf "$SEED" \
  --exclude='www/swap' \
  --exclude='www/server/panel/logs/*' \
  -C /opt/aapanel/stage www
rm -rf /opt/aapanel/stage

set +e
set +o pipefail
tar tzf "$SEED" | grep -q 'www/server/panel/BT-Panel'
list_rc=$?
set -o pipefail
set -e
if [ "$list_rc" -ne 0 ]; then
  echo "seed archive is missing the panel" >&2
  exit 1
fi

rm -f /tmp/install_panel_en.sh /tmp/aapanel-install.log /tmp/aapanel-installer.out
apt-get clean
rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/*

echo "==> Seed archive: $(du -h "$SEED" | awk '{print $1}')"
