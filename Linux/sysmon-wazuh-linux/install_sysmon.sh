#!/bin/bash
# =============================================================================
# install_sysmon.sh - Installation Sysmon for Linux
# Compatible : Debian 11/12/13, Ubuntu 22.04/24.04
# Author: Grujowmi
# Stratégie :
#   - Debian 11/12 + Ubuntu : repo Microsoft (apt)
#   - Debian 13 (Trixie)    : .deb directs depuis GitHub
#     (repo MS non supporté + clé SHA1 rejetée depuis 2026-02-01)
# =============================================================================
set -e

LOG="/var/log/sysmon-install.log"
CONFIG_SOURCE="/var/ossec/etc/shared/sysmon-linux.xml"
CONFIG_TARGET="/etc/sysmon/sysmon-linux.xml"
WATCHER_SCRIPT="/usr/local/bin/sysmon-watcher.sh"
SERVICE_FILE="/etc/systemd/system/sysmon-watcher.service"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"; }

# -----------------------------------------------------------------------------
# 0. Root check
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit être exécuté en root."
    exit 1
fi

log "=== Début installation Sysmon for Linux ==="

# -----------------------------------------------------------------------------
# 1. Détection distribution
# -----------------------------------------------------------------------------
[ ! -f /etc/os-release ] && { log "ERREUR: /etc/os-release introuvable."; exit 1; }
. /etc/os-release
log "Distribution : $NAME $VERSION_ID"

case "$ID" in
    debian|ubuntu) ;;
    *) log "ERREUR: Distribution non supportée ($ID)."; exit 1 ;;
esac

# -----------------------------------------------------------------------------
# 2. Dépendances communes
# -----------------------------------------------------------------------------
log "Installation des dépendances..."
apt-get update -qq
apt-get install -y -qq curl wget inotify-tools apt-transport-https libxml2-utils

# -----------------------------------------------------------------------------
# 3. Installation Sysmon
# -----------------------------------------------------------------------------

install_via_microsoft_repo() {
    local DISTRO="$1" VERSION="$2"
    log "Méthode : repo Microsoft (${DISTRO} ${VERSION})..."
    wget -q "https://packages.microsoft.com/config/${DISTRO}/${VERSION}/packages-microsoft-prod.deb" \
        -O /tmp/packages-microsoft-prod.deb
    dpkg -i /tmp/packages-microsoft-prod.deb >> "$LOG" 2>&1
    apt-get update -qq
    apt-get install -y sysinternalsebpf >> "$LOG" 2>&1
    apt-get install -y sysmonforlinux   >> "$LOG" 2>&1
}

install_via_github() {
    log "Méthode : GitHub .deb (Debian 13+, repo MS non supporté)..."

    # libssl-dev disponible dans les repos Debian standards
    apt-get install -y -qq libssl-dev

    # sysinternalsebpf
    log "Téléchargement sysinternalsebpf..."
    EBPF_URL=$(curl -Ls https://api.github.com/repos/microsoft/SysinternalsEBPF/releases/latest \
        | grep "browser_download_url.*amd64\.deb" | cut -d '"' -f 4)
    [ -z "$EBPF_URL" ] && { log "ERREUR: URL sysinternalsebpf introuvable."; exit 1; }
    log "URL : $EBPF_URL"
    curl -Ls "$EBPF_URL" -o /tmp/sysinternalsebpf.deb
    dpkg -i /tmp/sysinternalsebpf.deb >> "$LOG" 2>&1 || apt-get install -f -y -qq >> "$LOG" 2>&1

    # sysmonforlinux
    log "Téléchargement sysmonforlinux..."
    SYSMON_URL=$(curl -Ls https://api.github.com/repos/microsoft/SysmonForLinux/releases/latest \
        | grep "browser_download_url.*amd64\.deb" | cut -d '"' -f 4)
    [ -z "$SYSMON_URL" ] && { log "ERREUR: URL sysmonforlinux introuvable."; exit 1; }
    log "URL : $SYSMON_URL"
    curl -Ls "$SYSMON_URL" -o /tmp/sysmonforlinux.deb
    dpkg -i /tmp/sysmonforlinux.deb >> "$LOG" 2>&1 || apt-get install -f -y -qq >> "$LOG" 2>&1
}

# Sélection méthode
if   [ "$ID" = "debian" ] && [ "${VERSION_ID%%.*}" -ge 13 ]; then install_via_github
elif [ "$ID" = "debian" ]; then install_via_microsoft_repo "debian" "${VERSION_ID%%.*}"
elif [ "$ID" = "ubuntu" ]; then install_via_microsoft_repo "ubuntu" "$VERSION_ID"
fi

command -v sysmon &>/dev/null || { log "ERREUR: sysmon non disponible après install."; exit 1; }
log "Sysmon : $(sysmon --version 2>&1 | head -1)"

# -----------------------------------------------------------------------------
# 4. Config et démarrage Sysmon
# -----------------------------------------------------------------------------
mkdir -p /etc/sysmon

if [ -f "$CONFIG_SOURCE" ]; then
    cp "$CONFIG_SOURCE" "$CONFIG_TARGET"
    log "Config copiée depuis Wazuh shared."
    sysmon -accepteula -i "$CONFIG_TARGET" >> "$LOG" 2>&1
else
    log "ATTENTION: $CONFIG_SOURCE absent. Démarrage minimal (en attente du push Wazuh)."
    sysmon -accepteula -i >> "$LOG" 2>&1
fi

systemctl enable --now sysmon >> "$LOG" 2>&1
log "Service sysmon : $(systemctl is-active sysmon)"

# -----------------------------------------------------------------------------
# 5. sysmon-watcher (inotify -> rechargement auto dès push Wazuh)
# -----------------------------------------------------------------------------
log "Déploiement sysmon-watcher..."

cat > "$WATCHER_SCRIPT" << 'WATCHER_EOF'
#!/bin/bash
CONFIG_SOURCE="/var/ossec/etc/shared/sysmon-linux.xml"
CONFIG_TARGET="/etc/sysmon/sysmon-linux.xml"
WATCH_DIR="$(dirname $CONFIG_SOURCE)"
WATCH_FILE="$(basename $CONFIG_SOURCE)"

# Attente fichier source (délai boot agent Wazuh)
while [ ! -f "$CONFIG_SOURCE" ]; do
    logger -t sysmon-watcher "En attente du fichier config Wazuh..."
    sleep 30
done

logger -t sysmon-watcher "Surveillance démarrée sur $WATCH_DIR ($WATCH_FILE)"

# Wazuh écrit via fichier temporaire + MOVED_TO (rename atomique)
# → surveiller le répertoire, pas le fichier directement
inotifywait -m -e moved_to,close_write --format '%f' "$WATCH_DIR" 2>/dev/null \
| grep --line-buffered "^${WATCH_FILE}$" \
| while read -r FILE; do
    logger -t sysmon-watcher "Changement détecté, rechargement Sysmon..."

    if ! xmllint --noout "$CONFIG_SOURCE" 2>/dev/null; then
        logger -t sysmon-watcher "ERREUR: XML invalide, rechargement annulé."
        continue
    fi

    cp "$CONFIG_SOURCE" "$CONFIG_TARGET"

    if sysmon -c "$CONFIG_TARGET" >> /var/log/sysmon-install.log 2>&1; then
        logger -t sysmon-watcher "Config rechargée avec succès."
    else
        logger -t sysmon-watcher "ERREUR: Échec rechargement Sysmon."
    fi
done
WATCHER_EOF

chmod 750 "$WATCHER_SCRIPT"

cat > "$SERVICE_FILE" << 'SERVICE_EOF'
[Unit]
Description=Sysmon config watcher (inotify)
After=wazuh-agent.service sysmon.service
Requires=sysmon.service

[Service]
Type=simple
ExecStart=/usr/local/bin/sysmon-watcher.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable --now sysmon-watcher >> "$LOG" 2>&1

# -----------------------------------------------------------------------------
# 6. Résumé
# -----------------------------------------------------------------------------
log "=== Installation terminée ==="
log "  sysmon         : $(systemctl is-active sysmon)"
log "  sysmon-watcher : $(systemctl is-active sysmon-watcher)"
log "  Config source  : $CONFIG_SOURCE"
log "  Config active  : $CONFIG_TARGET"
echo ""
echo "Vérification : journalctl -u sysmon-watcher -f"
