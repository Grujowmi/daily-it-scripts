# 🖨️ Print Spooler – Restart & Warmup

Script PowerShell de **maintenance préventive du service d’impression Windows**.  
Il redémarre proprement le **Print Spooler**, vérifie son bon fonctionnement et effectue un **warmup des imprimantes** afin d’éviter les blocages et lenteurs d’impression.

---

## 🎯 Objectif

- Prévenir les bugs récurrents du Print Spooler
- Éviter les impressions bloquées ou très lentes
- S’assurer que toutes les imprimantes sont accessibles
- Améliorer l’expérience utilisateur, notamment en environnement multi-utilisateurs

---

## ⚙️ Fonctionnement

Le script effectue les actions suivantes :

1. Création d’un fichier de logs horodaté
2. Arrêt forcé du service **Spooler**
3. Attente contrôlée
4. Redémarrage du service
5. Vérification du statut du service
6. Warmup des imprimantes via `Get-Printer`
7. Génération d’un résumé dans les logs

Aucune impression n’est envoyée : le warmup est **non intrusif**.

---

## 📂 Logs

Les actions sont journalisées dans :

```text
C:\Logs\PrintSpoolerRestart.log
