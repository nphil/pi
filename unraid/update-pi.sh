#!/bin/bash
# Auto-update PI on Unraid. Runs from User Scripts on a daily cron.
# Pulls ghcr.io/nphil/pi:latest; if the digest moved, recreates the container
# with the canonical arguments (kept in sync with unraid/my-PI.xml — dockerMan
# recreation uses only the XML, this script must match it).
set -euo pipefail

IMAGE="ghcr.io/nphil/pi:latest"
NAME="PI"

current=$(docker inspect --format '{{.Image}}' "$NAME" 2>/dev/null || echo none)
docker pull "$IMAGE" >/dev/null
latest=$(docker image inspect --format '{{.Id}}' "$IMAGE")

if [ "$current" = "$latest" ]; then
  echo "PI is current ($latest)"
  exit 0
fi

echo "Updating PI: $current -> $latest"
docker stop "$NAME" >/dev/null 2>&1 || true
docker rm "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart unless-stopped \
  -p 8504:8504 \
  -e TZ=America/New_York \
  -e HOST_OS=Unraid -e HOST_HOSTNAME=BeastNAS -e HOST_CONTAINERNAME=PI \
  -l net.unraid.docker.managed=dockerman \
  -l 'net.unraid.docker.webui=http://[IP]:[PORT:8504]/' \
  -l 'net.unraid.docker.icon=http://192.168.1.69:3009/appicons/pi-web.png' \
  -v /mnt/nvme/appdata/pi:/data \
  "$IMAGE" >/dev/null

docker image prune -f --filter "label=org.opencontainers.image.source=https://github.com/nphil/pi" >/dev/null 2>&1 || true

/usr/local/emhttp/webGui/scripts/notify -e "PI updated" \
  -d "PI (pi + pi-web) updated to the latest GHCR image." -i normal || true
echo "PI updated to $latest"
