# ==========================================================
#  Script Name  : Secure-ZabbixPSK-GPO.ps1
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
# Script de sécurisation du PSK Zabbix - Exécution au démarrage (Task scheduler by GPO)

$pskPath = "C:\Program Files\Zabbix Agent 2\psk.key"
$flagFile = "C:\Windows\Temp\.zabbix-psk-secured"

# Si déjà sécurisé, sortir immédiatement (pas d'impact perf)
if (Test-Path $flagFile) {
    exit 0
}

# Si le fichier PSK n'existe pas encore, sortir (Zabbix pas encore installé)
if (-not (Test-Path $pskPath)) {
    exit 0
}

# Sécuriser le PSK
try {
    # Désactive l'héritage
    icacls $pskPath /inheritance:d 2>&1 | Out-Null
    
    # Retire les droits utilisateurs
    icacls $pskPath /remove "BUILTIN\Utilisateurs" 2>&1 | Out-Null
    
    # Vérifie le succès
    $check = icacls $pskPath | Out-String
    if ($check -notmatch "Utilisateurs") {
        # Crée le flag pour ne plus réexécuter
        "Secured on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $flagFile -Force
    }
} catch {
    # Erreur silencieuse, réessaiera au prochain démarrage
}

exit 0