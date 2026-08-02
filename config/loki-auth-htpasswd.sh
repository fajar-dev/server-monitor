#!/bin/sh
# Runs inside the nginx container (via /docker-entrypoint.d/) before nginx starts.
# Generates /etc/nginx/.htpasswd from the LOKI_USER / LOKI_PASSWORD env vars so the
# credentials live only in the monitoring server's .env, never in the image or repo.

if [ -n "$LOKI_USER" ] && [ -n "$LOKI_PASSWORD" ]; then
    apk add --no-cache apache2-utils >/dev/null 2>&1
    htpasswd -bc /etc/nginx/.htpasswd "$LOKI_USER" "$LOKI_PASSWORD"
    echo "loki-auth: htpasswd generated for user '$LOKI_USER'"
else
    echo "loki-auth: LOKI_USER/LOKI_PASSWORD not set — refusing to start without auth" >&2
    exit 1
fi
