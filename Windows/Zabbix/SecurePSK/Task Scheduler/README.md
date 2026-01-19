Secure-ZabbixPSK.ps1
📌 Description

Secure-ZabbixPSK.ps1 est un script PowerShell conçu pour sécuriser automatiquement la clé PSK de Zabbix Agent 2 sous Windows.
Il est prévu pour être exécuté au démarrage du système, avec un impact performance nul une fois la sécurisation effectuée.

Le script empêche les utilisateurs standards d’accéder au fichier PSK en modifiant ses permissions NTFS.

🎯 Objectifs

Protéger la clé PSK utilisée par Zabbix Agent 2

Supprimer les droits de lecture des utilisateurs standards

Garantir une exécution idempotente (une seule fois)

Être compatible avec une installation différée de Zabbix

⚙️ Fonctionnement

Vérifie si la sécurisation a déjà été appliquée (fichier flag)

Vérifie si Zabbix Agent 2 est installé (présence du fichier PSK)

Désactive l’héritage NTFS du fichier PSK

Supprime les droits du groupe BUILTIN\Utilisateurs

Crée un fichier de confirmation pour éviter toute réexécution

En cas d’erreur, le script échoue silencieusement et réessaiera au prochain démarrage

📂 Chemins utilisés
Élément	Chemin
Clé PSK Zabbix	C:\Program Files\Zabbix Agent 2\psk.key
Fichier flag	C:\Windows\Temp\.zabbix-psk-secured
🔐 Sécurité

Le script utilise icacls pour modifier les ACL NTFS

Les droits utilisateurs standards sont supprimés

Aucun log sensible n’est généré

Les erreurs sont volontairement silencieuses (contexte startup)

🚀 Déploiement recommandé

GPO (Startup Script)

Tâche planifiée au démarrage (SYSTEM)

Image de master / golden image

Outil de déploiement (SCCM, Intune, etc.)

⚠️ Le script doit être exécuté avec des droits administrateur.

📄 Exemple de code
$pskPath = "C:\Program Files\Zabbix Agent 2\psk.key"
$flagFile = "C:\Windows\Temp\.zabbix-psk-secured"

🧪 Comportement attendu
Situation	Résultat
Zabbix non installé	Le script quitte sans action
PSK déjà sécurisé	Le script quitte immédiatement
Erreur ACL	Nouvelle tentative au prochain démarrage
📝 Notes

Le script n’altère pas les droits SYSTEM ou Administrateurs

Compatible Windows Server et Windows Client

Aucun impact sur le fonctionnement de Zabbix Agent 2

📜 Licence

GPLv3