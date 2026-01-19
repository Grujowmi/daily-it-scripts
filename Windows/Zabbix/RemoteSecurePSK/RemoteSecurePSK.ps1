# ==========================================================
#  Script Name  : RemoteSecurePSK.ps1
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
#Requires -Modules ActiveDirectory

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Securisation PSK Zabbix - Deploiement distant" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Etape 1 : Recupe�ration de toutes les machines depuis Active Directory
Write-Host "[1/5] Recuperation des machines depuis Active Directory..." -ForegroundColor Yellow

try {
    $allComputers = Get-ADComputer -Filter * -Properties OperatingSystem | 
                    Select-Object Name, OperatingSystem | 
                    Sort-Object Name
    
    Write-Host "      Trouve : $($allComputers.Count) machines`n" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Impossible de recuperer les machines depuis AD" -ForegroundColor Red
    Write-Host "Erreur : $_" -ForegroundColor Red
    Read-Host "Appuyez sur Entree pour quitter"
    exit 1
}

# Etape 2 : Affichage et selection
Write-Host "[2/5] Selection des machines a traiter`n" -ForegroundColor Yellow

# Affichage de la liste avec numeros
$computerList = @()
$index = 1
foreach ($computer in $allComputers) {
    $os = if ($computer.OperatingSystem) { $computer.OperatingSystem } else { "Inconnu" }
    Write-Host "  [$index] $($computer.Name) - $os" -ForegroundColor Gray
    $computerList += [PSCustomObject]@{
        Index = $index
        Name = $computer.Name
        OS = $os
    }
    $index++
}

Write-Host "`nOptions de selection :" -ForegroundColor Cyan
Write-Host "  - Tapez 'ALL' pour toutes les machines" -ForegroundColor White
Write-Host "  - Tapez 'SERVER' pour tous les serveurs uniquement" -ForegroundColor White
Write-Host "  - Tapez 'WORKSTATION' pour tous les postes de travail uniquement" -ForegroundColor White
Write-Host "  - Tapez les numeros separes par des virgules (ex: 1,3,5-10,15)" -ForegroundColor White
Write-Host "  - Tapez des noms separes par des virgules (ex: PC-001,SRV-002)" -ForegroundColor White

$selection = Read-Host "`nVotre choix"

# Traitement de la selection
$selectedComputers = @()

switch -Regex ($selection.ToUpper()) {
    '^ALL$' {
        $selectedComputers = $allComputers.Name
        Write-Host "`n  Selection : TOUTES les machines ($($selectedComputers.Count))" -ForegroundColor Green
    }
    '^SERVER$' {
        $selectedComputers = $allComputers | Where-Object {$_.OperatingSystem -like "*Server*"} | Select-Object -ExpandProperty Name
        Write-Host "`n  Selection : Serveurs uniquement ($($selectedComputers.Count))" -ForegroundColor Green
    }
    '^WORKSTATION$' {
        $selectedComputers = $allComputers | Where-Object {$_.OperatingSystem -notlike "*Server*"} | Select-Object -ExpandProperty Name
        Write-Host "`n  Selection : Postes de travail uniquement ($($selectedComputers.Count))" -ForegroundColor Green
    }
    '^\d' {
        # Selection par numeros ou plages
        $numbers = $selection -split ',' | ForEach-Object {
            $_.Trim()
            if ($_ -match '(\d+)-(\d+)') {
                # Plage de numeros
                $start = [int]$Matches[1]
                $end = [int]$Matches[2]
                $start..$end
            } else {
                # Numero simple
                [int]$_
            }
        }
        
        $selectedComputers = $computerList | Where-Object {$numbers -contains $_.Index} | Select-Object -ExpandProperty Name
        Write-Host "`n  Selection : $($selectedComputers.Count) machines" -ForegroundColor Green
    }
    default {
        # Selection par noms
        $names = $selection -split ',' | ForEach-Object {$_.Trim()}
        $selectedComputers = $allComputers | Where-Object {$names -contains $_.Name} | Select-Object -ExpandProperty Name
        Write-Host "`n  Selection : $($selectedComputers.Count) machines" -ForegroundColor Green
    }
}

if ($selectedComputers.Count -eq 0) {
    Write-Host "[ERREUR] Aucune machine selectionnee" -ForegroundColor Red
    Read-Host "Appuyez sur Entree pour quitter"
    exit 1
}

# Confirmation
Write-Host "`nMachines selectionnees :" -ForegroundColor Cyan
$selectedComputers | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }

$confirm = Read-Host "`nConfirmez-vous le deploiement sur ces machines ? (O/N)"
if ($confirm -notmatch '^[oO]$') {
    Write-Host "Deploiement annule." -ForegroundColor Yellow
    Read-Host "Appuyez sur Entree pour quitter"
    exit 0
}

# Etape 3 : Preparation du script a executer a distance
Write-Host "`n[3/5] Preparation du script de securisation..." -ForegroundColor Yellow

$pskPath = "C:\Program Files\Zabbix Agent 2\psk.key"

$scriptBlock = {
    param($pskPath)
    
    $result = @{
        ComputerName = $env:COMPUTERNAME
        Success = $false
        Message = ""
        HasZabbix = $false
    }
    
    # Verification existence du fichier
    if (-not (Test-Path $pskPath)) {
        $result.Message = "Zabbix Agent 2 non installe ou PSK absent"
        return $result
    }
    
    $result.HasZabbix = $true
    
    try {
        # Desactivation heritage
        $output1 = icacls $pskPath /inheritance:d 2>&1
        
        if ($output1 -match "Accès refusé" -or $output1 -match "Access is denied") {
            $result.Message = "Acces refuse - Permissions insuffisantes"
            return $result
        }
        
        # Retrait droits utilisateurs
        $output2 = icacls $pskPath /remove "BUILTIN\Utilisateurs" 2>&1
        
        # Verification finale
        $finalPerms = icacls $pskPath 2>&1 | Out-String
        
        if ($finalPerms -notmatch "BUILTIN\\Utilisateurs" -and $finalPerms -notmatch "\\Users:") {
            $result.Success = $true
            $result.Message = "PSK securise - Utilisateurs n'ont plus acces"
        } else {
            $result.Message = "Echec - Utilisateurs ont toujours acces au fichier"
        }
        
    } catch {
        $result.Message = "Erreur d'execution : $_"
    }
    
    return $result
}

Write-Host "      Script pret`n" -ForegroundColor Green

# Etape 4 : Deploiement sur les machines selectionnees
Write-Host "[4/5] Deploiement en cours...`n" -ForegroundColor Yellow

$totalComputers = $selectedComputers.Count
$currentComputer = 0
$successCount = 0
$failCount = 0
$noZabbixCount = 0
$unreachableCount = 0
$results = @()

foreach ($computer in $selectedComputers) {
    $currentComputer++
    $percentComplete = [math]::Round(($currentComputer / $totalComputers) * 100)
    
    Write-Progress -Activity "Deploiement securisation PSK" -Status "Machine: $computer" -PercentComplete $percentComplete
    Write-Host "  [$currentComputer/$totalComputers] $computer..." -NoNewline
    
    # Test de connectivite rapide
    if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        Write-Host " [INACCESSIBLE]" -ForegroundColor Red
        $unreachableCount++
        $results += [PSCustomObject]@{
            Machine = $computer
            Statut = "Inaccessible"
            Message = "Machine hors ligne ou inaccessible"
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        continue
    }
    
    try {
        # Execution du script a distance
        $result = Invoke-Command -ComputerName $computer -ScriptBlock $scriptBlock -ArgumentList $pskPath -ErrorAction Stop
        
        if (-not $result.HasZabbix) {
            Write-Host " [PAS DE ZABBIX]" -ForegroundColor Yellow
            $noZabbixCount++
            $results += [PSCustomObject]@{
                Machine = $computer
                Statut = "Zabbix absent"
                Message = $result.Message
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        } elseif ($result.Success) {
            Write-Host " [OK]" -ForegroundColor Green
            $successCount++
            $results += [PSCustomObject]@{
                Machine = $computer
                Statut = "Succes"
                Message = $result.Message
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        } else {
            Write-Host " [ECHEC]" -ForegroundColor Red
            $failCount++
            $results += [PSCustomObject]@{
                Machine = $computer
                Statut = "Echec"
                Message = $result.Message
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
        
    } catch {
        Write-Host " [ERREUR]" -ForegroundColor Red
        $failCount++
        $results += [PSCustomObject]@{
            Machine = $computer
            Statut = "Erreur"
            Message = $_.Exception.Message
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}

Write-Progress -Activity "Deploiement securisation PSK" -Completed

# Etape 5 : Rapport final
Write-Host "`n[5/5] Generation du rapport final`n" -ForegroundColor Yellow

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "           RAPPORT FINAL" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Machines traitees    : $totalComputers" -ForegroundColor White
Write-Host "Succes               : $successCount" -ForegroundColor Green
Write-Host "Zabbix absent        : $noZabbixCount" -ForegroundColor Yellow
Write-Host "Echecs               : $failCount" -ForegroundColor Red
Write-Host "Inaccessibles        : $unreachableCount" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Cyan

# Export du rapport CSV
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportPath = "C:\Temp\Zabbix_PSK_Security_Report_$timestamp.csv"

# Creation du dossier si necessaire
if (-not (Test-Path "C:\Temp")) {
    New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null
}

$results | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
Write-Host "Rapport CSV exporte : $reportPath" -ForegroundColor Cyan

# Affichage detaille des echecs
if ($failCount -gt 0 -or $unreachableCount -gt 0) {
    Write-Host "`n=== DETAILS DES PROBLEMES ===" -ForegroundColor Red
    $results | Where-Object {$_.Statut -in @("Echec", "Erreur", "Inaccessible")} | Format-Table -AutoSize
}

# Resume des succes
if ($successCount -gt 0) {
    Write-Host "`n=== MACHINES SECURISEES ===" -ForegroundColor Green
    $results | Where-Object {$_.Statut -eq "Succes"} | Select-Object Machine | Format-Table -AutoSize
}

Write-Host "`nDeploiement termine !" -ForegroundColor Green
Read-Host "Appuyez sur Entree pour fermer"