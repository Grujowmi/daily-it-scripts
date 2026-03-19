# 🔄 Zabbix Proxy Auto-Updater

Script de mise à jour automatique du **Zabbix Proxy** pour Debian/Ubuntu.  
Conçu pour fonctionner en mode **entièrement non-interactif** : conserve systématiquement les fichiers de configuration personnalisés sans aucune intervention manuelle.

---

## ✨ Fonctionnalités

- ✅ Vérifie si une mise à jour est disponible avant de faire quoi que ce soit
- ✅ **Conserve automatiquement tous les fichiers de configuration modifiés** (`--force-confold`)
- ✅ Sauvegarde horodatée de `zabbix_proxy.conf` avant chaque mise à jour
- ✅ Redémarre le service et vérifie qu'il est bien actif après la MAJ
- ✅ Log complet dans `/var/log/zabbix-proxy-update.log`
- ✅ Mode `--dry-run` pour simuler sans rien modifier
- ✅ Compatible avec les variants `sqlite3`, `mysql` et `pgsql`

---

## 📋 Prérequis

- Debian 11/12 ou Ubuntu 22.04/24.04
- `zabbix-proxy-*` déjà installé et configuré
- Dépôt officiel Zabbix configuré dans apt
- Droits `root` ou `sudo`

---

## 🚀 Installation

### 1. Cloner le dépôt

```bash
git clone https://github.com/<votre-user>/zabbix-proxy-updater.git
cd zabbix-proxy-updater
```

### 2. Copier le script

```bash
sudo cp update-zabbix-proxy.sh /usr/local/sbin/
sudo chmod 750 /usr/local/sbin/update-zabbix-proxy.sh
sudo chown root:root /usr/local/sbin/update-zabbix-proxy.sh
```

### 3. Adapter la variable `PACKAGE` (si besoin)

Par défaut le script cible `zabbix-proxy-sqlite3`. Si vous utilisez une autre base :

```bash
sudo nano /usr/local/sbin/update-zabbix-proxy.sh
```

```bash
# Ligne à modifier selon votre configuration :
PACKAGE="zabbix-proxy-sqlite3"   # SQLite  (défaut)
PACKAGE="zabbix-proxy-mysql"     # MySQL / MariaDB
PACKAGE="zabbix-proxy-pgsql"     # PostgreSQL
```

---

## ⏰ Automatisation quotidienne

Deux méthodes disponibles. Le **systemd timer** est recommandé.

### Méthode A — Systemd Timer ✅ (recommandé)

**Créer le fichier service :**

```bash
sudo nano /etc/systemd/system/zabbix-proxy-update.service
```

```ini
[Unit]
Description=Mise à jour automatique Zabbix Proxy
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/update-zabbix-proxy.sh
StandardOutput=journal
StandardError=journal
```

**Créer le fichier timer (exécution quotidienne à 3h) :**

```bash
sudo nano /etc/systemd/system/zabbix-proxy-update.timer
```

```ini
[Unit]
Description=Check MAJ Zabbix Proxy quotidiennement

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=10min
Persistent=true

[Install]
WantedBy=timers.target
```

**Activer le timer :**

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now zabbix-proxy-update.timer
```

**Vérifier que le timer est actif :**

```bash
systemctl list-timers | grep zabbix
```

> `Persistent=true` garantit l'exécution au prochain démarrage si la machine était éteinte à l'heure prévue.  
> `RandomizedDelaySec=10min` évite que tous les proxies tapent les dépôts exactement en même temps.

---

### Méthode B — Cron

```bash
sudo crontab -e
```

```
0 3 * * * /usr/local/sbin/update-zabbix-proxy.sh >> /var/log/zabbix-proxy-update.log 2>&1
```

---

## 🖥️ Déploiement multi-proxies

Pour pousser le script et la configuration sur l'ensemble de vos proxies en une seule commande :

```bash
for proxy in proxy-X1 proxy-x2; do
  echo "=== Déploiement sur $proxy ==="
  scp /usr/local/sbin/update-zabbix-proxy.sh root@${proxy}:/usr/local/sbin/
  ssh root@${proxy} "
    chmod 750 /usr/local/sbin/update-zabbix-proxy.sh &&
    chown root:root /usr/local/sbin/update-zabbix-proxy.sh &&
    systemctl enable --now zabbix-proxy-update.timer &&
    systemctl list-timers | grep zabbix
  "
done
```

---

## 🧪 Utilisation manuelle

**Lancement standard :**
```bash
sudo /usr/local/sbin/update-zabbix-proxy.sh
```

**Mode simulation (aucune modification appliquée) :**
```bash
sudo /usr/local/sbin/update-zabbix-proxy.sh --dry-run
```

**Cibler un paquet spécifique à la volée :**
```bash
sudo /usr/local/sbin/update-zabbix-proxy.sh --package=zabbix-proxy-mysql
```

**Déclencher manuellement via systemd :**
```bash
sudo systemctl start zabbix-proxy-update.service
```

---

## 📊 Logs & supervision

**Voir les logs en temps réel :**
```bash
journalctl -u zabbix-proxy-update.service -f
```

**Consulter le fichier de log :**
```bash
tail -f /var/log/zabbix-proxy-update.log
```

**Vérifier le statut du service Zabbix Proxy :**
```bash
systemctl status zabbix-proxy
```

**Retrouver les backups de configuration :**
```bash
ls -lh /etc/zabbix/zabbix_proxy.conf.bak_*
```

---

## 🔒 Pourquoi les configs custom sont-elles préservées ?

Lors d'une mise à jour apt classique, dpkg peut proposer d'écraser vos fichiers de configuration modifiés avec la version du nouveau paquet. Sans réponse automatique, il affiche un prompt interactif.

Ce script passe les options suivantes à dpkg pour supprimer toute interaction :

```bash
-o Dpkg::Options::="--force-confold"   # Conserve TOUJOURS la version locale existante
-o Dpkg::Options::="--force-confdef"   # Utilise la valeur par défaut si le fichier n'a pas été modifié
```

C'est l'équivalent automatisé de répondre **N** à chaque question de dpkg.

De plus, une **sauvegarde horodatée** de `/etc/zabbix/zabbix_proxy.conf` est réalisée avant chaque opération, permettant un rollback immédiat si nécessaire.

---

## 📁 Structure du dépôt

```
zabbix-proxy-updater/
├── update-zabbix-proxy.sh          # Script principal
├── systemd/
│   ├── zabbix-proxy-update.service # Unit systemd
│   └── zabbix-proxy-update.timer   # Timer systemd
└── README.md                       # Cette documentation
```

---

## 📄 Licence

GPL v3

Attention, le script peut affichier une erreur en fin selon la langue de l'OS.
