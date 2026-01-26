# 🛡️ Zabbix Agent 2 - Deployment & Update Tool

Script PowerShell de pilotage centralisé pour le déploiement et la mise à jour de Zabbix Agent 2 sur un parc Windows via Active Directory.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)
![Windows](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![Zabbix](https://img.shields.io/badge/Zabbix-7.0.6-red.svg)
![License](https://img.shields.io/badge/License-GPLv3-green.svg)

---

## 📋 Table des matières

- [Présentation](#-présentation)
- [Fonctionnalités](#-fonctionnalités)
- [Prérequis](#-prérequis)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [Utilisation](#-utilisation)
- [Structure des fichiers](#-structure-des-fichiers)
- [Dépannage](#-dépannage)
- [FAQ](#-faq)
- [Changelog](#-changelog)
- [Licence](#-licence)

---

## 🎯 Présentation

Ce script permet de gérer le déploiement de Zabbix Agent 2 sur l'ensemble de votre parc informatique Windows directement depuis un contrôleur de domaine ou une station d'administration.

**Cas d'usage :**

- Déploiement initial de Zabbix Agent 2
- Mise à jour vers une nouvelle version
- Audit des versions installées sur le parc
- Vérification de l'état d'une machine spécifique

---

## ✨ Fonctionnalités

| Fonctionnalité | Description |
|----------------|-------------|
| **Patch PC unique** | Cibler une machine spécifique par son nom |
| **Patch par OU** | Sélectionner une Unité Organisationnelle avec affichage arborescent |
| **Patch global** | Déployer sur tout le parc avec double confirmation |
| **Vérification machine** | Contrôler l'état et la version d'une machine |
| **Inventaire complet** | Scanner le parc et exporter en CSV |
| **Rapports HTML** | Génération automatique de rapports visuels |
| **Logs détaillés** | Traçabilité complète des opérations |
| **Exclusions** | Liste de machines à ignorer (DC, serveurs critiques) |

---

## 📌 Prérequis

### Système

| Composant | Version minimale |
|-----------|------------------|
| PowerShell | 5.1 ou supérieur |
| Windows | Server 2016+ / Windows 10+ |
| .NET Framework | 4.5.2 ou supérieur |

### Modules PowerShell

```powershell
# Le module ActiveDirectory est requis
Get-Module -ListAvailable -Name ActiveDirectory

# Si non installé (sur Windows Server)
Install-WindowsFeature RSAT-AD-PowerShell

# Si non installé (sur Windows 10/11)
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

### Réseau

- **WinRM activé** sur les machines cibles
- **Ports ouverts** : 5985 (HTTP) ou 5986 (HTTPS)
- **Accès au partage NETLOGON** depuis les machines cibles

### Permissions

| Niveau | Permissions requises |
|--------|---------------------|
| Active Directory | Lecture des objets Computer et OU |
| Machines cibles | Administrateur local (pour l'installation MSI) |
| Partage réseau | Lecture sur le dossier des packages |

---

## 📥 Installation

### 1. Créer la structure de dossiers

```powershell
# Sur le contrôleur de domaine ou serveur de fichiers
$basePath = "\\$env:USERDNSDOMAIN\NETLOGON\ZabbixUpdate"

New-Item -ItemType Directory -Path "$basePath" -Force
New-Item -ItemType Directory -Path "$basePath\Packages" -Force
New-Item -ItemType Directory -Path "$basePath\Logs" -Force
New-Item -ItemType Directory -Path "$basePath\Reports" -Force
```

### 2. Copier les fichiers

```
\\DOMAIN\NETLOGON\ZabbixUpdate\
│
├── Update_Zabbix.ps1              # Script principal
│
├── Packages\
│   ├── zabbix_agent2-7.0.6-windows-amd64.msi
│   └── zabbix_agent2_config.mst        # Optionnel : Transform MSI
│
├── Logs\                               # Créé automatiquement
│
└── Reports\                            # Créé automatiquement
```

### 3. Télécharger le package Zabbix

```powershell
# Télécharger depuis le site officiel
$url = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/7.0.6/zabbix_agent2-7.0.6-windows-amd64-openssl.msi"
$output = "\\$env:USERDNSDOMAIN\NETLOGON\ZabbixUpdate\Packages\zabbix_agent2-7.0.6-windows-amd64.msi"

Invoke-WebRequest -Uri $url -OutFile $output
```

---

## ⚙️ Configuration

### Paramètres principaux

Ouvrez le script `Update_Zabbix.ps1` et modifiez la section `$Script:Config` :

```powershell
$Script:Config = @{
    # === CHEMINS ===
    PackageShare        = "\\$env:USERDNSDOMAIN\NETLOGON\ZabbixUpdate\Packages"
    MsiFileName         = "zabbix_agent2-7.0.6-windows-amd64.msi"
    MstFileName         = "zabbix_agent2_config.mst"  # Laisser vide "" si pas de MST
    LogPath             = "\\$env:USERDNSDOMAIN\NETLOGON\ZabbixUpdate\Logs"
    ReportPath          = "\\$env:USERDNSDOMAIN\NETLOGON\ZabbixUpdate\Reports"
    
    # === VERSION ===
    TargetVersion       = "7.0.6"
    
    # === EXECUTION ===
    MaxParallelJobs     = 10          # Nombre max de déploiements simultanés
    TimeoutSeconds      = 300         # Timeout par machine (5 min)
    RetryCount          = 2           # Nombre de tentatives en cas d'échec
    
    # === FILTRES ===
    ExcludedComputers   = @("DC01", "DC02", "SQL-PROD", "DVDCAPP01")
    OnlyWindows         = $true       # Ignorer les objets non-Windows
}
```

### Configuration du fichier MST (Transform)

Si vous utilisez un fichier MST pour personnaliser l'installation :

1. Créez votre MST avec Orca ou un outil similaire
2. Configurez les paramètres Zabbix (Server, Hostname, PSK, etc.)
3. Placez le fichier dans le dossier `Packages\`
4. Renseignez le nom dans `MstFileName`

**Exemple de paramètres MST courants :**

| Propriété | Description | Exemple |
|-----------|-------------|---------|
| SERVER | Adresse du serveur Zabbix | `zabbix.domain.local` |
| SERVERACTIVE | Adresse pour les checks actifs | `zabbix.domain.local` |
| HOSTNAME | Hostname de l'agent | `[HOSTNAME]` |
| TLSCONNECT | Type de connexion | `psk` |
| TLSPSKIDENTITY | Identité PSK | `PSK_ID_001` |
| TLSPSKFILE | Chemin du fichier PSK | `C:\Program Files\Zabbix Agent 2\zabbix_agent2.psk` |

---

## 🚀 Utilisation

### Lancement du script

```powershell
# Depuis le DC ou une station d'administration (en tant qu'administrateur)
\\DOMAIN\NETLOGON\ZabbixUpdate\Update_Zabbix.ps1

# Ou en local si copié
.\Update_Zabbix.ps1
```

### Menu principal

```
+==============================================================================+
|     ZABBIX UP - DEPLOYMENT & UPDATE TOOL v1.0                                |
|     Target Version: 7.0.6                                                    |
+==============================================================================+

+========================================+
|           MENU PRINCIPAL               |
+========================================+
|  [1] Patcher un PC specifique          |
|  [2] Patcher une OU                    |
|  [3] Patcher tout le parc              |
|  [4] Verifier une machine              |
|  [5] Inventaire des versions           |
|  [6] Configuration                     |
|  [Q] Quitter                           |
+========================================+

Votre choix:
```

### Option 1 : Patcher un PC spécifique

```
=======================================
  PATCH D'UN PC SPECIFIQUE
=======================================

Nom de l'ordinateur (ou 'retour' pour annuler): PC-USER01

Machine trouvee: PC-USER01
OS: Windows 11 Enterprise

Lancer le patch? (O/N): O

[2025-01-15 10:30:45] [INFO] [PC-USER01] Test de connectivite...
[2025-01-15 10:30:46] [INFO] [PC-USER01] Verification de la version actuelle...
[2025-01-15 10:30:48] [INFO] [PC-USER01] Lancement de l'installation...
[2025-01-15 10:31:15] [SUCCESS] [PC-USER01] Mise a jour reussie: 6.4.0 -> 7.0.6

=======================================
  RESULTAT
=======================================

Statut: Success
Message: Mise a jour reussie: 6.4.0 -> 7.0.6
Version: 6.4.0 -> 7.0.6
```

### Option 2 : Patcher une OU

```
=======================================
  PATCH D'UNE UNITE ORGANISATIONNELLE
=======================================

Chargement des OUs...

+-------+--------------------------------------------------+----------------+
| #     | Unite Organisationnelle                          | PCs (recursif) |
+-------+--------------------------------------------------+----------------+
| 1     | +-- Computers                                    |    45          |
| 2     |   +-- Workstations                               |    32          |
| 3     |     +-- Paris                                    |    15          |
| 4     |     +-- Lyon                                     |    17          |
| 5     |   +-- Laptops                                    |    13          |
| 6     | +-- Servers                                      |    12          |
+-------+--------------------------------------------------+----------------+

Numero de l'OU (ou 'retour'): 3

OU selectionnee: Paris
DN: OU=Paris,OU=Workstations,OU=Computers,DC=domain,DC=local

Inclure les sous-OUs? (O/N): N

15 ordinateur(s) trouve(s):
  - PC-PAR-001
  - PC-PAR-002
  - PC-PAR-003
  ...

Lancer le deploiement? (O/N): O
```

### Option 3 : Patcher tout le parc

```
=======================================
  PATCH DE TOUT LE PARC
=======================================

Analyse du parc...

[!] ATTENTION [!]
Vous etes sur le point de deployer sur 127 machines.

Machines exclues: DC01, DC02, SQL-PROD

Recapitulatif par OS:
  89 x Windows 11 Enterprise
  25 x Windows 10 Enterprise
  8 x Windows Server 2022 Standard
  5 x Windows Server 2019 Standard

Etes-vous sur? Tapez 'CONFIRMER' pour continuer: CONFIRMER
```

### Option 5 : Inventaire des versions

```
=======================================
  INVENTAIRE DES VERSIONS
=======================================

Selectionnez le scope:
  [1] Une OU specifique
  [2] Tout le parc
Choix: 2

Analyse de 127 machines...

[STATS] RESUME DE L'INVENTAIRE
==========================================================
  Total machines:        127
  En ligne:              118
  Hors ligne:            9
  A jour (7.0.6):        45
  Mise a jour requise:   68
  Non installe:          5

[DETAIL] PAR VERSION
  [OK] 7.0.6: 45 machine(s)
  [!] 6.4.0: 42 machine(s)
  [!] 6.2.0: 18 machine(s)
  [!] 6.0.0: 8 machine(s)
  [!] N/A: 5 machine(s)

Exporter en CSV? (O/N): O
Exporte vers: \\DOMAIN\NETLOGON\ZabbixUpdate\Reports\Inventory_20250115_103500.csv
```

---

## 📁 Structure des fichiers

```
\\DOMAIN\NETLOGON\ZabbixUpdate\
│
├── Update_Zabbix.ps1           # Script principal
├── README.md                        # Cette documentation
│
├── Packages\
│   ├── zabbix_agent2-7.0.6-windows-amd64.msi    # Package MSI
│   └── zabbix_agent2_config.mst                  # Transform (optionnel)
│
├── Logs\
│   ├── ZabbixUpdate_20250115.log    # Log du jour
│   ├── ZabbixUpdate_20250114.log
│   └── ...
│
└── Reports\
    ├── ZabbixDeployment_20250115_103045.html    # Rapport HTML
    ├── Inventory_20250115_103500.csv            # Export inventaire
    └── ...
```

---

## 📸 Rapport HTML généré

Le script génère automatiquement un rapport HTML après chaque déploiement :

```
+------------------------------------------------------------------+
|  Rapport de Deploiement - Zabbix Agent 2                         |
|  Version cible: 7.0.6 | Genere le: 15/01/2025 10:30:45           |
+------------------------------------------------------------------+

  +-------------+  +-------------+  +-------------+  +-------------+
  |     12      |  |      8      |  |      2      |  |      3      |
  |   Succes    |  | Deja a jour |  |   Echecs    |  | Hors ligne  |
  +-------------+  +-------------+  +-------------+  +-------------+

  +------------+----------------+----------+----------+--------+
  | Ordinateur | Statut         | Ancienne | Nouvelle | Duree  |
  +------------+----------------+----------+----------+--------+
  | PC-001     | Success        | 6.4.0    | 7.0.6    | 25.3s  |
  | PC-002     | Success        | 6.2.0    | 7.0.6    | 28.1s  |
  | PC-003     | AlreadyUpToDate| 7.0.6    | 7.0.6    | 2.1s   |
  | PC-004     | Offline        | N/A      | N/A      | 5.0s   |
  +------------+----------------+----------+----------+--------+
```

---

## 🔧 Dépannage

### Erreurs courantes

#### 1. Module ActiveDirectory non trouvé

```
Erreur: Module ActiveDirectory non disponible
```

**Solution :**

```powershell
# Windows Server
Install-WindowsFeature RSAT-AD-PowerShell

# Windows 10/11
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

#### 2. Machine inaccessible (WinRM)

```
[WARNING] [PC-001] Machine inaccessible (ping ou WinRM)
```

**Solutions :**

```powershell
# Sur la machine cible, activer WinRM
Enable-PSRemoting -Force

# Vérifier le service
Get-Service WinRM

# Tester la connexion
Test-WSMan -ComputerName PC-001
```

#### 3. Accès refusé

```
[ERROR] [PC-001] Exception: Access is denied
```

**Solutions :**

- Vérifier que vous exécutez le script en tant qu'administrateur
- Vérifier que votre compte a les droits admin local sur la cible
- Vérifier les GPO de restriction PowerShell Remoting

#### 4. Package MSI introuvable

```
Erreur: Package MSI introuvable: \\DOMAIN\NETLOGON\...
```

**Solutions :**

- Vérifier le chemin dans `$Script:Config.PackageShare`
- Vérifier le nom du fichier MSI
- Vérifier les permissions d'accès au partage

### Logs de débogage

Les logs détaillés sont disponibles dans :

```
\\DOMAIN\NETLOGON\ZabbixUpdate\Logs\ZabbixUpdate_YYYYMMDD.log
```

Format des logs :

```
[2025-01-15 10:30:45] [INFO] [PC-001] Test de connectivite...
[2025-01-15 10:30:46] [SUCCESS] [PC-001] Mise a jour reussie
[2025-01-15 10:30:47] [ERROR] [PC-002] Exception: Access denied
[2025-01-15 10:30:48] [WARNING] [PC-003] Machine inaccessible
```

### Log d'installation MSI

Sur chaque machine cible, un log MSI est créé :

```
C:\Windows\Temp\ZabbixAgent_Install.log
```

---

## ❓ FAQ

### Q: Puis-je utiliser le script sans fichier MST ?

**R:** Oui, laissez simplement le paramètre `MstFileName` vide :

```powershell
MstFileName = ""
```

### Q: Comment ajouter des machines à exclure ?

**R:** Modifiez le tableau `ExcludedComputers` :

```powershell
ExcludedComputers = @("DC01", "DC02", "SQL-PROD", "MA-MACHINE")
```

### Q: Le script fonctionne-t-il avec Zabbix Agent (v1) ?

**R:** Le script est conçu pour Zabbix Agent 2 mais détecte également l'Agent v1. Vous pouvez adapter les chemins dans la fonction `Get-ZabbixAgentVersion`.

### Q: Puis-je planifier le script en tâche planifiée ?

**R:** Oui, mais le script est interactif par défaut. Pour une utilisation automatisée, vous devriez créer une version non-interactive avec des paramètres en ligne de commande.

### Q: Comment gérer les PSK ?

**R:** Les PSK peuvent être gérés via :

1. Le fichier MST (recommandé)
2. Un script séparé de déploiement des PSK
3. Les paramètres MSI en ligne de commande

### Q: Le script supporte-t-il les machines hors domaine ?

**R:** Non, le script utilise Active Directory pour la découverte. Pour les machines hors domaine, vous devrez utiliser une autre méthode (liste manuelle, etc.).

---

## 📝 Changelog

### Version 1.0.0 (2025-01-15)

**Fonctionnalités initiales :**

- [x] Menu interactif complet
- [x] Patch PC unique
- [x] Patch par OU avec arborescence
- [x] Patch global avec double confirmation
- [x] Vérification de machine
- [x] Inventaire des versions avec export CSV
- [x] Rapports HTML automatiques
- [x] Logs détaillés
- [x] Gestion des exclusions
- [x] Support MSI + MST

### Roadmap

- [ ] Mode parallèle optimisé (RunspacePool)
- [ ] Support des paramètres en ligne de commande
- [ ] Envoi de rapport par email
- [ ] Interface graphique (WPF/WinForms)
- [ ] Support multi-version (upgrade path)

---

## 📄 Licence

Ce projet est distribué sous licence **GNU General Public License v3.0 (GPLv3)**.

```
Zabbix Agent 2 - Deployment & Update Tool
Copyright (C) 2025

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
```

### Résumé de la licence GPLv3

| Autorisé | Conditions | Interdit |
|----------|------------|----------|
| ✅ Usage commercial | 📋 Divulguer le source | ❌ Responsabilité |
| ✅ Modification | 📋 Licence identique | ❌ Garantie |
| ✅ Distribution | 📋 Conserver copyright | |
| ✅ Usage privé | 📋 Documenter les changements | |

---

## 🤝 Support

Pour toute question ou amélioration :

- Ouvrir une issue sur le dépôt Git
- Contacter l'équipe IT interne
- Consulter la documentation Zabbix officielle : [https://www.zabbix.com/documentation](https://www.zabbix.com/documentation)

---