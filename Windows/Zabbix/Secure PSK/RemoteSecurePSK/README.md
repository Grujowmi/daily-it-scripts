# 🔐 Sécurisation PSK Zabbix – Déploiement distant Active Directory

Script PowerShell permettant de **sécuriser le fichier PSK de Zabbix Agent 2** sur un ensemble de machines Windows, via **Active Directory** et **PowerShell Remoting**.

L’objectif est d’empêcher les utilisateurs standards d’accéder au fichier de clé PSK utilisé par Zabbix, tout en automatisant le déploiement à grande échelle.

---

## 🧠 Fonctionnalités

- 📡 Récupération automatique de toutes les machines depuis **Active Directory**
- 🖥️ Affichage interactif avec **sélection avancée** :
  - Toutes les machines
  - Serveurs uniquement
  - Postes de travail uniquement
  - Sélection par numéros, plages ou noms
- 🔒 Sécurisation du fichier PSK :
  - Désactivation de l’héritage des permissions
  - Suppression de l’accès au groupe **Utilisateurs**
- 🚀 Exécution **à distance** via PowerShell Remoting
- 📊 Suivi en temps réel avec barre de progression
- 🧾 Génération automatique d’un **rapport CSV détaillé**
- ❌ Gestion des cas d’erreur :
  - Machine inaccessible
  - Zabbix Agent absent
  - Permissions insuffisantes
  - Échecs d’exécution

---

## 📂 Fichier concerné

Le script agit sur le fichier suivant (chemin par défaut) :

```text
C:\Program Files\Zabbix Agent 2\psk.key
