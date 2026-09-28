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

# 2. Write a bulletproof, AIO-specific Nginx config
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

    server {
        listen 80;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;

        # Frontend routes (React Router)
        location / {
            try_files \$uri \$uri/ /index.html;
        }

        # Backend API routes proxied to the Node server
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

# 3. Start Nginx in the background
nginx -g 'daemon on;'

# 4. Start the Node API
node server.js