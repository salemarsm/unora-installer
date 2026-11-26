#!/usr/bin/env bash
# install.sh — Instalação/reinstalação completa do UNORA a partir do GitHub.
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/salemarsm/unora-installer/main/install.sh | sudo bash
#
# Idempotente: seguro de rodar em instalações novas ou antigas (udba/unora).
# Preserva IOCs e resultados de análise existentes.
set -euo pipefail

# ─── Cores ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'
BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "${GREEN}✓${RESET}  $*"; }
info() { echo -e "${CYAN}→${RESET}  $*"; }
warn() { echo -e "${YELLOW}⚠${RESET}  $*"; }
die()  { echo -e "${RED}✗${RESET}  $*" >&2; exit 1; }

# ─── Parâmetros ───────────────────────────────────────────────────────────────
REPO_URL="${REPO_URL:-git@github.com:salemarsm/unora.git}"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/unora}"
SERVICE_NAME="${SERVICE_NAME:-unora}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"
OLD_DIRS=("/opt/udba")
OLD_SERVICES=("udba-api" "udba" "unora-api")

# ─── Root ─────────────────────────────────────────────────────────────────────
[[ ${EUID:-0} -eq 0 ]] || die "Precisa de root. Use: sudo bash -c \"\$(curl -fsSL ...)\""

echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════╗"
echo -e "║        UNORA — Instalação            ║"
echo -e "╚══════════════════════════════════════╝${RESET}\n"

# ─── Dependências mínimas ─────────────────────────────────────────────────────
for cmd in git curl python3; do
    command -v "$cmd" &>/dev/null || die "Dependência ausente: $cmd. Instale com: apt install $cmd"
done

# ─── Usuário do sistema ───────────────────────────────────────────────────────
# Detecta: SUDO_USER, dono do INSTALL_DIR (se existir), ou primeiro usuário ≥ 1000
INSTALL_USER="${SUDO_USER:-}"
if [[ -z "$INSTALL_USER" || "$INSTALL_USER" == "root" ]]; then
    INSTALL_USER="$(stat -c '%U' "$INSTALL_DIR" 2>/dev/null || true)"
fi
if [[ -z "$INSTALL_USER" || "$INSTALL_USER" == "root" ]]; then
    INSTALL_USER="$(getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}')"
fi
[[ -n "$INSTALL_USER" ]] || die "Não foi possível determinar o usuário. Defina: SUDO_USER=<usuario> sudo bash ..."
ok "Usuário de serviço: ${INSTALL_USER}"

# ─── Para serviços antigos ────────────────────────────────────────────────────
for svc in "${OLD_SERVICES[@]}" "$SERVICE_NAME"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        info "Parando serviço: $svc"
        systemctl stop "$svc" --no-block 2>/dev/null || true
        sleep 2
        # Força kill se ainda estiver rodando
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            systemctl kill --signal=SIGKILL "$svc" 2>/dev/null || true
            sleep 1
        fi
    fi
    systemctl disable "$svc" 2>/dev/null || true
done

# ─── Remove unit files antigos ─────────────────────────────────────────────────
# Nomes legados (udba*, unora-api, unora-update) só são removidos se apontarem
# para este INSTALL_DIR — não derruba units de OUTRAS instalações paralelas.
OLD_UNIT_BASES=("udba-api" "udba" "udba-update" "unora-api" "unora-update" "$SERVICE_NAME" "${SERVICE_NAME}-update")
_reload_needed=0
for base in "${OLD_UNIT_BASES[@]}"; do
    for suffix in ".service" ".timer"; do
        unit_file="/etc/systemd/system/${base}${suffix}"
        [[ -f "$unit_file" ]] || continue
        if [[ "$base" != udba* && "$base" != "$SERVICE_NAME" && "$base" != "${SERVICE_NAME}-update" ]] && ! grep -q "${INSTALL_DIR}" "$unit_file"; then
            info "Mantendo ${unit_file} (pertence a outra instalação)"
            continue
        fi
        info "Removendo unit file: $unit_file"
        rm -f "$unit_file"
        _reload_needed=1
    done
done
for file in /etc/sudoers.d/udba-update /etc/sudoers.d/unora-update "/etc/sudoers.d/${SERVICE_NAME}-update"; do
    if [[ -f "$file" ]]; then
        if [[ "$file" == *udba* ]] || grep -q "${INSTALL_DIR}" "$file"; then
            info "Removendo sudoers: $file"; rm -f "$file"
        else
            info "Mantendo $file (pertence a outra instalação)"
        fi
    fi
done
[[ $_reload_needed -eq 1 ]] && systemctl daemon-reload

# ─── Remove venv corrompido ───────────────────────────────────────────────────
VENV_PATH="${INSTALL_DIR}/.venv"
if [[ -d "$VENV_PATH" ]] && ! "$VENV_PATH/bin/python" -c "" &>/dev/null; then
    warn "venv corrompido — removendo para reinstalar..."
    rm -rf "$VENV_PATH"
fi

# ─── Preserva IOCs e resultados ───────────────────────────────────────────────
IOC_BACKUP=""
RESULTS_BACKUP=""
for src_dir in "${OLD_DIRS[@]}" "$INSTALL_DIR"; do
    if [[ -d "${src_dir}/indicators" && -z "$IOC_BACKUP" ]]; then
        IOC_BACKUP=$(mktemp -d)
        cp -r "${src_dir}/indicators/." "$IOC_BACKUP/"
        ok "IOCs preservados de ${src_dir}/indicators"
    fi
done

# ─── Remove instalações antigas ───────────────────────────────────────────────
for old in "${OLD_DIRS[@]}"; do
    if [[ -d "$old" ]]; then
        info "Removendo instalação antiga: $old"
        rm -rf "$old"
    fi
done

# ─── Instala ou atualiza repo ─────────────────────────────────────────────────
if [[ -d "${INSTALL_DIR}/.git" ]]; then
    info "Repositório já existe em ${INSTALL_DIR} — atualizando para ${BRANCH}..."
    sudo -u "$INSTALL_USER" git -C "$INSTALL_DIR" fetch origin "$BRANCH" --quiet
    sudo -u "$INSTALL_USER" git -C "$INSTALL_DIR" checkout "$BRANCH" --quiet
    sudo -u "$INSTALL_USER" git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
    ok "Código atualizado: $(git -C "$INSTALL_DIR" rev-parse --short HEAD)"
else
    info "Clonando ${REPO_URL} → ${INSTALL_DIR} ..."

    # Repo privado via SSH: garante chave do usuário e orienta o cadastro
    # da Deploy Key (read-only) no GitHub antes de prosseguir.
    if [[ "$REPO_URL" == git@* || "$REPO_URL" == ssh://* ]]; then
        USER_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"
        SSH_KEY="${USER_HOME}/.ssh/id_ed25519"
        sudo -H -u "$INSTALL_USER" mkdir -p "${USER_HOME}/.ssh" && chmod 700 "${USER_HOME}/.ssh"
        if [[ ! -f "$SSH_KEY" ]]; then
            sudo -H -u "$INSTALL_USER" ssh-keygen -t ed25519 -N "" -C "unora-$(hostname -s)" -f "$SSH_KEY" -q
        fi
        # Nota: NÃO usar "ssh | grep -q" direto no if — sob set -o pipefail, o
        # exit 1 do GitHub (normal, mesmo autenticado) contamina o pipeline.
        SSH_CHECK="$(sudo -H -u "$INSTALL_USER" ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 || true)"
        if ! grep -q "successfully authenticated" <<<"$SSH_CHECK"; then
            warn "O GitHub ainda não reconhece a chave deste equipamento."
            echo ""
            echo -e "${BOLD}1) Adicione a chave abaixo como Deploy Key (somente leitura):${RESET}"
            echo -e "   GitHub → repositório ${CYAN}Settings → Deploy keys → Add deploy key${RESET}"
            echo -e "   (marque ${YELLOW}NÃO${RESET} marcar 'Allow write access')"
            echo ""
            cat "${SSH_KEY}.pub"
            echo ""
            echo -e "${BOLD}2) Rode este instalador novamente.${RESET}"
            exit 2
        fi
        ok "Autenticado no GitHub como deploy key"

        # Garante host key do GitHub no known_hosts de root (clone inicial,
        # sem TTY) e do usuário (fetches futuros do timer de update).
        case "$REPO_URL" in
            git@*)   SSH_HOST="${REPO_URL#git@}"; SSH_HOST="${SSH_HOST%%:*}" ;;
            ssh://*) SSH_HOST="$(printf '%s' "$REPO_URL" | sed -E 's#^ssh://[^@]*@([^/:]+).*#\1#')" ;;
            *)       SSH_HOST="" ;;
        esac
        if [[ -n "$SSH_HOST" ]]; then
            mkdir -p /root/.ssh && chmod 700 /root/.ssh
            ssh-keyscan -H -t ed25519,rsa "$SSH_HOST" >> /root/.ssh/known_hosts 2>/dev/null || true
            ssh-keyscan -H -t ed25519,rsa "$SSH_HOST" >> "${USER_HOME}/.ssh/known_hosts" 2>/dev/null || true
        fi
    fi

    # Remove diretório não-git se existir
    [[ -d "$INSTALL_DIR" ]] && rm -rf "$INSTALL_DIR"
    # Clone como USUÁRIO (a deploy key é dele); /opt é root-owned, então o
    # diretório é criado e transferido antes. Menor privilégio: root não
    # precisa (e não ganha) chave GitHub.
    mkdir -p "$INSTALL_DIR"
    chown "${INSTALL_USER}:${INSTALL_USER}" "$INSTALL_DIR"
    sudo -H -u "$INSTALL_USER" git clone --branch "$BRANCH" --depth 50 "$REPO_URL" "$INSTALL_DIR"
    chown -R "${INSTALL_USER}:${INSTALL_USER}" "$INSTALL_DIR"
    ok "Repositório clonado: $(git -C "$INSTALL_DIR" rev-parse --short HEAD)"
fi

# ─── Instala serviço ──────────────────────────────────────────────────────────
info "Executando install-uvicorn-service.sh..."
USER_NAME="$INSTALL_USER" HOST="$HOST" PORT="$PORT" bash "${INSTALL_DIR}/scripts/install-uvicorn-service.sh"

# ─── Configura auto-update ───────────────────────────────────────────────────
info "Configurando auto-update (timer de 30min)..."
bash "${INSTALL_DIR}/scripts/setup-auto-update.sh"

# ─── Kiosk (se tiver ambiente gráfico) ───────────────────────────────────────
# NO_KIOSK=1 pula o kiosk (instalação headless/servidor).
_kiosk_configured=0
if [[ "${NO_KIOSK:-0}" == "1" ]]; then
    info "NO_KIOSK=1 — kiosk não configurado."
elif command -v lightdm &>/dev/null || command -v labwc &>/dev/null || [[ -d /etc/xdg/lxsession ]]; then
    info "Configurando modo kiosk (boot direto para UNORA)..."
    # Garante a stack do kiosk mesmo em imagens sem desktop completo
    DEBIAN_FRONTEND=noninteractive apt-get install -y chromium unclutter-xfixes || \
        warn "Falha ao instalar chromium/unclutter-xfixes — verifique manualmente."
    bash "${INSTALL_DIR}/scripts/setup-kiosk.sh"
    _kiosk_configured=1
else
    info "Ambiente gráfico não detectado — instalando stack do kiosk (lightdm + chromium)..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y lightdm lightdm-gtk-greeter chromium unclutter-xfixes; then
        info "Configurando modo kiosk..."
        bash "${INSTALL_DIR}/scripts/setup-kiosk.sh"
        _kiosk_configured=1
    else
        warn "Não foi possível instalar o ambiente gráfico — kiosk não configurado."
        warn "Execute manualmente depois: sudo apt install lightdm chromium unclutter-xfixes && sudo bash ${INSTALL_DIR}/scripts/setup-kiosk.sh"
    fi
fi

# ─── Restaura IOCs ────────────────────────────────────────────────────────────
if [[ -n "$IOC_BACKUP" && -d "$IOC_BACKUP" ]]; then
    DEST_IOCS="${INSTALL_DIR}/indicators"
    mkdir -p "$DEST_IOCS"
    cp -r "${IOC_BACKUP}/." "$DEST_IOCS/"
    chown -R "${INSTALL_USER}:${INSTALL_USER}" "$DEST_IOCS"
    rm -rf "$IOC_BACKUP"
    ok "IOCs restaurados em ${DEST_IOCS}"
fi

# ─── Verifica serviço ────────────────────────────────────────────────────────
sleep 3
if systemctl is-active --quiet "$SERVICE_NAME"; then
    ok "Serviço ${SERVICE_NAME} ativo"
    info "Baixando IOCs iniciais (pode levar alguns segundos)..."
    if sudo -u "$INSTALL_USER" "${INSTALL_DIR}/.venv/bin/python" -c \
        "from unora.common.updates import IndicatorsUpdates; IndicatorsUpdates().update()" \
        2>/dev/null; then
        ok "IOCs iniciais baixados"
    else
        warn "Falha ao baixar IOCs iniciais (sem rede?). Serão baixados pelo scheduler."
    fi
    VERSION=$(curl -sf "http://127.0.0.1:${PORT}/version" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('rest_version','?'))" 2>/dev/null || echo "?")
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════╗"
    echo -e "║   UNORA instalado com sucesso! ✓     ║"
    echo -e "╚══════════════════════════════════════╝${RESET}"
    echo -e "  Versão  : ${BOLD}${VERSION}${RESET}"
    echo -e "  Acesso  : ${CYAN}http://$(hostname -I | awk '{print $1}'):${PORT}/ui/discovery.html${RESET}"
    echo -e "  Serviço : ${CYAN}systemctl status ${SERVICE_NAME}${RESET}"
    echo -e "  Logs    : ${CYAN}journalctl -u ${SERVICE_NAME} -f${RESET}"
    echo ""
    # ─── Ativa kiosk imediatamente se lightdm já estiver rodando ─────────────
    if [[ $_kiosk_configured -eq 1 ]] && systemctl is-active --quiet lightdm 2>/dev/null; then
        echo -e "  ${CYAN}→ Reiniciando interface gráfica em 5s para ativar o kiosk...${RESET}"
        (sleep 5 && systemctl restart lightdm) &
    fi
else
    die "Serviço não iniciou. Verifique: journalctl -u ${SERVICE_NAME} -n 50"
fi
