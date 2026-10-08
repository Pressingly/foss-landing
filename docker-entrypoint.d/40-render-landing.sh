#!/bin/sh
set -eu

: "${PLATFORM_DOMAIN:?PLATFORM_DOMAIN is required}"
: "${PLATFORM_PROTOCOL:?PLATFORM_PROTOCOL is required}"

template=/usr/share/landing/index.html.example
html_dir=/usr/share/nginx/html

escape_for_sed() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# An optional app's tile and pill sit between <!-- app:NAME --> markers and are
# dropped when its host variable is empty, so a deployment without the app never
# links to a host that does not exist.
optional_app_filter() {
    if [ -n "$2" ]; then
        printf '%s' '/<!-- \/\{0,1\}app:'"$1"' -->/d'
    else
        printf '%s' '/<!-- app:'"$1"' -->/,/<!-- \/app:'"$1"' -->/d'
    fi
}

sed \
    -e "$(optional_app_filter mautic "${MAUTIC_HOST:-}")" \
    -e "s|{{PROTOCOL}}|$(escape_for_sed "$PLATFORM_PROTOCOL")|g" \
    -e "s|{{DOMAIN}}|$(escape_for_sed "$PLATFORM_DOMAIN")|g" \
    -e "s|{{SMB_NAME}}|$(escape_for_sed "${SMB_NAME:-}")|g" \
    -e "s|{{SUBDOMAIN_PREFIX}}|$(escape_for_sed "${SUBDOMAIN_PREFIX:-}")|g" \
    -e "s|{{OIDC_LOGOUT_URI}}|$(escape_for_sed "${OIDC_LOGOUT_URI:-}")|g" \
    -e "s|{{OIDC_CLIENT_ID}}|$(escape_for_sed "${OIDC_CLIENT_ID:-}")|g" \
    -e "s|{{MAUTIC_HOST}}|$(escape_for_sed "${MAUTIC_HOST:-}")|g" \
    "$template" > "$html_dir/index.html.tmp"

mv "$html_dir/index.html.tmp" "$html_dir/index.html"
