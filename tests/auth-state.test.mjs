import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { once } from "node:events";
import { chromium } from "playwright";

const PORT = 8181;
const PORTAL = `http://example.test:${PORT}`;
const PORTAL_ROOT = `${PORTAL}/`;
const IDP_LOGOUT = `http://idp.example.test:${PORT}/logout`;
const IDP_AUTHORIZE = `http://idp.example.test:${PORT}/oauth2/authorize`;
const CLIENT_ID = "ci-client";
const SWITCH_LABEL = "Sign out / switch account";
const LOGOUT_LABEL = "Log out of all apps";
const DENIED_PATH = "/?login_error=access_denied&reason=not_corporate";

const renderedPage = (variable) => readFileSync(process.env[variable] ?? assert.fail(`${variable} is not set`), "utf8");
const pages = { withIdp: renderedPage("LANDING_PAGE"), withoutIdp: renderedPage("LANDING_PAGE_NO_IDP") };

let platform;
let server;
let browser;

const redirect = (location) => ({ status: 302, headers: { location } });

function platformResponse(url) {
  switch (url.hostname + url.pathname) {
    case "example.test/":
      return { status: 200, headers: { "content-type": "text/html" }, body: platform.html };
    case "example.test/oauth2/auth":
      return { status: platform.proxyAuthStatus };
    case "example.test/oauth2/start":
      return { status: 200, headers: { "content-type": "text/html" }, body: "oauth2-proxy start" };
    case "example.test/api/me":
      return redirect(IDP_AUTHORIZE);
    case "auth.example.test/oauth2/sign_out":
      return redirect(url.searchParams.get("rd"));
    case "idp.example.test/logout":
      return redirect(url.searchParams.get("logout_uri"));
    case "idp.example.test/oauth2/authorize":
      return { status: 200 };
    default:
      return { status: 404 };
  }
}

before(async () => {
  server = createServer((request, response) => {
    const url = new URL(request.url, `http://${request.headers.host}`);
    platform.hits.push({ endpoint: url.hostname + url.pathname, url });
    const { status, headers, body } = platformResponse(url);
    response.writeHead(status, headers).end(body);
  });
  server.listen(PORT, "127.0.0.1");
  await once(server, "listening");
  browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || undefined,
    args: [`--host-resolver-rules=MAP example.test 127.0.0.1, MAP *.example.test 127.0.0.1`],
  });
});

after(async () => {
  await browser?.close();
  server?.close();
});

async function openPortal(t, html) {
  platform = { html, proxyAuthStatus: 401, hits: [] };
  const context = await browser.newContext();
  t.after(() => context.close());
  await context.route((url) => !url.hostname.endsWith("example.test"), (route) => route.abort());
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  t.after(() => assert.deepEqual(errors, [], "page raised script errors"));
  return page;
}

const hitEndpoints = () => platform.hits.map((hit) => hit.endpoint);

async function visit(page, path = "/") {
  await page.goto(PORTAL + path);
  await page.waitForFunction(() => document.getElementById("auth-btn").textContent !== "Checking session...");
}

function portalState(page) {
  return page.evaluate(() => {
    const button = document.getElementById("auth-btn");
    return {
      url: location.href,
      button: button.textContent,
      buttonIsLogout: button.classList.contains("auth-btn-logout"),
      banner: document.querySelector(".auth-error-banner")?.textContent ?? null,
      bannerAction: document.querySelector(".auth-error-banner .banner-action")?.textContent ?? null,
      toasts: [...document.querySelectorAll(".toast")].map((toast) => toast.textContent),
      marker: localStorage.getItem("foss_cognito_alive_ts"),
      justLoggedIn: sessionStorage.getItem("foss_just_logged_in"),
    };
  });
}

test("a fresh visit offers Login, which starts the oauth2-proxy flow", async (t) => {
  const page = await openPortal(t, pages.withIdp);
  await visit(page);

  const state = await portalState(page);
  assert.equal(state.button, "Login");
  assert.equal(state.banner, null);
  assert.equal(state.marker, null);

  await page.click("#auth-btn");
  await page.waitForURL("**/oauth2/start?**");
  assert.equal(new URL(page.url()).searchParams.get("rd"), PORTAL);
});

test("a live proxy session after Login offers Log out of all apps", async (t) => {
  const page = await openPortal(t, pages.withIdp);
  await visit(page);
  await page.click("#auth-btn");
  await page.waitForURL("**/oauth2/start?**");

  platform.proxyAuthStatus = 202;
  await visit(page);

  const state = await portalState(page);
  assert.equal(state.button, LOGOUT_LABEL);
  assert.ok(state.buttonIsLogout);
  assert.ok(state.marker, "IdP-alive marker should be set");
  assert.ok(state.toasts.includes("You are now logged in."));
});

test("an access denial offers the account switch on the button and the banner", async (t) => {
  const page = await openPortal(t, pages.withIdp);
  await visit(page);
  await page.evaluate(() => sessionStorage.setItem("foss_just_logged_in", "1"));
  await visit(page, DENIED_PATH);

  const state = await portalState(page);
  assert.equal(state.url, PORTAL_ROOT, "denial params should be stripped");
  assert.equal(state.button, SWITCH_LABEL);
  assert.ok(state.buttonIsLogout);
  assert.match(state.banner, /Access Denied/);
  assert.match(state.banner, /personal account/);
  assert.equal(state.bannerAction, SWITCH_LABEL);
  assert.ok(state.marker, "IdP-alive marker should be set");
  assert.equal(state.justLoggedIn, null);
});

test("a reload after a denial keeps the logout offer without a logged-in toast or a background authorize", async (t) => {
  const page = await openPortal(t, pages.withIdp);
  await visit(page);
  await page.evaluate(() => sessionStorage.setItem("foss_just_logged_in", "1"));
  await visit(page, DENIED_PATH);
  await page.reload();
  await page.waitForLoadState("networkidle");

  const state = await portalState(page);
  assert.equal(state.button, LOGOUT_LABEL);
  assert.equal(state.banner, null);
  assert.ok(!state.toasts.some((toast) => /logged in/.test(toast)));
  assert.ok(hitEndpoints().includes("example.test/api/me"), "/api/me should be fetched");
  assert.ok(
    !hitEndpoints().includes("idp.example.test/oauth2/authorize"),
    "/api/me redirect to the IdP must not be followed",
  );
});

async function switchAccountVia(t, selector, { dismissBanner }) {
  const page = await openPortal(t, pages.withIdp);
  await visit(page, "/?login_error=access_denied&reason=wrong_organization");
  if (dismissBanner) {
    await page.click(".auth-error-banner .banner-dismiss");
    await page.waitForSelector(".auth-error-banner", { state: "detached" });
  }
  platform.hits.length = 0;

  await page.click(selector);
  await page.waitForSelector('.toast:has-text("You have been logged out.")');

  const logoutHits = platform.hits.filter((hit) => hit.endpoint !== "example.test/oauth2/auth");
  assert.deepEqual(
    logoutHits.map((hit) => hit.endpoint),
    ["auth.example.test/oauth2/sign_out", "idp.example.test/logout", "example.test/"],
  );
  const [signOut, idpLogout] = logoutHits;
  assert.equal(signOut.url.searchParams.get("rd"), `${IDP_LOGOUT}?client_id=${CLIENT_ID}&logout_uri=${PORTAL}`);
  assert.equal(idpLogout.url.searchParams.get("client_id"), CLIENT_ID);
  assert.equal(idpLogout.url.searchParams.get("logout_uri"), PORTAL);

  const state = await portalState(page);
  assert.equal(state.url, PORTAL_ROOT);
  assert.equal(state.button, "Login");
  assert.equal(state.marker, null);
}

test("switching account from the banner ends the proxy and IdP sessions", (t) =>
  switchAccountVia(t, ".auth-error-banner .banner-action", { dismissBanner: false }));

test("switching account from the header button ends the proxy and IdP sessions", (t) =>
  switchAccountVia(t, "#auth-btn", { dismissBanner: true }));

test("without IdP logout config a denial shows the banner but keeps Login", async (t) => {
  const page = await openPortal(t, pages.withoutIdp);
  await visit(page, DENIED_PATH);

  const state = await portalState(page);
  assert.equal(state.url, PORTAL_ROOT);
  assert.equal(state.button, "Login");
  assert.match(state.banner, /Access Denied/);
  assert.equal(state.bannerAction, null);
  assert.equal(state.marker, null);
});
