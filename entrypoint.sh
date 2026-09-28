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

# 2. Force Nginx logs to Docker console
ln -sf /dev/stdout /var/log/nginx/access.log
ln -sf /dev/stderr /var/log/nginx/error.log

# 3. Ensure variables exist for the author's Nginx template
export RESOLVER=${RESOLVER:-127.0.0.11}
export CF_CONNECTING_IP=${CF_CONNECTING_IP:-}
export BASE_PATH=${BASE_PATH:-}
export MEDIA_UPLOAD_MAX=${MEDIA_UPLOAD_MAX:-48m}
export BACKEND=127.0.0.1
export PORT=3000
export NGINX_PORT=80

# 4. Render the official openGym Nginx template
# CRITICAL FIX: We output to http.d/ instead of conf.d/ so Alpine loads it correctly.
envsubst '${BACKEND} ${PORT} ${NGINX_PORT} ${RESOLVER} ${CF_CONNECTING_IP} ${BASE_PATH} ${MEDIA_UPLOAD_MAX}' \
    < /etc/nginx/templates/default.conf.template \
    > /etc/nginx/http.d/default.conf

# 5. Start the Node API in the background
echo "Starting openGym Node API..."
node server.js &

# 6. Start Nginx in the foreground
echo "Starting Nginx proxy..."
exec nginx -g 'daemon off;'