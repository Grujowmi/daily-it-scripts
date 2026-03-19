#!/bin/bash
# ==========================================================
#  Script Name  : update-zabbix-proxy.sh
#
#  Written by   : Grujowmi
#  Mail         : grujowmi@proton.me
#
#  Made for IT folks who prefer automation over repetition.
#
#  License     : GPL v3
#  You are free to use, modify and share this script,
#  as long as it stays open-source and credits remain.
#
#  If this script saved you time, a PR is always welcome
# ==========================================================

set -euo pipefail

# ─── Couleurs ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Variables ──────────────────────────────────────────────
LOGFILE="/var/log/zabbix-proxy-update.log"
PACKAGE="zabbix-proxy-sqlite3"   # <-- adapter si vous utilisez mysql/pgsql
DRY_RUN=false
HOSTNAME_HOST=$(hostname -f)
DATE_RUN=$(date '+%Y-%m-%d %H:%M:%S')

# ─── Options CLI ────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --package=*) PACKAGE="${arg#*=}" ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--package=zabbix-proxy-mysql|zabbix-proxy-pgsql|zabbix-proxy-sqlite3]"
      exit 0
      ;;
  esac
done

# ─── Fonctions utilitaires ──────────────────────────────────
log() {
  local level="$1"; shift
  local msg="$*"
  local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${ts} [${level}] ${msg}" | tee -a "$LOGFILE"
}

info()    { echo -e "${CYAN}[INFO]${NC}  $*";  log INFO  "$*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*";  log OK    "$*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*";  log WARN  "$*"; }
error()   { echo -e "${RED}[ERREUR]${NC} $*"; log ERROR "$*"; }
die()     { error "$*"; exit 1; }

separator() {
  echo -e "${BOLD}────────────────────────────────────────────────────${NC}"
}

# ─── Vérifications préliminaires ────────────────────────────
check_root() {
  [[ $EUID -eq 0 ]] || die "Ce script doit être exécuté en root (sudo)."
}

check_os() {
  if ! command -v apt-get &>/dev/null; then
    die "Ce script est prévu pour Debian/Ubuntu (apt). OS non supporté."
  fi
}

check_package_installed() {
  if ! dpkg -l "$PACKAGE" 2>/dev/null | grep -q '^ii'; then
    die "Le paquet '${PACKAGE}' n'est pas installé sur ce serveur."
  fi
}

# ─── Récupère la version installée ──────────────────────────
get_installed_version() {
  dpkg -l "$PACKAGE" 2>/dev/null | awk '/^ii/ {print $3}' | head -1
}

# ─── Récupère la version disponible dans les dépôts ─────────
get_candidate_version() {
  apt-cache policy "$PACKAGE" 2>/dev/null \
    | awk '/Candidate:/ {print $2}' | head -1
}

# ─── Sauvegarde du fichier de config ────────────────────────
backup_config() {
  local config="/etc/zabbix/zabbix_proxy.conf"
  if [[ -f "$config" ]]; then
    local backup="${config}.bak_$(date '+%Y%m%d_%H%M%S')"
    cp "$config" "$backup"
    success "Config sauvegardée → ${backup}"
  else
    warn "Fichier de config introuvable : ${config}"
  fi
}

# ─── Statut du service avant/après ──────────────────────────
service_status() {
  systemctl is-active zabbix-proxy 2>/dev/null || echo "inactif"
}

# ─── Mise à jour principale ─────────────────────────────────
do_update() {
  # Force la conservation des fichiers de conf modifiés localement
  # --force-confold = garder l'ancienne version (équivalent "N" à chaque prompt)
  # --force-confdef = utiliser la valeur par défaut si pas de modif locale
  export DEBIAN_FRONTEND=noninteractive

  local APT_OPTS=(
    -o Dpkg::Options::="--force-confold"
    -o Dpkg::Options::="--force-confdef"
    --only-upgrade
    --yes
    --quiet
  )

  if $DRY_RUN; then
    warn "[DRY-RUN] Simulation uniquement — aucune modification appliquée."
    apt-get install --dry-run "${APT_OPTS[@]}" "$PACKAGE" 2>&1 | tee -a "$LOGFILE"
  else
    apt-get install "${APT_OPTS[@]}" "$PACKAGE" 2>&1 | tee -a "$LOGFILE"
  fi
}

# ─── Redémarrage du service ──────────────────────────────────
restart_service() {
  if $DRY_RUN; then
    warn "[DRY-RUN] Redémarrage simulé — zabbix-proxy non redémarré."
    return
  fi

  info "Redémarrage du service zabbix-proxy..."
  if systemctl restart zabbix-proxy; then
    sleep 2
    local status; status=$(service_status)
    if [[ "$status" == "active" ]]; then
      success "zabbix-proxy redémarré avec succès (status: ${status})"
    else
      error "zabbix-proxy ne semble pas actif après redémarrage (status: ${status})"
      journalctl -u zabbix-proxy --no-pager -n 20 | tee -a "$LOGFILE"
      exit 1
    fi
  else
    die "Échec du redémarrage de zabbix-proxy."
  fi
}

# ═══════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════
separator
echo -e "${BOLD}  Mise à jour Zabbix Proxy — Oncogard${NC}"
echo -e "  Hôte     : ${HOSTNAME_HOST}"
echo -e "  Date     : ${DATE_RUN}"
echo -e "  Paquet   : ${PACKAGE}"
$DRY_RUN && echo -e "  ${YELLOW}Mode     : DRY-RUN (simulation)${NC}"
separator

check_root
check_os
check_package_installed

# Versions avant mise à jour
VERSION_BEFORE=$(get_installed_version)
info "Version installée actuellement : ${VERSION_BEFORE}"

# Mise à jour du cache apt
info "Mise à jour du cache apt..."
if ! $DRY_RUN; then
  apt-get update -q 2>&1 | tee -a "$LOGFILE"
fi

VERSION_CANDIDATE=$(get_candidate_version)
info "Version disponible dans les dépôts : ${VERSION_CANDIDATE}"

# Vérifier si une mise à jour est nécessaire
if [[ "$VERSION_BEFORE" == "$VERSION_CANDIDATE" ]]; then
  success "Zabbix Proxy est déjà à jour (${VERSION_BEFORE}). Rien à faire."
  separator
  exit 0
fi

info "Mise à jour disponible : ${VERSION_BEFORE} → ${VERSION_CANDIDATE}"

# Sauvegarde préventive de la config
backup_config

# Statut avant
STATUS_BEFORE=$(service_status)
info "Statut du service avant mise à jour : ${STATUS_BEFORE}"

# Mise à jour
separator
info "Lancement de la mise à jour (configs custom conservées automatiquement)..."
do_update

# Version après
VERSION_AFTER=$(get_installed_version)
separator

if [[ "$VERSION_AFTER" == "$VERSION_CANDIDATE" ]] || $DRY_RUN; then
  success "Mise à jour réussie : ${VERSION_BEFORE} → ${VERSION_AFTER}"
else
  error "La version après mise à jour (${VERSION_AFTER}) ne correspond pas à l'attendu (${VERSION_CANDIDATE})."
fi

# Redémarrage
restart_service

# Résumé final
separator
echo -e "${BOLD}  Résumé de la mise à jour${NC}"
echo -e "  Hôte         : ${HOSTNAME_HOST}"
echo -e "  Version avant : ${VERSION_BEFORE}"
echo -e "  Version après : ${VERSION_AFTER}"
echo -e "  Service       : $(service_status)"
echo -e "  Log           : ${LOGFILE}"
separator
success "Terminé."
