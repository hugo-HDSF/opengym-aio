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

# 3. Write our own bulletproof Nginx config
cat << EOF > /etc/nginx/nginx.conf
user root;
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    client_max_body_size ${MEDIA_UPLOAD_MAX:-48m};

    # Push logs to the symlinks
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    server {
        listen 80;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;

        # Frontend routes
        location / {
            try_files \$uri \$uri/ /index.html;
        }

        # Backend API routes (Passing exactly as the API expects)
        location /api/ {
            proxy_pass http://127.0.0.1:3000;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOF

# 4. Start the Node API in the background
echo "Starting openGym Node API..."
node server.js &

# 5. Start Nginx in the foreground
echo "Starting Nginx proxy..."
exec nginx -g 'daemon off;'