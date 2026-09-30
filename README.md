# foss-landing

The FOSS platform's landing portal: one static page, served by nginx, that links to
every app and drives portal-wide sign-in and sign-out through oauth2-proxy.

> This page used to live at `landing/index.html.example` inside
> [Pressingly/foss-server-bundle](https://github.com/Pressingly/foss-server-bundle).
> That copy is deprecated. This repository is the source of truth for all new
> development, and its history carries the page's commits from the bundle.

## How the image works

The image ships `index.html.example` as a template. On every container start,
`docker-entrypoint.d/40-render-landing.sh` substitutes the placeholders from the
environment and writes `/usr/share/nginx/html/index.html`, then nginx starts.

Rendering happens at runtime, never at build time. Nothing deployment-specific is
baked into the image, so one tag serves every deployment: compose, Ansible and
Kubernetes alike.

## Configuration

| Variable | Placeholder | Required | Example |
|---|---|---|---|
| `PLATFORM_DOMAIN` | `{{DOMAIN}}` | yes | `moneta.askii.ai` |
| `PLATFORM_PROTOCOL` | `{{PROTOCOL}}` | yes | `https` |
| `OIDC_LOGOUT_URI` | `{{OIDC_LOGOUT_URI}}` | for sign-out | bare Cognito `/logout` endpoint |
| `OIDC_CLIENT_ID` | `{{OIDC_CLIENT_ID}}` | for sign-out | Cognito app client id |
| `SMB_NAME` | `{{SMB_NAME}}` | no | `foss` |
| `SUBDOMAIN_PREFIX` | `{{SUBDOMAIN_PREFIX}}` | no | empty |

- The container exits at startup if a required variable is unset or empty.
- Optional variables render as an empty string when unset.
- Values are inserted literally, including `&`, `|` and `\`.

## Running locally

```bash
docker build -t foss-landing .
docker run --rm -p 8080:80 \
  -e PLATFORM_DOMAIN=local.moneta.dev \
  -e PLATFORM_PROTOCOL=https \
  foss-landing
```

## Deploying

The image owns the page only. Routing and headers stay in each deployment:

- **Traefik (compose, Ansible):** the landing router must keep a low priority
  (the bundle uses `5`) so the more specific routers on the portal host, such as
  launchpad-api's `/api/*`, win their paths. The portal's CSP middleware
  (`landing-csp`) also lives in the deployment.
- **Kubernetes:** set the variables on the container. With
  `readOnlyRootFilesystem: true`, mount writable `emptyDir` volumes at
  `/usr/share/nginx/html`, `/var/cache/nginx` and `/var/run`.

The container listens on port `80`.

## Releases

Tags trigger Cloud Build: `vX.Y.Z-rc.N` publishes to the sandbox Artifact
Registry, and `vX.Y.Z` publishes to production after approval. The image path is
`<registry>/foss-landing/landing`.

## License

GPL-3.0. See [LICENSE](LICENSE).
