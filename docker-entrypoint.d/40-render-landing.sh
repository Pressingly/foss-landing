#!/bin/sh
set -eu

: "${PLATFORM_DOMAIN:?PLATFORM_DOMAIN is required}"
: "${PLATFORM_PROTOCOL:?PLATFORM_PROTOCOL is required}"

template=/usr/share/landing/index.html.example
html_dir=/usr/share/nginx/html

escape_for_sed() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

require_bare_host() {
    case "$2" in
        *[!A-Za-z0-9.:-]*) echo "$1 must be a bare hostname (no scheme, path or spaces)" >&2; exit 1 ;;
    esac
}

# Dropping an unset app's tile keeps a deployment from linking to a host that does not exist.
optional_app_filter() {
    if [ -n "$2" ]; then
        printf '%s' '/<!-- \/\{0,1\}app:'"$1"' -->/d'
    else
        printf '%s' '/<!-- app:'"$1"' -->/,/<!-- \/app:'"$1"' -->/d'
    fi
}

# Empty counts as unset because compose passes `${VAR:-}` through as an empty string.
resolve_host() {
    require_bare_host "$1" "$2"
    case "$2" in
        none) printf '' ;;
        '') printf '%s' "$3" ;;
        *) printf '%s' "$2" ;;
    esac
}

outline_host=$(resolve_host OUTLINE_HOST "${OUTLINE_HOST:-}" "docs.$PLATFORM_DOMAIN")
plane_host=$(resolve_host PLANE_HOST "${PLANE_HOST:-}" "pm.$PLATFORM_DOMAIN")
penpot_host=$(resolve_host PENPOT_HOST "${PENPOT_HOST:-}" "design.$PLATFORM_DOMAIN")
twenty_host=$(resolve_host TWENTY_HOST "${TWENTY_HOST:-}" "twenty.$PLATFORM_DOMAIN")
zammad_host=$(resolve_host ZAMMAD_HOST "${ZAMMAD_HOST:-}" "support.$PLATFORM_DOMAIN")
chatwoot_host=$(resolve_host CHATWOOT_HOST "${CHATWOOT_HOST:-}" "")
mautic_host=$(resolve_host MAUTIC_HOST "${MAUTIC_HOST:-}" "")
erpnext_host=$(resolve_host ERPNEXT_HOST "${ERPNEXT_HOST:-}" "")
hrms_host=$(resolve_host HRMS_HOST "${HRMS_HOST:-}" "")
frappe_crm_host=$(resolve_host FRAPPE_CRM_HOST "${FRAPPE_CRM_HOST:-}" "")
raven_host=$(resolve_host RAVEN_HOST "${RAVEN_HOST:-}" "")
zulip_host=$(resolve_host ZULIP_HOST "${ZULIP_HOST:-}" "")

app_count=0
for app_host in "$outline_host" "$plane_host" "$penpot_host" "$twenty_host" "$zammad_host" \
    "$chatwoot_host" "$mautic_host" "$erpnext_host" "$hrms_host" "$frappe_crm_host" "$raven_host" "$zulip_host"; do
    if [ -n "$app_host" ]; then app_count=$((app_count + 1)); fi
done

sed \
    -e "$(optional_app_filter outline "$outline_host")" \
    -e "$(optional_app_filter plane "$plane_host")" \
    -e "$(optional_app_filter penpot "$penpot_host")" \
    -e "$(optional_app_filter twenty "$twenty_host")" \
    -e "$(optional_app_filter zammad "$zammad_host")" \
    -e "$(optional_app_filter chatwoot "$chatwoot_host")" \
    -e "$(optional_app_filter mautic "$mautic_host")" \
    -e "$(optional_app_filter erpnext "$erpnext_host")" \
    -e "$(optional_app_filter hrms "$hrms_host")" \
    -e "$(optional_app_filter crm-frappe "$frappe_crm_host")" \
    -e "$(optional_app_filter raven "$raven_host")" \
    -e "$(optional_app_filter zulip "$zulip_host")" \
    -e "s|{{PROTOCOL}}|$(escape_for_sed "$PLATFORM_PROTOCOL")|g" \
    -e "s|{{DOMAIN}}|$(escape_for_sed "$PLATFORM_DOMAIN")|g" \
    -e "s|{{SMB_NAME}}|$(escape_for_sed "${SMB_NAME:-}")|g" \
    -e "s|{{SUBDOMAIN_PREFIX}}|$(escape_for_sed "${SUBDOMAIN_PREFIX:-}")|g" \
    -e "s|{{OIDC_LOGOUT_URI}}|$(escape_for_sed "${OIDC_LOGOUT_URI:-}")|g" \
    -e "s|{{OIDC_CLIENT_ID}}|$(escape_for_sed "${OIDC_CLIENT_ID:-}")|g" \
    -e "s|{{OUTLINE_HOST}}|$(escape_for_sed "$outline_host")|g" \
    -e "s|{{PLANE_HOST}}|$(escape_for_sed "$plane_host")|g" \
    -e "s|{{PENPOT_HOST}}|$(escape_for_sed "$penpot_host")|g" \
    -e "s|{{TWENTY_HOST}}|$(escape_for_sed "$twenty_host")|g" \
    -e "s|{{ZAMMAD_HOST}}|$(escape_for_sed "$zammad_host")|g" \
    -e "s|{{CHATWOOT_HOST}}|$(escape_for_sed "$chatwoot_host")|g" \
    -e "s|{{MAUTIC_HOST}}|$(escape_for_sed "$mautic_host")|g" \
    -e "s|{{ERPNEXT_HOST}}|$(escape_for_sed "$erpnext_host")|g" \
    -e "s|{{HRMS_HOST}}|$(escape_for_sed "$hrms_host")|g" \
    -e "s|{{FRAPPE_CRM_HOST}}|$(escape_for_sed "$frappe_crm_host")|g" \
    -e "s|{{RAVEN_HOST}}|$(escape_for_sed "$raven_host")|g" \
    -e "s|{{ZULIP_HOST}}|$(escape_for_sed "$zulip_host")|g" \
    -e "s|{{APP_COUNT}}|$app_count|g" \
    "$template" > "$html_dir/index.html.tmp"

mv "$html_dir/index.html.tmp" "$html_dir/index.html"
