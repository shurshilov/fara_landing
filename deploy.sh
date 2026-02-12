#!/bin/bash
# ============================================
# FARA CRM Landing — Deploy on fresh VPS
# ============================================
# Usage:
#   1. Copy project to VPS:  scp -r . user@your-server:/opt/fara-landing
#   2. SSH into server:      ssh user@your-server
#   3. Run:                  cd /opt/fara-landing && chmod +x deploy.sh && sudo ./deploy.sh
# ============================================

set -e

DOMAIN="${1:-faracrm.com}"
EMAIL="${2:-shurshilov.a@yandex.ru}"

echo "🚀 FARA CRM Landing deploy"
echo "   Domain: $DOMAIN"
echo "   Email:  $EMAIL"
echo ""

# ---- 1. Install Docker (if not installed) ----
if ! command -v docker &> /dev/null; then
    echo "📦 Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo "✅ Docker installed"
else
    echo "✅ Docker already installed"
fi

# ---- 2. Install Docker Compose plugin (if not installed) ----
if ! docker compose version &> /dev/null; then
    echo "📦 Installing Docker Compose..."
    apt-get update && apt-get install -y docker-compose-plugin
    echo "✅ Docker Compose installed"
else
    echo "✅ Docker Compose already installed"
fi

# ---- 3. Build and run (HTTP first) ----
echo "🔨 Building landing..."
docker compose build --no-cache
docker compose up -d

echo "✅ Landing running on http://$DOMAIN"
echo ""

# ---- 4. SSL with Let's Encrypt (optional) ----
read -p "🔒 Setup SSL for $DOMAIN? (y/n): " SETUP_SSL

if [ "$SETUP_SSL" = "y" ]; then
    echo "🔒 Getting SSL certificate..."

    # Create certbot dirs
    mkdir -p certbot/conf certbot/www

    # Stop current container
    docker compose down

    # Get certificate with standalone mode
    docker run --rm -it \
        -p 80:80 \
        -v "./certbot/conf:/etc/letsencrypt" \
        -v "./certbot/www:/var/www/certbot" \
        certbot/certbot certonly \
        --standalone \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN" \
        -d "www.$DOMAIN"

    # Create SSL nginx config
    cat > nginx-ssl.conf << NGINXEOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\\\$host\\\$request_uri; }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_vary on;
    gzip_min_length 256;
    gzip_types text/plain text/css text/javascript application/javascript application/json image/svg+xml font/woff font/woff2;

    location ~* \\.(jpg|jpeg|png|gif|webp|svg|ico|woff|woff2|ttf|eot)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location ~* \\.(css|js)\$ {
        expires 7d;
        add_header Cache-Control "public";
    }

    location / {
        try_files \\\$uri \\\$uri/ /index.html;
    }

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
}
NGINXEOF

    # Update docker-compose for SSL
    cat > docker-compose.yml << DCEOF
services:
  landing:
    build: .
    container_name: fara-landing
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./certbot/conf:/etc/letsencrypt:ro
      - ./certbot/www:/var/www/certbot:ro
      - ./nginx-ssl.conf:/etc/nginx/conf.d/default.conf:ro

  certbot:
    image: certbot/certbot
    container_name: fara-certbot
    restart: unless-stopped
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait \$\${!}; done;'"
DCEOF

    # Rebuild and run with SSL
    docker compose build --no-cache
    docker compose up -d

    echo "✅ SSL configured! https://$DOMAIN"
else
    echo "ℹ️  Skipping SSL. Run this script again to add it later."
fi

echo ""
echo "============================================"
echo "✅ Deploy complete!"
echo ""
echo "Commands:"
echo "  docker compose logs -f    # view logs"
echo "  docker compose restart    # restart"
echo "  docker compose down       # stop"
echo "  docker compose up -d --build  # rebuild & run"
echo "============================================"
