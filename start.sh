#!/usr/bin/env bash
# Starts everything Explainly needs, in the right order:
# the database and the AI model (Docker), then the server.
# If an old server is still running, it is stopped first.
cd "$(dirname "$0")"

docker compose up -d

old=$(ss -ltnp 2>/dev/null | grep ':8000 ' | grep -oP 'pid=\K[0-9]+' | head -1)
if [ -n "$old" ]; then
  echo "Stopping the old server (process $old)"
  kill "$old"
  sleep 2
fi

echo
echo "Open the app in the browser:  http://localhost:8000"
echo
exec .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
