#!/bin/sh
set -eu

: "${PLATFORM_DOMAIN:?PLATFORM_DOMAIN is required}"
: "${PLATFORM_PROTOCOL:?PLATFORM_PROTOCOL is required}"

template=/usr/share/landing/index.html.example
html_dir=/usr/share/nginx/html

escape_for_sed() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

sed \
    -e "s|{{PROTOCOL}}|$(escape_for_sed "$PLATFORM_PROTOCOL")|g" \
    -e "s|{{DOMAIN}}|$(escape_for_sed "$PLATFORM_DOMAIN")|g" \
    -e "s|{{SMB_NAME}}|$(escape_for_sed "${SMB_NAME:-}")|g" \
    -e "s|{{SUBDOMAIN_PREFIX}}|$(escape_for_sed "${SUBDOMAIN_PREFIX:-}")|g" \
    -e "s|{{OIDC_LOGOUT_URI}}|$(escape_for_sed "${OIDC_LOGOUT_URI:-}")|g" \
    -e "s|{{OIDC_CLIENT_ID}}|$(escape_for_sed "${OIDC_CLIENT_ID:-}")|g" \
    "$template" > "$html_dir/index.html.tmp"

mv "$html_dir/index.html.tmp" "$html_dir/index.html"
