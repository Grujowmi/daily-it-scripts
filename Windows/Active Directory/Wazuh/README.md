# Gestion du service Wazuh dans un domaine Active Directory

## 📌 Description
Ce script PowerShell permet de **gérer (arrêter et vérifier)** le service **Wazuh** sur des machines Windows membres d’un domaine Active Directory.

Il est conçu pour être utilisé en cas de problème de déploiement ou de maintenance du service Wazuh.

---

## 🚀 Fonctionnalités
- Arrêt du service Wazuh sur :
  - Une machine spécifique
  - Plusieurs machines (liste)
  - Une Unité d’Organisation (OU)
  - Toutes les machines Windows du domaine
- Vérification de l’état du service Wazuh
- Menu interactif
- Gestion des erreurs et confirmations de sécurité

---

## 🛠️ Pré-requis

- **Windows PowerShell 5.1**
- Module **ActiveDirectory** (RSAT)
- Droits administrateur sur les machines cibles
- **WinRM activé** sur les postes
- Résolution DNS fonctionnelle
- Service Wazuh nommé : `WazuhSvc`

---

## ⚙️ Installation

1. Copier le script sur un contrôleur de domaine ou une machine d’administration
2. Ouvrir une console PowerShell **en tant qu’administrateur**
3. Vérifier l’exécution des scripts :
   ```powershell
   Set-ExecutionPolicy RemoteSigned
