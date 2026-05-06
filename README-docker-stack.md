# JBS Networks Docker stack

This branch adds a production Docker Compose stack for Nginx and Navidrome.

## Apply before production

1. Replace `music.example.com` in `nginx/conf.d/20-navidrome.conf`.
2. Put certificate files at `nginx/certs/fullchain.pem` and `nginx/certs/privkey.pem`.
3. Replace `/srv/music:/music:ro` in `compose.yaml` with the real music path.

## Run

```bash
docker compose -f compose.yaml build
docker compose -f compose.yaml up -d
docker compose -f compose.yaml ps
```

## Healthcheck

Nginx healthcheck is isolated to `127.0.0.1:8080/nginx-health`, so HTTPS redirect, public server_name, auth, CDN checks, and HTTP/3 do not break container health.

## HTTP/3 note

Keep `quic_bpf` disabled by default. After HTTP/3 configuration changes, prefer full container restart:

```bash
docker compose -f compose.yaml restart nginx
```
