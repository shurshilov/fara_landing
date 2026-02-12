#!/bin/bash
# ══════════════════════════════════════════════════
# Первичная настройка SSL-сертификатов
# Запустить один раз: ./init-ssl.sh
# ══════════════════════════════════════════════════

set -e

DOMAIN="faracrm.com"
EMAIL="shurshilov.a@yandex.ru"

echo "=== 1. Создаём папки ==="
mkdir -p certbot/conf certbot/www nginx/conf.d

echo "=== 2. Проверяем DNS ==="
DNS_FAIL=0
for sub in "" "www." "demo." "docs."; do
    host="${sub}${DOMAIN}"
    echo -n "  $host → "
    ip=$(dig +short "$host" A 2>/dev/null | head -1)
    if [ -z "$ip" ]; then
        echo "❌ НЕ НАЙДЕН! Добавь A-запись в DNS."
        DNS_FAIL=1
    else
        echo "✅ $ip"
    fi
done

if [ "$DNS_FAIL" = "1" ]; then
    echo ""
    echo "⚠️  Некоторые DNS-записи не настроены."
    read -p "Продолжить всё равно? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Отменено. Настрой DNS и запусти снова."
        exit 1
    fi
fi

echo "=== 3. Временный nginx (только HTTP для ACME) ==="

# Сохраняем SSL-конфиги
for f in nginx/conf.d/*.conf; do
    [ -f "$f" ] && cp "$f" "$f.bak"
done

# Временный конфиг без SSL
cat > nginx/conf.d/00-temp.conf << 'EOF'
server {
    listen 80;
    server_name faracrm.com www.faracrm.com demo.faracrm.com docs.faracrm.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 'SSL setup in progress...';
        add_header Content-Type text/plain;
    }
}
EOF

# Убираем SSL-конфиги (nginx не стартанёт без сертификатов)
rm -f nginx/conf.d/01-landing.conf nginx/conf.d/02-demo.conf nginx/conf.d/03-docs.conf

docker compose up -d nginx-proxy
sleep 3

echo "=== 4. Запрашиваем сертификат ==="
docker compose run --rm --entrypoint "" certbot certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    -d "$DOMAIN" \
    -d "www.$DOMAIN" \
    -d "demo.$DOMAIN" \
    -d "docs.$DOMAIN"

echo "=== 5. Восстанавливаем SSL-конфиги ==="
rm -f nginx/conf.d/00-temp.conf
for f in nginx/conf.d/*.conf.bak; do
    [ -f "$f" ] && mv "$f" "${f%.bak}"
done

echo "=== 6. Перезапускаем всё ==="
docker compose down
docker compose up -d

echo ""
echo "✅ SSL настроен!"
echo "   https://faracrm.com"
echo "   https://demo.faracrm.com"
echo "   https://docs.faracrm.com"
