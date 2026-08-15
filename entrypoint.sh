#!/bin/bash
# One container, both pi-web processes: the session daemon keeps agent runs
# alive across browser disconnects, the web server fronts it. tini is PID 1;
# if either process dies we exit so the restart policy brings both back.
set -e

mkdir -p /data/home /data/config /data/pi-web /data/pi-agent /data/workspace

# A hard kill can leave a stale daemon socket behind.
rm -f "${PI_WEB_SESSIOND_SOCKET:-/data/pi-web/sessiond.sock}" 2>/dev/null || true

pi-web-sessiond &
SESSIOND_PID=$!

trap 'kill -TERM $SESSIOND_PID $SERVER_PID 2>/dev/null; wait' TERM INT

# Wait for the daemon socket rather than sleeping blind.
for _ in $(seq 1 50); do
  [ -S "${PI_WEB_SESSIOND_SOCKET:-/data/pi-web/sessiond.sock}" ] && break
  sleep 0.2
done

pi-web-server &
SERVER_PID=$!

wait -n
kill -TERM $SESSIOND_PID $SERVER_PID 2>/dev/null || true
exit 1
