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

check "no {{...}} placeholders remain" no_placeholders_left
check "exactly 5 app cards render" app_card_count_is 5
for app in docs pm design twenty support; do
    check "app card links to https://$app.example.test" page_contains "href=\"https://$app.example.test\""
done
check "FOSS_LOGOUT.portal" page_contains 'portal: "https://example.test"'
check "FOSS_LOGOUT.oauthProxy" page_contains 'oauthProxy: "https://auth.example.test/oauth2/sign_out"'
check "FOSS_LOGOUT.cognitoLogout" page_contains 'cognitoLogout: "https://idp.example.test/logout"'
check "FOSS_LOGOUT.cognitoClientId" page_contains 'cognitoClientId: "ci-client"'
check "no Chatwoot tile without CHATWOOT_HOST" not_page_contains 'card-chatwoot'

page=$("$(dirname "$0")/render-page.sh" "$image" "$fixtures/sample-chatwoot.env")
check "no {{...}} placeholders remain with CHATWOOT_HOST" no_placeholders_left
check "exactly 6 app cards render with CHATWOOT_HOST" app_card_count_is 6
check "Chatwoot card links to CHATWOOT_HOST" page_contains 'href="https://chatwoot.example.test"'
check "no app markers leak into the page" not_page_contains 'app:chatwoot'

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
