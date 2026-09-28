hum, i think we're missing something, why is traefik not picking up my labels and actualy routing it ? i don't see it in the traefik config ... 
core: 
```
services:
# -------------------------------------------------------
# INFRASTRUCTURE
# -------------------------------------------------------

#  deunhealth:
#    image: qmcgaw/deunhealth
#    container_name: deunhealth
#    network_mode: "none"
#    environment:
#      - LOG_LEVEL=info
#      - HEALTH_SERVER_ADDRESS=${HEALTH_SERVER_ADDRESS}
#      - TZ=${TZ}
#    restart: always
#    volumes:
#      - /var/run/docker.sock:/var/run/docker.sock

  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    environment:
      - LOG_LEVEL=info
      - TZ=${TZ}
    networks:
      - proxy
    restart: unless-stopped

  tailscale:
    image: tailscale/tailscale
    container_name: tailscale
    network_mode: "host"
    environment:
      - TS_HOSTNAME=${TS_HOSTNAME}
      - TS_AUTHKEY=${TS_AUTHKEY}
      - TS_STATE_DIR=${TS_STATE_DIR}
      - TS_ROUTES=${TS_ROUTES}
      - TS_USERSPACE=${TS_USERSPACE}
    volumes:
      - /volume2/docker/stacks/core/tailscale:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - NET_RAW
    restart: unless-stopped

  adguard:
    container_name: adguard
    image: adguard/adguardhome
    dns:
      - 8.8.8.8
      - 1.1.1.1
    environment:
      - TZ=Europe/Paris
    volumes:
      - /volume2/docker/stacks/core/adguard/work:/opt/adguardhome/work
      - /volume2/docker/stacks/core/adguard/conf:/opt/adguardhome/conf
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.adguard.rule=Host(`adguard.${DESEC_DOMAIN}`)"
      - "traefik.http.services.adguard.loadbalancer.server.port=${ADGUARD_PORT}"
      - "traefik.http.routers.adguard.entrypoints=websecure"
      - "traefik.http.routers.adguard.tls=true"
      - "traefik.http.routers.adguard.middlewares=crowdsec,authentik,secure-headers"
    networks:
      proxy:
        ipv4_address: 10.10.10.12
      macvlan_net:
        ipv4_address: 192.168.1.200
    restart: unless-stopped

  traefik:
    image: traefik:v3
    container_name: traefik
    security_opt:
      - no-new-privileges:true
    ports:
      - ${TRAEFIK_HOST_PORT}:${TRAEFIK_SERVICE_PORT}
    environment:
      - TEST="TEST"
      - TZ=${TZ}
      - DESEC_TOKEN=${DESEC_TOKEN}
      - DESEC_DOMAIN=${DESEC_DOMAIN}
      - LEGO_DISABLE_CNAME_SUPPORT=true
    volumes:
      - /volume2/docker/stacks/core/traefik/traefik.yml:/traefik.yml:ro
      - /volume2/docker/stacks/core/traefik/acme.json:/acme.json
      - /volume2/docker/stacks/core/traefik/dynamic:/dynamic_conf
      - /volume2/docker/stacks/core/traefik/logs:/var/log/traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(`traefik.${DESEC_DOMAIN}`)"
      - "traefik.http.routers.api.service=api@internal"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=${ACME_DNS_PROVIDER}"
      - "traefik.http.routers.api.tls.domains[0].main=${DESEC_DOMAIN}"
      - "traefik.http.routers.api.tls.domains[0].sans=${DESEC_SANS}"
      - "traefik.http.routers.api.middlewares=crowdsec,authentik,secure-headers"
      # --- MIDDLEWARE DEFINITIONS (The Rules) ---
      # 1. Authentik (The Bouncer)
      - "traefik.http.middlewares.authentik.forwardauth.address=http://authentik_server:9000/outpost.goauthentik.io/auth/traefik"
      - "traefik.http.middlewares.authentik.forwardauth.trustForwardHeader=true"
      - "traefik.http.middlewares.authentik.forwardauth.authResponseHeaders=X-authentik-username,X-authentik-groups,X-authentik-email,X-authentik-name,X-authentik-uid"
      - "traefik.http.middlewares.authentik.forwardauth.maxResponseBodySize=2097152"
      # 2. Internal Only (The IP Filter)
      # 127.0.0.1 (Local), 192.168.0.0/16 (Home LAN), 10.0.0.0/8 (Tailscale/Docker)
      - "traefik.http.middlewares.internal-only.ipallowlist.sourcerange=127.0.0.1/32,192.168.0.0/16,10.0.0.0/8"
      # 3. SECURE HEADERS (The Armor) - Prevents browser attacks
      - "traefik.http.middlewares.secure-headers.headers.sslredirect=true"
      - "traefik.http.middlewares.secure-headers.headers.stsSeconds=315360000"
      - "traefik.http.middlewares.secure-headers.headers.browserXssFilter=true"
      - "traefik.http.middlewares.secure-headers.headers.contentTypeNosniff=true"
      - "traefik.http.middlewares.secure-headers.headers.forceSTSHeader=true"
      # 4. AUTH HEADERS FIX (The Logic Fix for Authentik redirection)
      - "traefik.http.middlewares.auth-headers.headers.customrequestheaders.X-Forwarded-Proto=https"
      # --- CROWDSEC MIDDLEWARE ---
      - "traefik.http.middlewares.crowdsec.forwardauth.address=http://cs-bouncer:8080/api/v1/forwardAuth"
      - "traefik.http.middlewares.crowdsec.forwardauth.trustForwardHeader=true"
      - "traefik.http.middlewares.crowdsec.forwardauth.maxResponseBodySize=2097152"
      # ---------------------------
    networks:
      - proxy
      - socket_net
    restart: unless-stopped

  ddclient:
    image: lscr.io/linuxserver/ddclient:latest
    container_name: ddclient
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - /volume2/docker/stacks/core/ddclient:/config
    dns:
      - 8.8.8.8
      - 1.1.1.1
    networks:
      - proxy
    restart: unless-stopped

  auth_postgres:
    image: postgres:16-alpine
    container_name: auth_postgres
    environment:
      - POSTGRES_PASSWORD=${AUTHENTIK_POSTGRES_PASSWORD}
      - POSTGRES_USER=${AUTHENTIK_POSTGRES_USER}
      - POSTGRES_DB=${AUTHENTIK_POSTGRES_DB}
    volumes:
      - /volume2/docker/stacks/core/auth_postgres:/var/lib/postgresql/data
    networks:
      - backend
    restart: unless-stopped

  authentik_server:
    image: ghcr.io/goauthentik/server:2026.8.3
    container_name: authentik_server
    command: server
    environment:
      - AUTHENTIK_POSTGRESQL__HOST=${AUTHENTIK_POSTGRESQL_HOST}
      - AUTHENTIK_POSTGRESQL__USER=${AUTHENTIK_POSTGRES_USER}
      - AUTHENTIK_POSTGRESQL__NAME=${AUTHENTIK_POSTGRES_DB}
      - AUTHENTIK_POSTGRESQL__PASSWORD=${AUTHENTIK_POSTGRES_PASSWORD}
      - AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
    volumes:
      - /volume2/docker/stacks/core/authentik/media:/media
      - /volume2/docker/stacks/core/authentik/templates:/templates
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.authentik.rule=Host(`auth.${DESEC_DOMAIN}`)"
      - "traefik.http.services.authentik.loadbalancer.server.port=${AUTHENTIK_SERVER_PORT}"
      - "traefik.http.routers.authentik.entrypoints=websecure"
      - "traefik.http.routers.authentik.tls=true"
      - "traefik.http.routers.authentik.middlewares=crowdsec,secure-headers,auth-headers"
    networks:
      - proxy
      - backend
    depends_on:
      - auth_postgres
    restart: unless-stopped

  authentik_worker:
    image: ghcr.io/goauthentik/server:2026.8.3
    container_name: authentik_worker
    command: worker
    environment:
      - AUTHENTIK_POSTGRESQL__HOST=${AUTHENTIK_POSTGRESQL_HOST}
      - AUTHENTIK_POSTGRESQL__USER=${AUTHENTIK_POSTGRES_USER}
      - AUTHENTIK_POSTGRESQL__NAME=${AUTHENTIK_POSTGRES_DB}
      - AUTHENTIK_POSTGRESQL__PASSWORD=${AUTHENTIK_POSTGRES_PASSWORD}
      - AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
    volumes:
      - /volume2/docker/stacks/core/authentik/media:/media
      - /volume2/docker/stacks/core/authentik/templates:/templates
    networks:
      - backend
    depends_on:
      - auth_postgres
    restart: unless-stopped

  socket-proxy:
    image: tecnativa/docker-socket-proxy:latest
    container_name: socket-proxy
    environment:
      - CONTAINERS=1
      - NETWORKS=1
      - EVENTS=1
      - POST=0 
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - socket_net
    restart: unless-stopped

  crowdsec:
    image: crowdsecurity/crowdsec:latest
    container_name: crowdsec
    environment:
      - GID=${PGID}
      - COLLECTIONS=${CROWDSEC_COLLECTIONS}
    volumes:
      - /volume2/docker/stacks/core/crowdsec/config:/etc/crowdsec
      - /volume2/docker/stacks/core/crowdsec/data:/var/lib/crowdsec/data
      - /volume2/docker/stacks/core/traefik/logs:/var/log/traefik:ro
    networks:
      - proxy
    restart: unless-stopped

  cs-bouncer:
    image: fbonalair/traefik-crowdsec-bouncer:latest
    container_name: cs-bouncer
    environment:
      - CROWDSEC_BOUNCER_API_KEY=${CROWDSEC_BOUNCER_API_KEY}
      - CROWDSEC_AGENT_HOST=${CROWDSEC_AGENT_HOST}
    networks:
      - proxy
    restart: unless-stopped

  notifications:
    image: node:24-slim
    container_name: notifications
    working_dir: /app
    volumes:
      - /volume2/docker/stacks/core/notifications:/app
    command: sh -c "npm install && node --watch src/index.js"
    labels:
      - "traefik.enable=true"
      - "traefik.http.services.notifications.loadbalancer.server.port=${NOTIFICATIONS_PORT}"

      # 1. FRONTEND ROUTER (Protected by Authentik)
      # Matches everything EXCEPT /webhook
      - "traefik.http.routers.notifications-web.rule=Host(`notifications.${DESEC_DOMAIN}`)"
      - "traefik.http.routers.notifications-web.entrypoints=websecure"
      - "traefik.http.routers.notifications-web.tls=true"
      - "traefik.http.routers.notifications-web.middlewares=crowdsec,authentik,secure-headers"
      - "traefik.http.routers.notifications-web.service=notifications"

      # 2. WEBHOOK ROUTER (Bypasses Authentik)
      # Radarr/Sonarr use ?apikey= for auth here. Authentik would block them.
      # Because PathPrefix is more specific, Traefik routes /webhook requests here.
      - "traefik.http.routers.notifications-hook.rule=Host(`notifications.${DESEC_DOMAIN}`) && PathPrefix(`/webhook`)"
      - "traefik.http.routers.notifications-hook.entrypoints=websecure"
      - "traefik.http.routers.notifications-hook.tls=true"
      - "traefik.http.routers.notifications-hook.middlewares=crowdsec,secure-headers"
      - "traefik.http.routers.notifications-hook.service=notifications"
    networks:
      - proxy
    restart: unless-stopped
  
  cdn:
    image: busybox:musl
    container_name: cdn
    command: httpd -f -p 80 -h /www
    volumes:
      - /volume2/docker/stacks/core/cdn/public:/www:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.cdn.rule=Host(`cdn.${DESEC_DOMAIN}`)"
      - "traefik.http.services.cdn.loadbalancer.server.port=${CDN_PORT}"
      - "traefik.http.routers.cdn.entrypoints=websecure"
      - "traefik.http.routers.cdn.tls=true"
      - "traefik.http.routers.cdn.middlewares=crowdsec,secure-headers"
    networks:
      - proxy
    restart: unless-stopped

#  hdd-monitor:
#    image: alpine:latest
#    container_name: hdd-monitor
#    privileged: true
#    environment:
#      - TZ=${TZ}
#    command: >
#      sh -c "apk add --no-cache inotify-tools && inotifywait -m -r -e open,modify --timefmt '%Y-%m-%d %H:%M:%S' --format '%T | %e | %w%f' /volume1/data"
#    volumes:
#      - /volume1/data:/volume1/data:ro
#    logging:
#      driver: "json-file"
#      options:
#        max-size: "10m"
#        max-file: "3"
#    restart: unless-stopped

# --- NETWORK CREATION ---
networks:
  proxy:
    name: proxy
    driver: bridge
    ipam:
      config:
        - subnet: 10.10.10.0/24
          gateway: 10.10.10.1
  macvlan_net:
    driver: macvlan
    driver_opts:
      parent: eth0
    ipam:
      config:
        - subnet: 192.168.1.0/24 
          gateway: 192.168.1.1   
          ip_range: 192.168.1.200/32
  backend:
    name: backend
    driver: bridge
    ipam:
      config:
        - subnet: 10.10.20.0/24
          gateway: 10.10.20.1
  socket_net:
    name: socket_net
    driver: bridge
    ipam:
      config:
        - subnet: 10.10.30.0/24
          gateway: 10.10.30.1
```


traefik.yml:
```
global:
  checkNewVersion: false
  sendAnonymousUsage: false

log:
  level: INFO

accessLog:
  filePath: "/var/log/traefik/access.log"
  bufferingSize: 100

api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
    http:
      encodedCharacters:
        allowEncodedSlash: false
        allowEncodedBackSlash: false
        allowEncodedNullCharacter: false
        allowEncodedSemicolon: false
        allowEncodedPercent: false
        allowEncodedQuestionMark: false
        allowEncodedHash: false

certificatesResolvers:
  desec:
    acme:
      email: "hugo.dasilva.filipe@gmail.com"
      storage: acme.json
      dnsChallenge:
        provider: desec
        propagation:
          delayBeforeChecks: 60
        resolvers:
          - "1.1.1.1:53"
          - "8.8.8.8:53"

providers:
  docker:
    endpoint: "tcp://socket-proxy:2375" 
    exposedByDefault: false
  file:
    directory: "/dynamic_conf"
    watch: false
```

lab : 
```
services:
# -------------------------------------------------------
# LAB
# -------------------------------------------------------
  pronostics:
    build: /volume2/docker/stacks/lab/pronostics
    container_name: pronostics
    environment:
      - TZ=${TZ}
    user: "${PUID}:${PGID}"
    volumes:
      - /volume2/docker/stacks/lab/pronostics/data:/app/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.pronostics.rule=Host(`cesars.${DESEC_DOMAIN}`)"
      - "traefik.http.services.pronostics.loadbalancer.server.port=${PRONOSTICS_PORT}"
      - "traefik.http.routers.pronostics.entrypoints=websecure"
      - "traefik.http.routers.pronostics.tls=true"
      - "traefik.http.routers.pronostics.middlewares=crowdsec,secure-headers"
    networks:
      - proxy
    restart: unless-stopped

  trek:
    image: mauriceboe/trek:latest
    container_name: trek
    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
    tmpfs:
      - /tmp:noexec,nosuid,size=64m
    environment:
      - NODE_ENV=production
      - PORT=${TREK_PORT}
      - ENCRYPTION_KEY=${TREK_ENCRYPTION_KEY} # Add this to your .env (generate with: openssl rand -hex 32)
      - TZ=${TZ}
      - LOG_LEVEL=info
      - FORCE_HTTPS=true
      - TRUST_PROXY=1
      - APP_URL=https://trek.${DESEC_DOMAIN}
      - ADMIN_EMAIL=admin@trek.local
      - ADMIN_PASSWORD=changeme
      # --- AUTHENTIK NATIVE OIDC (Optional, but recommended over Traefik ForwardAuth for this app) ---
      # - OIDC_ISSUER=https://auth.${DESEC_DOMAIN}/application/o/trek/
      # - OIDC_CLIENT_ID=${TREK_OIDC_CLIENT_ID}
      # - OIDC_CLIENT_SECRET=${TREK_OIDC_CLIENT_SECRET}
      # - OIDC_DISPLAY_NAME=Authentik
      # - OIDC_ONLY=true
      # - OIDC_ADMIN_CLAIM=groups
      # - OIDC_ADMIN_VALUE=trek-admins
    volumes:
      - /volume2/docker/stacks/lab/trek/data:/app/data
      - /volume2/docker/stacks/lab/trek/uploads:/app/uploads
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.trek.rule=Host(`trek.${DESEC_DOMAIN}`)"
      - "traefik.http.services.trek.loadbalancer.server.port=${TREK_PORT}"
      - "traefik.http.routers.trek.entrypoints=websecure"
      - "traefik.http.routers.trek.tls=true"
      - "traefik.http.routers.trek.middlewares=crowdsec,secure-headers"
    healthcheck:
      disable: true
    networks:
      - proxy
    restart: unless-stopped

  # -------------------------------------------------------
# BAR ASSISTANT
# -------------------------------------------------------
  salt-rim:
    image: barassistant/salt-rim:v4
    container_name: salt_rim
    depends_on:
      - bar-assistant
    environment:
      - API_URL=${BAR_API_URL}
      - MEILISEARCH_URL=${BAR_MEILISEARCH_URL}
    labels:
      - "traefik.enable=true"
      # UI sits at the root domain
      - "traefik.http.routers.saltrim.rule=Host(`bar.${DESEC_DOMAIN}`)"
      - "traefik.http.services.saltrim.loadbalancer.server.port=8080"
      - "traefik.http.routers.saltrim.entrypoints=websecure"
      - "traefik.http.routers.saltrim.tls=true"
      - "traefik.http.routers.saltrim.middlewares=crowdsec,secure-headers"
    networks:
      - proxy
    restart: unless-stopped

  bar-assistant:
    image: barassistant/server:v5
    container_name: bar_assistant
    depends_on:
      - bar_meilisearch
      - bar_redis
    environment:
      - APP_URL=${BAR_API_URL}
      - MEILISEARCH_KEY=${BAR_MEILI_MASTER_KEY}
      - MEILISEARCH_HOST=http://bar_meilisearch:7700
      - REDIS_HOST=bar_redis
      - CACHE_DRIVER=redis
      - SESSION_DRIVER=redis
      - ALLOW_REGISTRATION=false
    volumes:
      - /volume2/docker/stacks/lab/bar_assistant/storage:/var/www/cocktails/storage/bar-assistant
    labels:
      - "traefik.enable=true"
      # API sits at /bar and requires the prefix to be stripped before hitting the container
      - "traefik.http.routers.bar-api.rule=Host(`bar.${DESEC_DOMAIN}`) && PathPrefix(`/bar`)"
      - "traefik.http.services.bar-api.loadbalancer.server.port=8080"
      - "traefik.http.routers.bar-api.entrypoints=websecure"
      - "traefik.http.routers.bar-api.tls=true"
      - "traefik.http.middlewares.bar-stripprefix.stripprefix.prefixes=/bar"
      - "traefik.http.routers.bar-api.middlewares=bar-stripprefix,crowdsec,secure-headers"
    networks:
      - proxy
      - backend
    restart: unless-stopped

  bar_meilisearch:
    image: getmeili/meilisearch:v1.15
    container_name: bar_meilisearch
    environment:
      - MEILI_NO_ANALYTICS=true
      - MEILI_MASTER_KEY=${BAR_MEILI_MASTER_KEY}
      - MEILI_ENV=production
    volumes:
      - /volume2/docker/stacks/lab/bar_assistant/meilisearch:/meili_data
    labels:
      - "traefik.enable=true"
      # Search sits at /search and requires the prefix to be stripped before hitting the container
      - "traefik.http.routers.bar-search.rule=Host(`bar.${DESEC_DOMAIN}`) && PathPrefix(`/search`)"
      - "traefik.http.services.bar-search.loadbalancer.server.port=7700"
      - "traefik.http.routers.bar-search.entrypoints=websecure"
      - "traefik.http.routers.bar-search.tls=true"
      - "traefik.http.middlewares.bar-search-stripprefix.stripprefix.prefixes=/search"
      - "traefik.http.routers.bar-search.middlewares=bar-search-stripprefix,crowdsec,secure-headers"
    networks:
      - proxy
      - backend
    restart: unless-stopped

  bar_redis:
    image: redis:alpine
    container_name: bar_redis
    environment:
      - ALLOW_EMPTY_PASSWORD=yes
    networks:
      - backend
    restart: unless-stopped

#  sems:
#    image: ghcr.io/hugo-hdsf/sems-electra-ao:latest
#    container_name: sems
#    environment:
#      - TZ=${TZ}
#    command: ["./sems", "--config", "configs/example_station.json", "--port", "${SEMS_PORT:-8080}"]
#    user: "${PUID}:${PGID}"
#    labels:
#      - "traefik.enable=true"
#      - "traefik.http.routers.sems.rule=Host(`sems.${DESEC_DOMAIN}`)"
#      - "traefik.http.services.sems.loadbalancer.server.port=${SEMS_PORT}"
#      - "traefik.http.routers.sems.entrypoints=websecure"
#      - "traefik.http.routers.sems.tls=true"
#      - "traefik.http.routers.sems.middlewares=crowdsec,secure-headers"
#    networks:
#      - proxy
#    restart: unless-stopped
#    healthcheck:
#      test: ["CMD", "wget", "--spider", "-q", "http://localhost:${SEMS_PORT:-8080}/api/v1/status"]
#      interval: 30s
#      timeout: 5s
#      retries: 3
#      start_period: 10s

  opengym:
    image: ghcr.io/hugo-hdsf/opengym-aio:latest
    container_name: opengym
    environment:
      - PORT=3000
      - TRUST_PROXY=1
      - DATA_DIR=/data
      - MEDIA_UPLOAD_MAX=48m
      - MEDIA_VIDEO_MAX_MB=40
      - RESOLVER=127.0.0.11
      - BASE_PATH=
      - CF_CONNECTING_IP=
    volumes:
      - /volume2/docker/stacks/lab/opengym/data/database:/data
      - /volume2/docker/stacks/lab/opengym/data/coach-auth:/coach-auth
      - /volume2/docker/stacks/lab/opengym/data/media/img:/usr/share/nginx/html/img
      - /volume2/docker/stacks/lab/opengym/data/media/gif:/usr/share/nginx/html/gif
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.opengym.rule=Host(`opengym.${DESEC_DOMAIN}`)"
      - "traefik.http.services.opengym.loadbalancer.server.port=80"
      - "traefik.http.routers.opengym.entrypoints=websecure"
      - "traefik.http.routers.opengym.tls=true"
      - "traefik.http.routers.opengym.middlewares=crowdsec,secure-headers"
    networks:
      - proxy
    restart: unless-stopped

networks:
  proxy:
    external: true
  backend:
    external: true
```


