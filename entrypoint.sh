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

# 2. FORCE Nginx logs to Docker console
mkdir -p /var/log/nginx
ln -sf /proc/1/fd/1 /var/log/nginx/access.log
ln -sf /proc/1/fd/2 /var/log/nginx/error.log

# 3. Write a bulletproof AIO Nginx config
cat << EOF > /etc/nginx/nginx.conf
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size ${MEDIA_UPLOAD_MAX:-48m};

    # Logs are now mapped to the symlinks we created
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log debug;

    server {
        listen 80;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;

        # Serve frontend files
        location / {
            try_files \$uri \$uri/ /index.html;
        }

        # Proxy API requests (stripping the /api prefix just in case Node doesn't expect it)
        location /api/ {
            rewrite ^/api/(.*)$ /\$1 break;
            proxy_pass http://127.0.0.1:3000;
            proxy_set_header Host \$http_host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOF

# 4. Start the Node API in the background
echo "Starting Node API..."
node server.js &

# 5. Start Nginx in the foreground (this keeps the container alive and logs flowing)
echo "Starting Nginx proxy..."
exec nginx -g 'daemon off;'