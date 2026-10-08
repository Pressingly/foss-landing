#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: render.test.sh <image>}
fixtures=$(cd "$(dirname "$0")/fixtures" && pwd)
failures=0
timeout_cmd=$(command -v timeout || command -v gtimeout || { echo "timeout (coreutils) is required" >&2; exit 1; })

check() {
    local name=$1
    shift
    if "$@"; then
        echo "ok   $name"
    else
        echo "FAIL $name"
        failures=$((failures + 1))
    fi
}

page=$("$(dirname "$0")/render-page.sh" "$image" "$fixtures/sample.env")

page_contains() { grep -qF -- "$1" <<<"$page"; }
not_page_contains() { ! page_contains "$1"; }
no_placeholders_left() { ! grep -q '{{' <<<"$page"; }
app_card_count_is() { [[ $(grep -c 'class="app-card ' <<<"$page") -eq $1 ]]; }
cards_in_order() {
    local order
    order=$(grep -o 'class="app-card card-[a-z]*"' <<<"$page" | sed 's/.*card-\([a-z]*\)"/card-\1/' | tr '\n' ' ')
    [[ "$order" == *"$1 $2 $3"* ]]
}

check "no {{...}} placeholders remain" no_placeholders_left
check "exactly 5 app cards render" app_card_count_is 5
for app in docs pm design twenty support; do
    check "app card links to https://$app.example.test" page_contains "href=\"https://$app.example.test\""
done
check "FOSS_LOGOUT.portal" page_contains 'portal: "https://example.test"'
check "FOSS_LOGOUT.oauthProxy" page_contains 'oauthProxy: "https://auth.example.test/oauth2/sign_out"'
check "FOSS_LOGOUT.cognitoLogout" page_contains 'cognitoLogout: "https://idp.example.test/logout"'
check "FOSS_LOGOUT.cognitoClientId" page_contains 'cognitoClientId: "ci-client"'
for app in chatwoot mautic; do
    check "no ${app} tile without its host" not_page_contains "class=\"app-card card-${app}\""
done
check "no Chatwoot pill without CHATWOOT_HOST" not_page_contains '</span>Chatwoot</span>'
check "no Mautic pill without MAUTIC_HOST" not_page_contains '</span>Mautic</span>'

page=$("$(dirname "$0")/render-page.sh" "$image" "$fixtures/sample-chatwoot.env")
check "no {{...}} placeholders remain with CHATWOOT_HOST" no_placeholders_left
check "exactly 6 app cards render with CHATWOOT_HOST" app_card_count_is 6
check "Chatwoot card links to CHATWOOT_HOST" page_contains 'href="https://chatwoot.example.test"'
check "Chatwoot pill renders with CHATWOOT_HOST" page_contains '</span>Chatwoot</span>'
check "no Mautic tile with only CHATWOOT_HOST" not_page_contains 'class="app-card card-mautic"'
check "no app markers leak into the page with CHATWOOT_HOST" not_page_contains '<!-- app:'

page=$("$(dirname "$0")/render-page.sh" "$image" "$fixtures/sample-mautic.env")
check "no {{...}} placeholders remain with MAUTIC_HOST" no_placeholders_left
check "exactly 6 app cards render with MAUTIC_HOST" app_card_count_is 6
check "Mautic card links to MAUTIC_HOST" page_contains 'href="https://mautic.example.test/s/dashboard"'
check "Mautic pill renders with MAUTIC_HOST" page_contains '</span>Mautic</span>'
check "no Chatwoot tile with only MAUTIC_HOST" not_page_contains 'class="app-card card-chatwoot"'
check "no app markers leak into the page with MAUTIC_HOST" not_page_contains '<!-- app:'

page=$("$(dirname "$0")/render-page.sh" "$image" "$fixtures/sample-both.env")
check "no {{...}} placeholders remain with both hosts" no_placeholders_left
check "exactly 7 app cards render with both hosts" app_card_count_is 7
check "Chatwoot card links to CHATWOOT_HOST with both hosts" page_contains 'href="https://chatwoot.example.test"'
check "Mautic card links to MAUTIC_HOST with both hosts" page_contains 'href="https://mautic.example.test/s/dashboard"'
check "Chatwoot card comes before Mautic card" cards_in_order card-zammad card-chatwoot card-mautic
check "no app markers leak into the page with both hosts" not_page_contains '<!-- app:'

startup_fails_naming() {
    local variable=$1
    shift
    local output status=0
    output=$("$timeout_cmd" 30 docker run --rm "$@" "$image" 2>&1) || status=$?
    [[ $status -ne 0 && $status -ne 124 ]] && grep -qF "$variable is required" <<<"$output"
}

check "startup fails when PLATFORM_DOMAIN is unset" \
    startup_fails_naming PLATFORM_DOMAIN -e PLATFORM_PROTOCOL=https
check "startup fails when PLATFORM_DOMAIN is empty" \
    startup_fails_naming PLATFORM_DOMAIN -e PLATFORM_DOMAIN= -e PLATFORM_PROTOCOL=https
check "startup fails when PLATFORM_PROTOCOL is unset" \
    startup_fails_naming PLATFORM_PROTOCOL -e PLATFORM_DOMAIN=example.test
check "startup fails when PLATFORM_PROTOCOL is empty" \
    startup_fails_naming PLATFORM_PROTOCOL -e PLATFORM_DOMAIN=example.test -e PLATFORM_PROTOCOL=

[[ $failures -eq 0 ]] || { echo "$failures check(s) failed"; exit 1; }
