# Stage 1: Grab the pre-built frontend files
FROM ghcr.io/duartesantos8/opengym-web:latest AS web-source

# Stage 2: Use the official API as our base so Node.js is perfectly configured
FROM ghcr.io/duartesantos8/opengym-api:latest

USER root

# Install Nginx and Git (handles both Debian and Alpine bases just in case)
RUN (apt-get update && apt-get install -y nginx git gettext-base) || (apk update && apk add --no-cache nginx git gettext)

# Bring over the Nginx templates and compiled static files from Stage 1
COPY --from=web-source /etc/nginx/templates /etc/nginx/templates
COPY --from=web-source /usr/share/nginx/html /usr/share/nginx/html

# Copy our custom startup script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Force Nginx to look for the API on localhost inside this shared container
ENV PORT=3000
ENV BACKEND=127.0.0.1
ENV NGINX_PORT=80

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]