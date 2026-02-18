#!/bin/bash
# ============================================================
# FARA CRM Demo Manager
# Интерактивное управление демо-инстансом
# ============================================================

set -euo pipefail

# ── Config ───────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
CRON_LOG="/var/log/faracrm-demo-reset.log"
BACKEND_URL="http://localhost:8000/api/"
HEALTH_TIMEOUT=120

# ── Colors ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ──────────────────────────────────────────────
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }
info() { echo -e "${BLUE}[→]${NC} $*"; }

confirm() {
    echo -en "${YELLOW}    Продолжить? [y/N]: ${NC}"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

wait_backend() {
    info "Ожидание backend..."
    local elapsed=0
    while [ $elapsed -lt $HEALTH_TIMEOUT ]; do
        if curl -sf "$BACKEND_URL" > /dev/null 2>&1; then
            log "Backend готов! (${elapsed}s)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -ne "\r    ${elapsed}s / ${HEALTH_TIMEOUT}s..."
    done
    echo
    err "Backend не ответил за ${HEALTH_TIMEOUT}s"
    return 1
}

# ── Actions ──────────────────────────────────────────────

do_reset_now() {
    echo
    echo -e "${BOLD}  Сброс демо-инстанса${NC}"
    echo -e "  Будут выполнены:"
    echo -e "    1. ${CYAN}docker compose down${NC} — остановка контейнеров"
    echo -e "    2. ${CYAN}docker volume rm pgdata${NC} — удаление БД"
    echo -e "    3. ${CYAN}docker compose up -d${NC} — запуск (post_init создаст данные)"
    echo
    confirm || { warn "Отменено."; return; }

    echo
    info "Останавливаю контейнеры..."
    docker compose -f "$COMPOSE_FILE" down --timeout 10
    log "Контейнеры остановлены"

    info "Удаляю PostgreSQL volume..."
    # Имя volume: {project}_{volume} — берём из compose
    local pg_volumes
    pg_volumes=$(docker volume ls -q | grep -E "pgdata" || true)
    if [ -n "$pg_volumes" ]; then
        echo "$pg_volumes" | xargs docker volume rm -f
        log "Volumes удалены: $pg_volumes"
    else
        warn "PostgreSQL volumes не найдены (возможно уже удалены)"
    fi

    info "Запускаю контейнеры..."
    docker compose -f "$COMPOSE_FILE" up -d
    log "Контейнеры запущены"

    wait_backend

    echo
    log "Демо сброшен. Чистая БД с данными post_init."
}

do_status() {
    echo
    echo -e "${BOLD}  Статус контейнеров:${NC}"
    echo
    docker compose -f "$COMPOSE_FILE" ps 2>/dev/null || err "docker compose не запущен"

    echo
    echo -e "${BOLD}  Volumes:${NC}"
    docker volume ls | grep -E "pgdata|filestore" || echo "    (нет volumes)"

    echo
    echo -e "${BOLD}  Cron:${NC}"
    local cron_entry
    cron_entry=$(crontab -l 2>/dev/null | grep "demo-reset" || true)
    if [ -n "$cron_entry" ]; then
        echo -e "    ${GREEN}Активен:${NC} $cron_entry"
    else
        echo -e "    ${YELLOW}Не настроен${NC}"
    fi

    echo
    echo -e "${BOLD}  Systemd timer:${NC}"
    if systemctl is-active demo-reset.timer &>/dev/null; then
        echo -e "    ${GREEN}Активен${NC}"
        systemctl list-timers demo-reset.timer --no-pager 2>/dev/null | tail -2
    else
        echo -e "    ${YELLOW}Не настроен${NC}"
    fi
    echo
}

ask_period() {
    echo -e "  Выберите период сброса:"
    echo -e "    ${BOLD}1)${NC}  Каждые 30 минут"
    echo -e "    ${BOLD}2)${NC}  Каждый час"
    echo -e "    ${BOLD}3)${NC}  Каждые 2 часа"
    echo -e "    ${BOLD}4)${NC}  Каждые 6 часов"
    echo -e "    ${BOLD}5)${NC}  Каждые 12 часов"
    echo -e "    ${BOLD}6)${NC}  Раз в сутки (00:00)"
    echo
    echo -en "  ${BOLD}Выбор [1-6]: ${NC}"
    read -r period_choice
    case "$period_choice" in
        1) CHOSEN_CRON="*/30 * * * *"; CHOSEN_CALENDAR="*:00/30:00"; CHOSEN_LABEL="каждые 30 минут" ;;
        2) CHOSEN_CRON="0 * * * *";    CHOSEN_CALENDAR="*:00:00";    CHOSEN_LABEL="каждый час" ;;
        3) CHOSEN_CRON="0 */2 * * *";  CHOSEN_CALENDAR="0/2:00:00";  CHOSEN_LABEL="каждые 2 часа" ;;
        4) CHOSEN_CRON="0 */6 * * *";  CHOSEN_CALENDAR="0/6:00:00";  CHOSEN_LABEL="каждые 6 часов" ;;
        5) CHOSEN_CRON="0 */12 * * *"; CHOSEN_CALENDAR="0/12:00:00"; CHOSEN_LABEL="каждые 12 часов" ;;
        6) CHOSEN_CRON="0 0 * * *";    CHOSEN_CALENDAR="*-*-* 00:00:00"; CHOSEN_LABEL="раз в сутки" ;;
        *) err "Неверный выбор"; return 1 ;;
    esac
}

do_setup_cron() {
    echo
    echo -e "${BOLD}  Настройка Cron${NC}"
    echo
    ask_period || return
    echo
    echo -e "  Будет добавлено в crontab (${GREEN}${CHOSEN_LABEL}${NC}):"
    echo -e "    ${CYAN}${CHOSEN_CRON} ${SCRIPT_DIR}/demo-manager.sh --reset >> ${CRON_LOG} 2>&1${NC}"
    echo

    # Проверяем нет ли уже
    local existing
    existing=$(crontab -l 2>/dev/null | grep "demo-manager.sh\|demo-reset" || true)
    if [ -n "$existing" ]; then
        warn "Уже есть запись в crontab:"
        echo "    $existing"
        echo -en "${YELLOW}    Заменить? [y/N]: ${NC}"
        read -r answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            warn "Отменено."
            return
        fi
        # Удаляем старую запись
        crontab -l 2>/dev/null | grep -v "demo-manager.sh\|demo-reset" | crontab -
        log "Старая запись удалена"
    else
        confirm || { warn "Отменено."; return; }
    fi

    # Добавляем новую
    (crontab -l 2>/dev/null; echo "${CHOSEN_CRON} ${SCRIPT_DIR}/demo-manager.sh --reset >> ${CRON_LOG} 2>&1") | crontab -
    log "Cron задача создана (${CHOSEN_LABEL})"
    log "Логи: tail -f ${CRON_LOG}"
    echo
}

do_remove_cron() {
    echo
    local existing
    existing=$(crontab -l 2>/dev/null | grep "demo-manager.sh\|demo-reset" || true)
    if [ -z "$existing" ]; then
        warn "Cron задача не найдена"
        return
    fi
    echo -e "  Удаляю: ${CYAN}${existing}${NC}"
    confirm || { warn "Отменено."; return; }

    crontab -l 2>/dev/null | grep -v "demo-manager.sh\|demo-reset" | crontab -
    log "Cron задача удалена"
    echo
}

do_setup_systemd() {
    echo
    echo -e "${BOLD}  Настройка Systemd Timer${NC}"
    echo
    ask_period || return
    echo
    echo -e "  Будут созданы (${GREEN}${CHOSEN_LABEL}${NC}):"
    echo -e "    ${CYAN}/etc/systemd/system/demo-reset.service${NC}"
    echo -e "    ${CYAN}/etc/systemd/system/demo-reset.timer${NC}"
    echo
    confirm || { warn "Отменено."; return; }

    # Service unit
    cat > /etc/systemd/system/demo-reset.service << EOF
[Unit]
Description=FARA CRM Demo Reset
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/demo-manager.sh --reset
WorkingDirectory=${SCRIPT_DIR}
StandardOutput=journal
StandardError=journal
TimeoutStartSec=300
EOF
    log "Service создан"

    # Timer unit
    cat > /etc/systemd/system/demo-reset.timer << EOF
[Unit]
Description=FARA CRM Demo Reset — ${CHOSEN_LABEL}

[Timer]
OnCalendar=${CHOSEN_CALENDAR}
RandomizedDelaySec=30
Persistent=true

[Install]
WantedBy=timers.target
EOF
    log "Timer создан"

    systemctl daemon-reload
    systemctl enable --now demo-reset.timer
    log "Timer активирован (${CHOSEN_LABEL})"

    echo
    echo -e "  Проверка:"
    systemctl list-timers demo-reset.timer --no-pager
    echo
    log "Логи: journalctl -u demo-reset.service -f"
    echo
}

do_remove_systemd() {
    echo
    if ! systemctl is-enabled demo-reset.timer &>/dev/null; then
        warn "Systemd timer не настроен"
        return
    fi
    echo -e "  Удаляю systemd timer и service..."
    confirm || { warn "Отменено."; return; }

    systemctl disable --now demo-reset.timer 2>/dev/null || true
    rm -f /etc/systemd/system/demo-reset.service
    rm -f /etc/systemd/system/demo-reset.timer
    systemctl daemon-reload
    log "Systemd timer удалён"
    echo
}

do_logs() {
    echo
    echo -e "${BOLD}  Логи:${NC}"
    echo

    if [ -f "$CRON_LOG" ]; then
        echo -e "  ${CYAN}Cron log (последние 30 строк):${NC}"
        tail -30 "$CRON_LOG"
    fi

    if systemctl is-active demo-reset.timer &>/dev/null; then
        echo -e "  ${CYAN}Systemd journal (последние 30 строк):${NC}"
        journalctl -u demo-reset.service --no-pager -n 30
    fi

    if [ ! -f "$CRON_LOG" ] && ! systemctl is-active demo-reset.timer &>/dev/null; then
        warn "Нет логов (ни cron, ни systemd не настроены)"
    fi
    echo
}

# ── Non-interactive mode ─────────────────────────────────
if [[ "${1:-}" == "--reset" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEMO-RESET: Starting..."

    cd "$SCRIPT_DIR"
    docker compose -f "$COMPOSE_FILE" down --timeout 10

    pg_volumes=$(docker volume ls -q | grep -E "pgdata" || true)
    [ -n "$pg_volumes" ] && echo "$pg_volumes" | xargs docker volume rm -f

    docker compose -f "$COMPOSE_FILE" up -d

    elapsed=0
    while [ $elapsed -lt $HEALTH_TIMEOUT ]; do
        if curl -sf "$BACKEND_URL" > /dev/null 2>&1; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEMO-RESET: Backend ready (${elapsed}s)"
            exit 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEMO-RESET: WARNING — backend not ready in ${HEALTH_TIMEOUT}s"
    exit 1
fi

# ── Interactive Menu ─────────────────────────────────────

show_menu() {
    clear
    echo
    echo -e "${BOLD}  ╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║       ${CYAN}FARA CRM Demo Manager${NC}${BOLD}             ║${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════════╝${NC}"
    echo
    echo -e "  ${BOLD}1)${NC}  🔄  Сбросить демо сейчас"
    echo -e "  ${BOLD}2)${NC}  📊  Статус"
    echo -e "  ${BOLD}3)${NC}  ⏰  Настроить Cron (каждый час)"
    echo -e "  ${BOLD}4)${NC}  🗑   Удалить Cron"
    echo -e "  ${BOLD}5)${NC}  ⚙️   Настроить Systemd Timer (каждый час)"
    echo -e "  ${BOLD}6)${NC}  🗑   Удалить Systemd Timer"
    echo -e "  ${BOLD}7)${NC}  📋  Посмотреть логи"
    echo -e "  ${BOLD}0)${NC}  🚪  Выход"
    echo
    echo -en "  ${BOLD}Выбор [0-7]: ${NC}"
}

while true; do
    show_menu
    read -r choice
    case "$choice" in
        1) do_reset_now ;;
        2) do_status ;;
        3) do_setup_cron ;;
        4) do_remove_cron ;;
        5) do_setup_systemd ;;
        6) do_remove_systemd ;;
        7) do_logs ;;
        0) echo; log "До свидания!"; exit 0 ;;
        *) err "Неверный выбор" ;;
    esac
    echo -en "  ${BOLD}Нажмите Enter для продолжения...${NC}"
    read -r
done
