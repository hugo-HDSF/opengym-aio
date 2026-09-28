#!/bin/sh

# 1. Download media if missing
mkdir -p /usr/share/nginx/html/img /usr/share/nginx/html/gif
if [ -z "$(ls -A /usr/share/nginx/html/img 2>/dev/null)" ]; then
    echo "Downloading exercise media..."
    git clone --depth 1 https://github.com/hasaneyldrm/exercises-dataset /tmp/ds
    cp /tmp/ds/images/*.jpg /usr/share/nginx/html/img/
    cp /tmp/ds/videos/*.gif /usr/share/nginx/html/gif/
    rm -rf /tmp/ds
fi

# 2. Ensure defaults exist so Nginx templates don't break
export RESOLVER=${RESOLVER:-127.0.0.11}
export CF_CONNECTING_IP=${CF_CONNECTING_IP:-}
export BASE_PATH=${BASE_PATH:-}
export MEDIA_UPLOAD_MAX=${MEDIA_UPLOAD_MAX:-48m}

# Ensure configuration directory exists
mkdir -p /etc/nginx/conf.d

# 3. Render Nginx configuration
envsubst '${BACKEND} ${PORT} ${NGINX_PORT} ${RESOLVER} ${CF_CONNECTING_IP} ${BASE_PATH} ${MEDIA_UPLOAD_MAX}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf

# 4. Start Nginx in the background
nginx -g 'daemon on;'

# 5. Start the Node API (openGym uses server.js)
node server.js