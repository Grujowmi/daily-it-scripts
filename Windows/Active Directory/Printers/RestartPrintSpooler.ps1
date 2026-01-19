# ==========================================================
#  Script Name  : RestartPrintSpooler.ps1
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


$logFile = "C:\Logs\PrintSpoolerRestart.log"

# Creer le dossier de logs s'il n'existe pas
if (!(Test-Path "C:\Logs")) {
    New-Item -ItemType Directory -Path "C:\Logs" | Out-None
}

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File $logFile -Append
    Write-Host $Message
}

Write-Log "=========================================="
Write-Log "DEBUT - Redemarrage du Print Spooler"

# Arret du service
Write-Log "Arret du service Spooler..."
try {
    Stop-Service -Name Spooler -Force -ErrorAction Stop
    Write-Log "Service Spooler arrete avec succes"
} catch {
    Write-Log "ERREUR lors de l'arrêt : $($_.Exception.Message)"
    exit 1
}

# Attente
Write-Log "Attente de 5 secondes..."
Start-Sleep -Seconds 5

# Demarrage du service
Write-Log "Demarrage du service Spooler..."
try {
    Start-Service -Name Spooler -ErrorAction Stop
    Write-Log "Service Spooler demarre avec succes"
} catch {
    Write-Log "ERREUR lors du demarrage : $($_.Exception.Message)"
    exit 1
}

# Attente que le service soit completement operationnel
Write-Log "Attente de 10 secondes (demarrage complet)..."
Start-Sleep -Seconds 10

# Verification du statut
$spoolerStatus = Get-Service -Name Spooler
if ($spoolerStatus.Status -eq "Running") {
    Write-Log "Verification OK : Service Spooler en cours d'execution"
} else {
    Write-Log "ALERTE : Service Spooler statut = $($spoolerStatus.Status)"
}

# Warmup des imprimantes
Write-Log "Debut du warmup des imprimantes..."
$printerCount = 0
$errorCount = 0

Get-Printer | ForEach-Object {
    try {
        $printer = Get-Printer -Name $_.Name -ErrorAction Stop
        Write-Log "  Warmup OK : $($printer.Name)"
        $printerCount++
    } catch {
        Write-Log "  Warmup ERREUR : $($_.Name) - $($_.Exception.Message)"
        $errorCount++
    }
}

Write-Log "Warmup termine : $printerCount imprimantes OK, $errorCount erreurs"
Write-Log "FIN - Redemarrage du Print Spooler"
Write-Log "=========================================="