# Stage 1: Grab the compiled frontend website
FROM ghcr.io/duartesantos8/opengym-web:latest AS web-source

# Stage 2: Base on the official API
FROM ghcr.io/duartesantos8/opengym-api:latest

USER root

# Install Nginx and Git (works for both Debian and Alpine)
RUN (apt-get update && apt-get install -y nginx git) || (apk update && apk add --no-cache nginx git)

# Copy ONLY the static frontend files (leave their messy Nginx configs behind)
COPY --from=web-source /usr/share/nginx/html /usr/share/nginx/html

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV PORT=3000

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]