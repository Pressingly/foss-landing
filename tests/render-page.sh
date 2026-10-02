#!/bin/sh
set -eu

image=${1:?usage: render-page.sh <image> <env-file>}
env_file=${2:?usage: render-page.sh <image> <env-file>}

docker run --rm --env-file "$env_file" --entrypoint sh "$image" \
    -c '/docker-entrypoint.d/40-render-landing.sh && cat /usr/share/nginx/html/index.html'
