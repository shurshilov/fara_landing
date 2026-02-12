# FARA CRM — Production Deploy

## Архитектура

```
Internet
   │
   ▼
nginx-proxy (:80/:443)  ← этот docker-compose (лендинг)
   │
   ├── faracrm.com      → landing контейнер (сеть: proxy)
   ├── demo.faracrm.com → frontend + backend (сеть: crm, из основного проекта)
   └── docs.faracrm.com → backend /docs-dev/ (сеть: crm)
```

## Структура на сервере

```
/opt/fara/
├── landing/                      # Этот проект (лендинг + reverse proxy)
│   ├── docker-compose.yml
│   ├── init-ssl.sh
│   ├── Dockerfile                # Сборка лендинга
│   ├── index.html
│   ├── nginx.conf                # Nginx конфиг лендинга (внутренний)
│   ├── nginx/
│   │   └── conf.d/
│   │       ├── 01-landing.conf   # faracrm.com
│   │       ├── 02-demo.conf      # demo.faracrm.com
│   │       └── 03-docs.conf      # docs.faracrm.com
│   └── certbot/                  # Авто-создаётся
│
└── faracrm_new/                  # Основной проект (НЕ МЕНЯТЬ)
    ├── docker-compose.yml
    ├── docker/
    ├── backend/
    └── frontend/
```

## Порядок запуска

```bash
# 1. Сначала запустить основной проект (создаст сеть)
cd /opt/fara/faracrm_new
docker compose up -d

# 2. Узнать имя сети
docker network ls | grep default
# Пример: faracrm_new_default

# 3. Обновить имя сети в landing/docker-compose.yml (networks.crm.name)

# 4. Настроить DNS (A-записи на IP сервера):
#    faracrm.com, www.faracrm.com, demo.faracrm.com, docs.faracrm.com

# 5. Получить SSL и запустить лендинг
cd /opt/fara/landing
chmod +x init-ssl.sh
./init-ssl.sh
```

## Обновление CRM

```bash
cd /opt/fara/faracrm_new
git pull
docker compose up --build -d backend frontend

# Перезагрузить proxy чтобы подхватил новые контейнеры
cd /opt/fara/landing
docker compose restart nginx-proxy
```

## Обновление лендинга

```bash
cd /opt/fara/landing
git pull
docker compose up --build -d landing
```

## Обновление SSL (автоматическое)

Certbot автоматически обновляет сертификаты каждые 12 часов.
Для ручного обновления:

```bash
cd /opt/fara/landing
docker compose run --rm certbot renew
docker compose exec nginx-proxy nginx -s reload
```
