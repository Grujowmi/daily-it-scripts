# 🛠️ Daily IT Scripts

![GitHub repo size](https://img.shields.io/github/repo-size/Grujowmi/daily-it-scripts)
![GitHub last commit](https://img.shields.io/github/last-commit/Grujowmi/daily-it-scripts)
![GitHub license](https://img.shields.io/github/license/Grujowmi/daily-it-scripts)

Bienvenue sur **Daily IT Scripts** ! 🚀
Ce dépôt regroupe une collection de scripts pratiques et réutilisables, conçus pour automatiser, simplifier et accélérer les tâches informatiques quotidiennes (Administration Système, Réseau, Cloud, etc.).

## 🎯 Objectif

L'objectif de ce projet est de centraliser des outils en ligne de commande (Bash, PowerShell, Python, etc.) afin de :
- Gagner du temps sur les tâches répétitives.
- Standardiser les procédures de maintenance et de déploiement.
- Partager des solutions techniques utiles à la communauté IT.

## 📂 Structure du dépôt

*(Note: N'hésite pas à modifier cette section en fonction de l'arborescence réelle de ton projet)*

* 📁 **`Linux/`** : Scripts Bash pour l'administration de serveurs Linux (gestion des logs, backups, surveillance système).
* 📁 **`Windows/`** : Scripts PowerShell/Batch pour l'environnement Windows (Active Directory, gestion des postes clients, nettoyage).
* 📁 **`Network/`** : Outils de diagnostic réseau et de monitoring.
* 📁 **`Python/`** : Scripts d'automatisation divers (requêtes API, parsing de données).

## 🚀 Installation & Utilisation

### 1. Cloner le dépôt
Pour récupérer l'ensemble des scripts sur votre machine locale :

```bash
git clone https://github.com/Grujowmi/daily-it-scripts.git
cd daily-it-scripts
```
### 1. Exécution
**Pour les scripts Linux (Bash) :**
N'oubliez pas de rendre le script exécutable avant de le lancer.

```bash
chmod +x chemin/vers/le/script.sh
./chemin/vers/le/script.sh
```
**Pour les scripts Windows (PowerShell) :**
Il se peut que vous deviez autoriser l'exécution des scripts sur votre machine :
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
.\chemin\vers\le\script.ps1
```
## ⚠️ Avertissement de sécurité

> [!WARNING]
> Ne lancez jamais un script en production sans l’avoir **lu**, **compris** et **testé** dans un environnement de développement au préalable.
>
> L’auteur de ce dépôt ne saurait être tenu responsable des dommages causés par une mauvaise utilisation de ces scripts.

## 🚀 Contribution

Les contributions sont les bienvenues ! Si vous avez un script utile que vous souhaitez partager :

Forkez le projet.
Créez une branche pour votre fonctionnalité (git checkout -b ajout-script-backup).
Commitez vos changements (git commit -m 'Ajout d'un script de backup automatisé').
Pushez vers la branche (git push origin ajout-script-backup).
Ouvrez une Pull Request.
Merci de vous assurer que vos scripts sont commentés et documentés un minimum en en-tête.

## 📜 Licence

Ce projet est sous licence GPL v3
Créé et maintenu par Grujowmi.

