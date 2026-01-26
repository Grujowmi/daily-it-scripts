# ==========================================================
#  Script Name  : Update_Zabbix.ps1
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


#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Script de pilotage pour la mise a jour de Zabbix Agent 2 sur le parc AD
.DESCRIPTION
    Permet de mettre a jour Zabbix Agent 2 sur:
    - Un PC specifique
    - Une Unite Organisationnelle (OU)
    - Tout le parc AD
.VERSION
    1.0.0
#>

param(
    [switch]$NoMenu
)

#region ===== CONFIGURATION =====
$Script:Config = @{
    # Chemins
    PackageShare        = "\\$env:USERDNSDOMAIN\NETLOGON\ZabbixUpdate\Packages"
    MsiFileName         = "#NOM_DU_MSI"
    MstFileName         = "#NOM_DU_MST" #LAISSER VIDE SI PAS DE MST
    LogPath             = "\\$env:USERDNSDOMAIN\NETLOGON\ZabbixUpdate\Logs"
    ReportPath          = "\\$env:USERDNSDOMAIN\NETLOGON\ZabbixUpdate\Reports"
    
    # Version cible
    TargetVersion       = "#NOUVELLE VERSION"
    
    # Parametres d'execution
    MaxParallelJobs     = 10
    TimeoutSeconds      = 300
    RetryCount          = 2
    
    # Filtres AD
    ExcludedComputers   = @("DC01", "DC02", "SQL-PROD")
    OnlyWindows         = $true
}

$Script:Colors = @{
    Success = "Green"
    Error   = "Red"
    Warning = "Yellow"
    Info    = "Cyan"
    Header  = "Magenta"
}
#endregion

#region ===== FONCTIONS UTILITAIRES =====

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO",
        [string]$ComputerName = "GLOBAL"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [$ComputerName] $Message"
    
    $logFile = Join-Path $Script:Config.LogPath "ZabbixUpdate_$(Get-Date -Format 'yyyyMMdd').log"
    
    if (-not (Test-Path $Script:Config.LogPath)) {
        New-Item -ItemType Directory -Path $Script:Config.LogPath -Force | Out-Null
    }
    
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
    
    $color = switch ($Level) {
        "SUCCESS" { $Script:Colors.Success }
        "ERROR"   { $Script:Colors.Error }
        "WARNING" { $Script:Colors.Warning }
        default   { $Script:Colors.Info }
    }
    
    Write-Host $logEntry -ForegroundColor $color
}

function Show-Banner {
    Clear-Host
    $banner = @"
+==============================================================================+
|                                                                              |
|     ZZZZZZ   AAA   BBBBB   BBBBB   III  X   X       U   U  PPPP              |
|        Z    A   A  B    B  B    B   I    X X        U   U  P   P             |
|       Z     AAAAA  BBBBB   BBBBB    I     X         U   U  PPPP              |
|      Z      A   A  B    B  B    B   I    X X        U   U  P                 |
|     ZZZZZZ  A   A  BBBBB   BBBBB   III  X   X        UUU   P                 |
|                                                                              |
|                    DEPLOYMENT & UPDATE TOOL v1.0                             |
|                    Target Version: $($Script:Config.TargetVersion.PadRight(42))|
+==============================================================================+
"@
    Write-Host $banner -ForegroundColor $Script:Colors.Header
}

function Test-Prerequisites {
    Write-Host "`n[*] Verification des prerequis..." -ForegroundColor $Script:Colors.Info
    
    $errors = @()
    
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        $errors += "Module ActiveDirectory non disponible"
    }
    
    $msiPath = Join-Path $Script:Config.PackageShare $Script:Config.MsiFileName
    if (-not (Test-Path $msiPath)) {
        $errors += "Package MSI introuvable: $msiPath"
    }
    
    if ($Script:Config.MstFileName -and $Script:Config.MstFileName -ne "") {
        $mstPath = Join-Path $Script:Config.PackageShare $Script:Config.MstFileName
        if (-not (Test-Path $mstPath)) {
            $errors += "Fichier MST introuvable: $mstPath"
        }
    }
    
    foreach ($path in @($Script:Config.LogPath, $Script:Config.ReportPath)) {
        if (-not (Test-Path $path)) {
            try {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                Write-Host "  [+] Dossier cree: $path" -ForegroundColor $Script:Colors.Success
            } catch {
                $errors += "Impossible de creer: $path"
            }
        }
    }
    
    if ($errors.Count -gt 0) {
        Write-Host "`n[!] ERREURS DETECTEES:" -ForegroundColor $Script:Colors.Error
        $errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor $Script:Colors.Error }
        return $false
    }
    
    Write-Host "  [+] Tous les prerequis sont OK" -ForegroundColor $Script:Colors.Success
    return $true
}
#endregion

#region ===== FONCTIONS AD =====

function Get-ADOrganizationalUnitsTree {
    $domain = Get-ADDomain
    $allOUs = Get-ADOrganizationalUnit -Filter * -Properties CanonicalName | 
              Sort-Object CanonicalName
    
    $ouList = @()
    $index = 1
    
    foreach ($ou in $allOUs) {
        $depth = ($ou.CanonicalName.Split('/').Count - 2)
        $indent = "  " * $depth
        
        $computerCount = (Get-ADComputer -Filter * -SearchBase $ou.DistinguishedName -SearchScope OneLevel -ErrorAction SilentlyContinue).Count
        $computerCountRecursive = (Get-ADComputer -Filter * -SearchBase $ou.DistinguishedName -ErrorAction SilentlyContinue).Count
        
        $ouList += [PSCustomObject]@{
            Index                   = $index
            Name                    = $ou.Name
            DistinguishedName       = $ou.DistinguishedName
            DisplayName             = "$indent+-- $($ou.Name)"
            ComputersCount          = $computerCount
            ComputersCountRecursive = $computerCountRecursive
            Depth                   = $depth
        }
        $index++
    }
    
    return $ouList
}

function Get-TargetComputers {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Single", "OU", "All")]
        [string]$Scope,
        
        [string]$Target,
        [switch]$Recursive
    )
    
    $computers = @()
    
    switch ($Scope) {
        "Single" {
            try {
                $comp = Get-ADComputer -Identity $Target -Properties OperatingSystem, LastLogonDate -ErrorAction Stop
                $computers += $comp
            } catch {
                Write-Log "Ordinateur '$Target' non trouve dans AD" -Level ERROR
                return $null
            }
        }
        
        "OU" {
            $searchScope = if ($Recursive) { "Subtree" } else { "OneLevel" }
            $computers = Get-ADComputer -Filter * -SearchBase $Target -SearchScope $searchScope -Properties OperatingSystem, LastLogonDate -ErrorAction SilentlyContinue
        }
        
        "All" {
            $computers = Get-ADComputer -Filter * -Properties OperatingSystem, LastLogonDate -ErrorAction SilentlyContinue
        }
    }
    
    if ($Script:Config.OnlyWindows) {
        $computers = $computers | Where-Object { $_.OperatingSystem -like "*Windows*" }
    }
    
    $computers = $computers | Where-Object { $_.Name -notin $Script:Config.ExcludedComputers }
    $computers = $computers | Where-Object { $_.OperatingSystem -notlike "*Domain Controller*" }
    
    return $computers
}
#endregion

#region ===== FONCTIONS DE DEPLOIEMENT =====

function Test-ComputerConnectivity {
    param([string]$ComputerName)
    
    $ping = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $ping) { return $false }
    
    try {
        $null = Test-WSMan -ComputerName $ComputerName -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-ZabbixAgentVersion {
    param([string]$ComputerName)
    
    try {
        $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            $uninstallPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )
            
            foreach ($path in $uninstallPaths) {
                $zabbix = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | 
                          Where-Object { $_.DisplayName -like "*Zabbix Agent*" }
                if ($zabbix) {
                    return @{
                        Installed   = $true
                        Version     = $zabbix.DisplayVersion
                        InstallPath = $zabbix.InstallLocation
                    }
                }
            }
            
            $exePaths = @(
                "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe",
                "C:\Program Files\Zabbix Agent\zabbix_agentd.exe"
            )
            
            foreach ($exePath in $exePaths) {
                if (Test-Path $exePath) {
                    $version = (Get-Item $exePath).VersionInfo.ProductVersion
                    return @{
                        Installed   = $true
                        Version     = $version
                        InstallPath = Split-Path $exePath -Parent
                    }
                }
            }
            
            return @{ Installed = $false; Version = $null; InstallPath = $null }
            
        } -ErrorAction Stop
        
        return $result
        
    } catch {
        return @{ Installed = $null; Version = "ERROR"; InstallPath = $null; Error = $_.Exception.Message }
    }
}

function Install-ZabbixAgent {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )
    
    $result = [PSCustomObject]@{
        ComputerName    = $ComputerName
        Status          = "Unknown"
        PreviousVersion = $null
        NewVersion      = $null
        Message         = ""
        Duration        = 0
    }
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        Write-Log "Test de connectivite..." -Level INFO -ComputerName $ComputerName
        if (-not (Test-ComputerConnectivity -ComputerName $ComputerName)) {
            $result.Status = "Offline"
            $result.Message = "Machine inaccessible (ping ou WinRM)"
            Write-Log $result.Message -Level WARNING -ComputerName $ComputerName
            return $result
        }
        
        Write-Log "Verification de la version actuelle..." -Level INFO -ComputerName $ComputerName
        $currentVersion = Get-ZabbixAgentVersion -ComputerName $ComputerName
        $result.PreviousVersion = $currentVersion.Version
        
        if ($currentVersion.Version -eq $Script:Config.TargetVersion) {
            $result.Status = "AlreadyUpToDate"
            $result.NewVersion = $currentVersion.Version
            $result.Message = "Deja a jour ($($Script:Config.TargetVersion))"
            Write-Log $result.Message -Level SUCCESS -ComputerName $ComputerName
            return $result
        }
        
        $msiPath = Join-Path $Script:Config.PackageShare $Script:Config.MsiFileName
        $mstPath = if ($Script:Config.MstFileName) { 
            Join-Path $Script:Config.PackageShare $Script:Config.MstFileName 
        } else { $null }
        
        $msiArgs = "/i `"$msiPath`" /qn /norestart /l*v `"C:\Windows\Temp\ZabbixAgent_Install.log`""
        if ($mstPath) {
            $msiArgs += " TRANSFORMS=`"$mstPath`""
        }
        
        Write-Log "Lancement de l'installation..." -Level INFO -ComputerName $ComputerName
        
        $installResult = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($msiArgs)
            
            $services = @("Zabbix Agent 2", "Zabbix Agent")
            foreach ($svc in $services) {
                $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
                if ($service -and $service.Status -eq "Running") {
                    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                }
            }
            
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
            
            Start-Sleep -Seconds 3
            foreach ($svc in $services) {
                $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
                if ($service) {
                    Start-Service -Name $svc -ErrorAction SilentlyContinue
                    break
                }
            }
            
            return @{
                ExitCode = $process.ExitCode
                Success  = ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010)
            }
            
        } -ArgumentList $msiArgs -ErrorAction Stop
        
        if ($installResult.Success) {
            Start-Sleep -Seconds 2
            $newVersion = Get-ZabbixAgentVersion -ComputerName $ComputerName
            $result.NewVersion = $newVersion.Version
            $result.Status = "Success"
            $result.Message = "Mise a jour reussie: $($result.PreviousVersion) -> $($result.NewVersion)"
            Write-Log $result.Message -Level SUCCESS -ComputerName $ComputerName
        } else {
            $result.Status = "Failed"
            $result.Message = "Echec de l'installation (Code: $($installResult.ExitCode))"
            Write-Log $result.Message -Level ERROR -ComputerName $ComputerName
        }
        
    } catch {
        $result.Status = "Error"
        $result.Message = "Exception: $($_.Exception.Message)"
        Write-Log $result.Message -Level ERROR -ComputerName $ComputerName
    }
    
    $stopwatch.Stop()
    $result.Duration = $stopwatch.Elapsed.TotalSeconds
    
    return $result
}

function Start-SequentialDeployment {
    param(
        [Parameter(Mandatory)]
        [array]$Computers
    )
    
    $results = @()
    $totalCount = $Computers.Count
    $current = 0
    
    foreach ($computer in $Computers) {
        $current++
        $percent = [math]::Round(($current / $totalCount) * 100)
        
        Write-Progress -Activity "Deploiement Zabbix Agent 2" `
                       -Status "[$current/$totalCount] $($computer.Name)" `
                       -PercentComplete $percent
        
        $result = Install-ZabbixAgent -ComputerName $computer.Name
        $results += $result
    }
    
    Write-Progress -Activity "Deploiement Zabbix Agent 2" -Completed
    
    return $results
}
#endregion

#region ===== RAPPORT =====

function New-DeploymentReport {
    param(
        [Parameter(Mandatory)]
        [array]$Results,
        [string]$Scope
    )
    
    $reportDate = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportFile = Join-Path $Script:Config.ReportPath "ZabbixDeployment_$reportDate.html"
    
    $stats = @{
        Total           = $Results.Count
        Success         = ($Results | Where-Object { $_.Status -eq "Success" }).Count
        AlreadyUpToDate = ($Results | Where-Object { $_.Status -eq "AlreadyUpToDate" }).Count
        Failed          = ($Results | Where-Object { $_.Status -eq "Failed" }).Count
        Offline         = ($Results | Where-Object { $_.Status -eq "Offline" }).Count
        Error           = ($Results | Where-Object { $_.Status -eq "Error" }).Count
    }
    
    $tableRows = ""
    foreach ($r in ($Results | Sort-Object Status, ComputerName)) {
        $tableRows += @"
        <tr>
            <td><strong>$($r.ComputerName)</strong></td>
            <td><span class="status $($r.Status)">$($r.Status)</span></td>
            <td>$($r.PreviousVersion)</td>
            <td>$($r.NewVersion)</td>
            <td>$([math]::Round($r.Duration, 1))s</td>
            <td>$($r.Message)</td>
        </tr>
"@
    }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Rapport Deploiement Zabbix Agent 2</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #1a1a2e; color: #eee; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; border-radius: 10px; margin-bottom: 20px; }
        .header h1 { margin: 0; color: white; }
        .header p { margin: 5px 0 0 0; color: rgba(255,255,255,0.8); }
        .stats { display: flex; gap: 15px; margin-bottom: 20px; flex-wrap: wrap; }
        .stat-card { background: #16213e; padding: 20px; border-radius: 10px; min-width: 150px; text-align: center; }
        .stat-card.success { border-left: 4px solid #00b894; }
        .stat-card.uptodate { border-left: 4px solid #0984e3; }
        .stat-card.failed { border-left: 4px solid #d63031; }
        .stat-card.offline { border-left: 4px solid #fdcb6e; }
        .stat-card .number { font-size: 2.5em; font-weight: bold; }
        .stat-card .label { color: #888; }
        table { width: 100%; border-collapse: collapse; background: #16213e; border-radius: 10px; overflow: hidden; }
        th { background: #0f3460; padding: 15px; text-align: left; }
        td { padding: 12px 15px; border-bottom: 1px solid #0f3460; }
        tr:hover { background: #1a1a40; }
        .status { padding: 5px 12px; border-radius: 20px; font-size: 0.85em; font-weight: bold; }
        .status.Success { background: #00b894; color: white; }
        .status.AlreadyUpToDate { background: #0984e3; color: white; }
        .status.Failed { background: #d63031; color: white; }
        .status.Offline { background: #fdcb6e; color: #2d3436; }
        .status.Error { background: #e17055; color: white; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Rapport de Deploiement - Zabbix Agent 2</h1>
        <p>Version cible: $($Script:Config.TargetVersion) | Genere le: $(Get-Date -Format "dd/MM/yyyy HH:mm:ss") | Scope: $Scope</p>
    </div>
    
    <div class="stats">
        <div class="stat-card success">
            <div class="number">$($stats.Success)</div>
            <div class="label">Succes</div>
        </div>
        <div class="stat-card uptodate">
            <div class="number">$($stats.AlreadyUpToDate)</div>
            <div class="label">Deja a jour</div>
        </div>
        <div class="stat-card failed">
            <div class="number">$($stats.Failed)</div>
            <div class="label">Echecs</div>
        </div>
        <div class="stat-card offline">
            <div class="number">$($stats.Offline)</div>
            <div class="label">Hors ligne</div>
        </div>
    </div>
    
    <table>
        <tr>
            <th>Ordinateur</th>
            <th>Statut</th>
            <th>Version precedente</th>
            <th>Nouvelle version</th>
            <th>Duree</th>
            <th>Message</th>
        </tr>
        $tableRows
    </table>
</body>
</html>
"@

    $html | Out-File -FilePath $reportFile -Encoding UTF8
    
    Write-Host "`n[RAPPORT] Genere: $reportFile" -ForegroundColor $Script:Colors.Success
    
    Start-Process $reportFile
    
    return $reportFile
}
#endregion

#region ===== MENUS INTERACTIFS =====

function Show-MainMenu {
    Write-Host "`n+========================================+" -ForegroundColor $Script:Colors.Header
    Write-Host "|           MENU PRINCIPAL               |" -ForegroundColor $Script:Colors.Header
    Write-Host "+========================================+" -ForegroundColor $Script:Colors.Header
    Write-Host "|  [1] Patcher un PC specifique          |" -ForegroundColor White
    Write-Host "|  [2] Patcher une OU                    |" -ForegroundColor White
    Write-Host "|  [3] Patcher tout le parc              |" -ForegroundColor White
    Write-Host "|  [4] Verifier une machine              |" -ForegroundColor White
    Write-Host "|  [5] Inventaire des versions           |" -ForegroundColor White
    Write-Host "|  [6] Configuration                     |" -ForegroundColor White
    Write-Host "|  [Q] Quitter                           |" -ForegroundColor White
    Write-Host "+========================================+" -ForegroundColor $Script:Colors.Header
    
    $choice = Read-Host "`nVotre choix"
    return $choice.ToUpper()
}

function Invoke-SingleComputerPatch {
    Write-Host "`n=======================================" -ForegroundColor $Script:Colors.Info
    Write-Host "  PATCH D'UN PC SPECIFIQUE" -ForegroundColor $Script:Colors.Info
    Write-Host "=======================================`n" -ForegroundColor $Script:Colors.Info
    
    $computerName = Read-Host "Nom de l'ordinateur (ou 'retour' pour annuler)"
    
    if ($computerName -eq "retour") { return }
    
    $computers = Get-TargetComputers -Scope Single -Target $computerName
    
    if (-not $computers) {
        Write-Host "Ordinateur non trouve dans l'Active Directory." -ForegroundColor $Script:Colors.Error
        Read-Host "Appuyez sur Entree pour continuer"
        return
    }
    
    Write-Host "`nMachine trouvee: $($computers.Name)" -ForegroundColor $Script:Colors.Success
    Write-Host "OS: $($computers.OperatingSystem)" -ForegroundColor Gray
    
    $confirm = Read-Host "`nLancer le patch? (O/N)"
    if ($confirm.ToUpper() -ne "O") { return }
    
    $result = Install-ZabbixAgent -ComputerName $computers.Name
    
    Write-Host "`n=======================================" -ForegroundColor $Script:Colors.Info
    Write-Host "  RESULTAT" -ForegroundColor $Script:Colors.Info
    Write-Host "=======================================" -ForegroundColor $Script:Colors.Info
    
    $color = switch ($result.Status) {
        "Success"         { $Script:Colors.Success }
        "AlreadyUpToDate" { $Script:Colors.Success }
        "Failed"          { $Script:Colors.Error }
        "Offline"         { $Script:Colors.Warning }
        default           { $Script:Colors.Warning }
    }
    
    Write-Host "`nStatut: $($result.Status)" -ForegroundColor $color
    Write-Host "Message: $($result.Message)" -ForegroundColor $color
    Write-Host "Version: $($result.PreviousVersion) -> $($result.NewVersion)" -ForegroundColor Gray
    
    Read-Host "`nAppuyez sur Entree pour continuer"
}

function Invoke-OUPatch {
    Write-Host "`n=======================================" -ForegroundColor $Script:Colors.Info
    Write-Host "  PATCH D'UNE UNITE ORGANISATIONNELLE" -ForegroundColor $Script:Colors.Info
    Write-Host "=======================================`n" -ForegroundColor $Script:Colors.Info
    
    Write-Host "Chargement des OUs..." -ForegroundColor Gray
    $ous = Get-ADOrganizationalUnitsTree
    
    Write-Host "`n+-------+--------------------------------------------------+----------------+"
    Write-Host "| #     | Unite Organisationnelle                          | PCs (recursif) |"
    Write-Host "+-------+--------------------------------------------------+----------------+"
    
    foreach ($ou in $ous) {
        $displayName = $ou.DisplayName
        if ($displayName.Length -gt 48) {
            $displayName = $displayName.Substring(0, 45) + "..."
        }
        $displayName = $displayName.PadRight(48)
        $count = "$($ou.ComputersCountRecursive)".PadLeft(5)
        Write-Host ("| {0,-5} | {1} | {2}          |" -f $ou.Index, $displayName, $count)
    }
    
    Write-Host "+-------+--------------------------------------------------+----------------+"
    
    $selection = Read-Host "`nNumero de l'OU (ou 'retour')"
    if ($selection -eq "retour") { return }
    
    try {
        $selectedOU = $ous | Where-Object { $_.Index -eq [int]$selection }
    } catch {
        Write-Host "Selection invalide." -ForegroundColor $Script:Colors.Error
        Read-Host "Appuyez sur Entree"
        return
    }
    
    if (-not $selectedOU) {
        Write-Host "Selection invalide." -ForegroundColor $Script:Colors.Error
        Read-Host "Appuyez sur Entree"
        return
    }
    
    Write-Host "`nOU selectionnee: $($selectedOU.Name)" -ForegroundColor $Script:Colors.Success
    Write-Host "DN: $($selectedOU.DistinguishedName)" -ForegroundColor Gray
    
    $recursive = Read-Host "Inclure les sous-OUs? (O/N)"
    $includeSubOUs = ($recursive.ToUpper() -eq "O")
    
    $computers = Get-TargetComputers -Scope OU -Target $selectedOU.DistinguishedName -Recursive:$includeSubOUs
    
    if (-not $computers -or $computers.Count -eq 0) {
        Write-Host "Aucun ordinateur trouve dans cette OU." -ForegroundColor $Script:Colors.Warning
        Read-Host "Appuyez sur Entree"
        return
    }
    
    Write-Host "`n$($computers.Count) ordinateur(s) trouve(s):" -ForegroundColor $Script:Colors.Info
    $computers | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
    
    $confirm = Read-Host "`nLancer le deploiement? (O/N)"
    if ($confirm.ToUpper() -ne "O") { return }
    
    $results = Start-SequentialDeployment -Computers $computers
    
    New-DeploymentReport -Results $results -Scope "OU: $($selectedOU.Name)"
    
    Read-Host "`nAppuyez sur Entree pour continuer"
}

function Invoke-FullParkPatch {
    Write-Host "`n=======================================" -ForegroundColor $Script:Colors.Info
    Write-Host "  PATCH DE TOUT LE PARC" -ForegroundColor $Script:Colors.Info
    Write-Host "=======================================`n" -ForegroundColor $Script:Colors.Info
    
    Write-Host "Analyse du parc..." -ForegroundColor Gray
    $computers = Get-TargetComputers -Scope All
    
    Write-Host "`n[!] ATTENTION [!]" -ForegroundColor $Script:Colors.Warning
    Write-Host "Vous etes sur le point de deployer sur $($computers.Count) machines." -ForegroundColor $Script:Colors.Warning
    Write-Host "`nMachines exclues: $($Script:Config.ExcludedComputers -join ', ')" -ForegroundColor Gray
    
    Write-Host "`nRecapitulatif par OS:" -ForegroundColor $Script:Colors.Info
    $computers | Group-Object OperatingSystem | Sort-Object Count -Descending | ForEach-Object {
        Write-Host "  $($_.Count) x $($_.Name)" -ForegroundColor Gray
    }
    
    Write-Host "`n"
    $confirm1 = Read-Host "Etes-vous sur? Tapez 'CONFIRMER' pour continuer"
    if ($confirm1 -ne "CONFIRMER") {
        Write-Host "Operation annulee." -ForegroundColor $Script:Colors.Warning
        Read-Host "Appuyez sur Entree"
        return
    }
    
    Write-Host "`nDeploiement en cours..." -ForegroundColor $Script:Colors.Info
    
    $results = Start-SequentialDeployment -Computers $computers
    
    New-DeploymentReport -Results $results -Scope "Parc complet"
    
    Read-Host "`nAppuyez sur Entree pour continuer"
}

function Show-ComputerInfo {
    Write-Host "`n=======================================" -ForegroundColor $Script:Colors.Info
    Write-Host "  VERIFICATION D'UNE MACHINE" -ForegroundColor $Script:Colors.Info
    Write-Host "=======================================`n" -ForegroundColor $Script:Colors.Info
    
    $computerName = Read-Host "Nom de l'ordinateur"
    
    Write-Host "`nAnalyse de $computerName..." -ForegroundColor Gray
    
    $online = Test-ComputerConnectivity -ComputerName $computerName
    
    Write-Host "`n+----------------------------------------------------------+"
    Write-Host "|  INFORMATIONS: $($computerName.PadRight(41)) |"
    Write-Host "+----------------------------------------------------------+"
    
    if ($online) {
        Write-Host "|  Connectivite:    [OK] En ligne                          |" -ForegroundColor $Script:Colors.Success
        
        $zabbixInfo = Get-ZabbixAgentVersion -ComputerName $computerName
        
        if ($zabbixInfo.Installed) {
            $versionColor = if ($zabbixInfo.Version -eq $Script:Config.TargetVersion) { 
                $Script:Colors.Success 
            } else { 
                $Script:Colors.Warning 
            }
            Write-Host "|  Zabbix Agent:    [OK] Installe                          |" -ForegroundColor $Script:Colors.Success
            
            $versionDisplay = if ($zabbixInfo.Version) { $zabbixInfo.Version } else { "N/A" }
            Write-Host "|  Version:         $($versionDisplay.PadRight(39)) |" -ForegroundColor $versionColor
            
            $pathDisplay = if ($zabbixInfo.InstallPath) { $zabbixInfo.InstallPath } else { "N/A" }
            if ($pathDisplay.Length -gt 38) { $pathDisplay = $pathDisplay.Substring(0, 35) + "..." }
            Write-Host "|  Chemin:          $($pathDisplay.PadRight(39)) |"
            
            if ($zabbixInfo.Version -ne $Script:Config.TargetVersion) {
                Write-Host "|                                                          |"
                Write-Host "|  [!] Mise a jour disponible vers $($Script:Config.TargetVersion)                    |" -ForegroundColor $Script:Colors.Warning
            }
        } else {
            Write-Host "|  Zabbix Agent:    [X] Non installe                       |" -ForegroundColor $Script:Colors.Error
        }
    } else {
        Write-Host "|  Connectivite:    [X] Hors ligne / Inaccessible          |" -ForegroundColor $Script:Colors.Error
    }
    
    Write-Host "+----------------------------------------------------------+"
    
    Read-Host "`nAppuyez sur Entree pour continuer"
}

function Show-VersionInventory {
    Write-Host "`n=======================================" -ForegroundColor $Script:Colors.Info
    Write-Host "  INVENTAIRE DES VERSIONS" -ForegroundColor $Script:Colors.Info
    Write-Host "=======================================`n" -ForegroundColor $Script:Colors.Info
    
    Write-Host "Selectionnez le scope:" -ForegroundColor $Script:Colors.Info
    Write-Host "  [1] Une OU specifique"
    Write-Host "  [2] Tout le parc"
    $scope = Read-Host "Choix"
    
    if ($scope -eq "1") {
        $ous = Get-ADOrganizationalUnitsTree
        foreach ($ou in $ous) {
            Write-Host ("  [{0}] {1} ({2} PCs)" -f $ou.Index, $ou.Name, $ou.ComputersCountRecursive)
        }
        $ouChoice = Read-Host "Numero de l'OU"
        try {
            $selectedOU = $ous | Where-Object { $_.Index -eq [int]$ouChoice }
            $computers = Get-TargetComputers -Scope OU -Target $selectedOU.DistinguishedName -Recursive
        } catch {
            Write-Host "Selection invalide." -ForegroundColor $Script:Colors.Error
            Read-Host "Appuyez sur Entree"
            return
        }
    } else {
        $computers = Get-TargetComputers -Scope All
    }
    
    if (-not $computers -or $computers.Count -eq 0) {
        Write-Host "Aucun ordinateur trouve." -ForegroundColor $Script:Colors.Warning
        Read-Host "Appuyez sur Entree"
        return
    }
    
    Write-Host "`nAnalyse de $($computers.Count) machines..." -ForegroundColor Gray
    
    $inventory = @()
    $i = 0
    
    foreach ($computer in $computers) {
        $i++
        Write-Progress -Activity "Inventaire" -Status $computer.Name -PercentComplete (($i / $computers.Count) * 100)
        
        $online = Test-ComputerConnectivity -ComputerName $computer.Name
        
        if ($online) {
            $zabbixInfo = Get-ZabbixAgentVersion -ComputerName $computer.Name
            $inventory += [PSCustomObject]@{
                ComputerName = $computer.Name
                Status       = "Online"
                Installed    = $zabbixInfo.Installed
                Version      = $zabbixInfo.Version
                NeedsUpdate  = ($zabbixInfo.Version -ne $Script:Config.TargetVersion)
            }
        } else {
            $inventory += [PSCustomObject]@{
                ComputerName = $computer.Name
                Status       = "Offline"
                Installed    = $null
                Version      = "N/A"
                NeedsUpdate  = $null
            }
        }
    }
    
    Write-Progress -Activity "Inventaire" -Completed
    
    Write-Host "`n[STATS] RESUME DE L'INVENTAIRE" -ForegroundColor $Script:Colors.Header
    Write-Host "=========================================================="
    
    $online = ($inventory | Where-Object { $_.Status -eq "Online" }).Count
    $offline = ($inventory | Where-Object { $_.Status -eq "Offline" }).Count
    $upToDate = ($inventory | Where-Object { -not $_.NeedsUpdate -and $_.Status -eq "Online" }).Count
    $needsUpdate = ($inventory | Where-Object { $_.NeedsUpdate -and $_.Status -eq "Online" }).Count
    $notInstalled = ($inventory | Where-Object { $_.Installed -eq $false }).Count
    
    Write-Host "  Total machines:        $($computers.Count)"
    Write-Host "  En ligne:              $online" -ForegroundColor $Script:Colors.Success
    Write-Host "  Hors ligne:            $offline" -ForegroundColor $Script:Colors.Warning
    Write-Host "  A jour ($($Script:Config.TargetVersion)):        $upToDate" -ForegroundColor $Script:Colors.Success
    Write-Host "  Mise a jour requise:   $needsUpdate" -ForegroundColor $Script:Colors.Warning
    Write-Host "  Non installe:          $notInstalled" -ForegroundColor $Script:Colors.Error
    
    Write-Host "`n[DETAIL] PAR VERSION" -ForegroundColor $Script:Colors.Header
    $inventory | Where-Object { $_.Status -eq "Online" -and $_.Version } | 
                 Group-Object Version | 
                 Sort-Object Count -Descending |
                 ForEach-Object {
                     $icon = if ($_.Name -eq $Script:Config.TargetVersion) { "[OK]" } else { "[!]" }
                     Write-Host "  $icon $($_.Name): $($_.Count) machine(s)"
                 }
    
    $exportChoice = Read-Host "`nExporter en CSV? (O/N)"
    if ($exportChoice.ToUpper() -eq "O") {
        $csvPath = Join-Path $Script:Config.ReportPath "Inventory_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $inventory | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Exporte vers: $csvPath" -ForegroundColor $Script:Colors.Success
    }
    
    Read-Host "`nAppuyez sur Entree pour continuer"
}

function Show-Configuration {
    Write-Host "`n=======================================" -ForegroundColor $Script:Colors.Info
    Write-Host "  CONFIGURATION ACTUELLE" -ForegroundColor $Script:Colors.Info
    Write-Host "=======================================`n" -ForegroundColor $Script:Colors.Info
    
    Write-Host "[PACKAGES]" -ForegroundColor $Script:Colors.Header
    Write-Host "  Partage:       $($Script:Config.PackageShare)"
    Write-Host "  MSI:           $($Script:Config.MsiFileName)"
    $mstDisplay = if ($Script:Config.MstFileName) { $Script:Config.MstFileName } else { "Non configure" }
    Write-Host "  MST:           $mstDisplay"
    Write-Host "  Version cible: $($Script:Config.TargetVersion)"
    
    Write-Host "`n[CHEMINS]" -ForegroundColor $Script:Colors.Header
    Write-Host "  Logs:          $($Script:Config.LogPath)"
    Write-Host "  Rapports:      $($Script:Config.ReportPath)"
    
    Write-Host "`n[PARAMETRES]" -ForegroundColor $Script:Colors.Header
    Write-Host "  Jobs paralleles:  $($Script:Config.MaxParallelJobs)"
    Write-Host "  Timeout:          $($Script:Config.TimeoutSeconds)s"
    Write-Host "  Retry:            $($Script:Config.RetryCount)"
    
    Write-Host "`n[EXCLUSIONS]" -ForegroundColor $Script:Colors.Header
    Write-Host "  Machines:      $($Script:Config.ExcludedComputers -join ', ')"
    Write-Host "  Windows only:  $($Script:Config.OnlyWindows)"
    
    Read-Host "`nAppuyez sur Entree pour continuer"
}
#endregion

#region ===== POINT D'ENTREE =====

function Start-DeploymentTool {
    Show-Banner
    
    if (-not (Test-Prerequisites)) {
        Write-Host "`n[X] Prerequis non satisfaits. Corrigez les erreurs et relancez." -ForegroundColor $Script:Colors.Error
        Read-Host "Appuyez sur Entree pour quitter"
        exit 1
    }
    
    do {
        Show-Banner
        $choice = Show-MainMenu
        
        switch ($choice) {
            "1" { Invoke-SingleComputerPatch }
            "2" { Invoke-OUPatch }
            "3" { Invoke-FullParkPatch }
            "4" { Show-ComputerInfo }
            "5" { Show-VersionInventory }
            "6" { Show-Configuration }
            "Q" { 
                Write-Host "`nAu revoir!" -ForegroundColor $Script:Colors.Success
                break 
            }
            default {
                Write-Host "Option invalide." -ForegroundColor $Script:Colors.Warning
                Start-Sleep -Seconds 1
            }
        }
        
    } while ($choice -ne "Q")
}

# Lancement
Start-DeploymentTool
#endregion