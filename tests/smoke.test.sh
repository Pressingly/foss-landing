#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: smoke.test.sh <image>}
port=${SMOKE_PORT:-8080}
fixtures=$(cd "$(dirname "$0")/fixtures" && pwd)
container=$(docker run -d -p "127.0.0.1:$port:80" --env-file "$fixtures/sample.env" "$image")
body=$(mktemp)

cleanup() {
    local status=$?
    [[ $status -eq 0 ]] || docker logs "$container" >&2 || true
    docker rm -f "$container" >/dev/null
    rm -f "$body"
    exit "$status"
}
trap cleanup EXIT

url="http://127.0.0.1:$port/"
for _ in $(seq 1 30); do
    curl -fsS -o /dev/null "$url" 2>/dev/null && break
    sleep 1
done

status=$(curl -sS -o "$body" -w '%{http_code}' "$url")
[[ $status == 200 ]] || { echo "FAIL GET / returned $status"; exit 1; }
echo "ok   GET / returned 200"

grep -qF 'href="https://docs.example.test"' "$body" || { echo "FAIL page is not the rendered portal"; exit 1; }
echo "ok   GET / serves the rendered portal"

! grep -q '{{' "$body" || { echo "FAIL served page still has {{...}} placeholders"; exit 1; }
echo "ok   served page has no placeholders"
