#Requires -Version 5.1
#Requires -Modules ActiveDirectory
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
<#
.SYNOPSIS
    Script pour arreter le service Wazuh sur les machines du domaine
.DESCRIPTION
    Permet d'arreter le service Wazuh sur une ou plusieurs machines du domaine
    en cas de probleme lors du deploiement
#>

# Configuration
$ErrorActionPreference = "Continue"
$ServiceName = "WazuhSvc"  # Nom du service Wazuh

# Fonction pour afficher le menu principal
function Show-Menu {
    Clear-Host
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "   GESTION SERVICE WAZUH - DOMAINE AD" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Arreter Wazuh sur UNE machine specifique"
    Write-Host "2. Arreter Wazuh sur PLUSIEURS machines (liste)"
    Write-Host "3. Arreter Wazuh sur une OU (Unite d'Organisation)"
    Write-Host "4. Arreter Wazuh sur TOUTES les machines du domaine"
    Write-Host "5. Verifier l'etat du service Wazuh"
    Write-Host "Q. Quitter"
    Write-Host ""
}

# Fonction pour arreter le service sur une machine
function Stop-WazuhService {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName
    )
    
    try {
        # Test de connectivite
        if (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet) {
            Write-Host "[INFO] Connexion à $ComputerName..." -ForegroundColor Yellow
            
            # Arret du service
            $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                param($SvcName)
                $service = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
                if ($service) {
                    if ($service.Status -eq "Running") {
                        Stop-Service -Name $SvcName -Force
                        Start-Sleep -Seconds 2
                        return @{
                            Success = $true
                            Status = (Get-Service -Name $SvcName).Status
                            Message = "Service arrete avec succes"
                        }
                    } else {
                        return @{
                            Success = $true
                            Status = $service.Status
                            Message = "Service dejà arrete"
                        }
                    }
                } else {
                    return @{
                        Success = $false
                        Status = "NotFound"
                        Message = "Service Wazuh non trouve"
                    }
                }
            } -ArgumentList $ServiceName -ErrorAction Stop
            
            if ($result.Success) {
                Write-Host "[OK] $ComputerName : $($result.Message) (État: $($result.Status))" -ForegroundColor Green
            } else {
                Write-Host "[ATTENTION] $ComputerName : $($result.Message)" -ForegroundColor Yellow
            }
            
        } else {
            Write-Host "[ERREUR] $ComputerName : Machine inaccessible" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[ERREUR] $ComputerName : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Fonction pour verifier l'etat du service
function Check-WazuhService {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName
    )
    
    try {
        if (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet) {
            $status = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                param($SvcName)
                $service = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
                if ($service) {
                    return $service.Status
                } else {
                    return "NotInstalled"
                }
            } -ArgumentList $ServiceName -ErrorAction Stop
            
            $color = switch ($status) {
                "Running" { "Green" }
                "Stopped" { "Yellow" }
                default { "Red" }
            }
            Write-Host "$ComputerName : $status" -ForegroundColor $color
        } else {
            Write-Host "$ComputerName : Inaccessible" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "$ComputerName : Erreur - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Option 1: Machine unique
function Stop-SingleComputer {
    Write-Host "`nArret du service Wazuh sur une machine specifique" -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    $computer = Read-Host "`nEntrez le nom de la machine"
    
    if ([string]::IsNullOrWhiteSpace($computer)) {
        Write-Host "Nom de machine invalide" -ForegroundColor Red
        return
    }
    
    Write-Host "`nTraitement en cours..." -ForegroundColor Yellow
    Stop-WazuhService -ComputerName $computer
}

# Option 2: Plusieurs machines (liste)
function Stop-MultipleComputers {
    Write-Host "`nArret du service Wazuh sur plusieurs machines" -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "Entrez les noms des machines separes par des virgules"
    Write-Host "Exemple: PC01,PC02,PC03" -ForegroundColor Gray
    
    $computerList = Read-Host "`nListe des machines"
    
    if ([string]::IsNullOrWhiteSpace($computerList)) {
        Write-Host "Liste vide" -ForegroundColor Red
        return
    }
    
    $computers = $computerList -split ',' | ForEach-Object { $_.Trim() }
    
    Write-Host "`nTraitement de $($computers.Count) machine(s)..." -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($computer in $computers) {
        if (![string]::IsNullOrWhiteSpace($computer)) {
            Stop-WazuhService -ComputerName $computer
        }
    }
}

# Option 3: Machines d'une OU
function Stop-OUComputers {
    Write-Host "`nArret du service Wazuh sur une OU" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    catch {
        Write-Host "Module Active Directory non disponible" -ForegroundColor Red
        return
    }
    
    Write-Host "Entrez le DN de l'OU"
    Write-Host "Exemple: OU=Workstations,DC=contoso,DC=com" -ForegroundColor Gray
    $ouDN = Read-Host "`nDN de l'OU"
    
    if ([string]::IsNullOrWhiteSpace($ouDN)) {
        Write-Host "DN invalide" -ForegroundColor Red
        return
    }
    
    try {
        $computers = Get-ADComputer -Filter * -SearchBase $ouDN | Select-Object -ExpandProperty Name
        
        Write-Host "`n$($computers.Count) machine(s) trouvee(s) dans l'OU" -ForegroundColor Yellow
        
        $confirm = Read-Host "Confirmer l'arret du service sur ces machines? (O/N)"
        if ($confirm -ne 'O') {
            Write-Host "Operation annulee" -ForegroundColor Yellow
            return
        }
        
        Write-Host "`nTraitement en cours..." -ForegroundColor Yellow
        Write-Host ""
        
        foreach ($computer in $computers) {
            Stop-WazuhService -ComputerName $computer
        }
    }
    catch {
        Write-Host "Erreur lors de la recuperation des machines: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Option 4: Toutes les machines du domaine
function Stop-AllDomainComputers {
    Write-Host "`nArret du service Wazuh sur TOUTES les machines du domaine" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "ATTENTION: Cette action va affecter TOUTES les machines du domaine!" -ForegroundColor Red
    Write-Host ""
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    catch {
        Write-Host "Module Active Directory non disponible" -ForegroundColor Red
        return
    }
    
    try {
        $computers = Get-ADComputer -Filter {OperatingSystem -like "*Windows*"} | Select-Object -ExpandProperty Name
        
        Write-Host "$($computers.Count) machine(s) Windows trouvee(s) dans le domaine" -ForegroundColor Yellow
        Write-Host ""
        
        $confirm = Read-Host "Êtes-vous ABSOLUMENT SÛR de vouloir continuer? (tapez 'OUI' en majuscules)"
        if ($confirm -ne 'OUI') {
            Write-Host "Operation annulee" -ForegroundColor Yellow
            return
        }
        
        Write-Host "`nTraitement en cours..." -ForegroundColor Yellow
        Write-Host ""
        
        $i = 0
        foreach ($computer in $computers) {
            $i++
            Write-Host "[$i/$($computers.Count)]" -ForegroundColor Cyan -NoNewline
            Write-Host " " -NoNewline
            Stop-WazuhService -ComputerName $computer
        }
    }
    catch {
        Write-Host "Erreur: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Option 5: Verifier l'etat du service
function Check-ServiceStatus {
    Write-Host "`nVerification de l'etat du service Wazuh" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Verifier une machine"
    Write-Host "2. Verifier plusieurs machines"
    Write-Host "3. Verifier une OU"
    Write-Host ""
    
    $choice = Read-Host "Choix"
    
    switch ($choice) {
        "1" {
            $computer = Read-Host "`nNom de la machine"
            if (![string]::IsNullOrWhiteSpace($computer)) {
                Check-WazuhService -ComputerName $computer
            }
        }
        "2" {
            $computerList = Read-Host "`nListe des machines (separees par des virgules)"
            $computers = $computerList -split ',' | ForEach-Object { $_.Trim() }
            Write-Host ""
            foreach ($computer in $computers) {
                if (![string]::IsNullOrWhiteSpace($computer)) {
                    Check-WazuhService -ComputerName $computer
                }
            }
        }
        "3" {
            try {
                Import-Module ActiveDirectory -ErrorAction Stop
                $ouDN = Read-Host "`nDN de l'OU"
                $computers = Get-ADComputer -Filter * -SearchBase $ouDN | Select-Object -ExpandProperty Name
                Write-Host ""
                foreach ($computer in $computers) {
                    Check-WazuhService -ComputerName $computer
                }
            }
            catch {
                Write-Host "Erreur: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

# Boucle principale
do {
    Show-Menu
    $choice = Read-Host "Votre choix"
    
    switch ($choice) {
        "1" { Stop-SingleComputer }
        "2" { Stop-MultipleComputers }
        "3" { Stop-OUComputers }
        "4" { Stop-AllDomainComputers }
        "5" { Check-ServiceStatus }
        "Q" { 
            Write-Host "`nAu revoir!" -ForegroundColor Cyan
            break 
        }
        default { 
            Write-Host "`nChoix invalide" -ForegroundColor Red 
        }
    }
    
    if ($choice -ne "Q") {
        Write-Host "`n"
        Read-Host "Appuyez sur Entree pour continuer"
    }
    
} while ($choice -ne "Q")