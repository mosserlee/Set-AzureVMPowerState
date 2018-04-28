#
# Set power state of Azure VM to expected status.
#
function Set-AzureVMPowerState {
    param($VM, $ToOnline)
    if ($VM -eq $null) {
        return
    }

    $status = ($VM.Statuses[1].Code) -split '/' | Select-Object -Last 1
    if ( ($status -eq 'deallocated') -and $ToOnline) {
        Write-Log "Try to start VM [$($VM.Name)] ..."
        Start-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Confirm:$false
        return
    }
    if (($status -eq 'running') -and ( -not $ToOnline) ) {
        Write-Log "Try to stop VM [$($VM.Name)] ..."
        Stop-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Confirm:$false -Force
        return
    }
    Write-Log "VM [$($VM.Name)]'s current state is [$status], and consistent with expected status."
}

#
# Resolve online schedules of VM, and return expected status.
#
# Return Value:
# $null:      nothing to do, 
# $true:      online,
# $false:     offline
#
function Resolve-VMOnlineSchedule {
    param($GlobalSchedule, $VMSchedule)

    # Take vm schedule as hign priority
    $schedulePara = @($VMSchedule, $GlobalSchedule) |
        Where-Object {$_.Count -gt 0 } |
        Select-Object -First 1

    if ($schedulePara -eq $null) {
        return $null
    }

    $schedules = New-Object System.Collections.ArrayList($null)
    if ($schedulePara -is [array]) {
        $schedules.AddRange($schedulePara) | Out-Null
    }
    else {
        $schedules.Add($schedulePara) |Out-Null
    }

    if ($schedules.Count -eq 0) {
        return $null
    }
    $now = [DateTimeOffset]::Now
    foreach ($c in $schedules) {
        if ($c.DayOfWeek.Count -eq 0) {
            continue 
        }
        if ($now.DayOfWeek.ToString() -notin $c.DayOfWeek) {
            continue
        }
        if (($c.FromTime -eq $null) -and ($c.ToTime -eq $null)) {
            return $false
        }
        $from = [DateTimeOffset]($c.FromTime)
        $to = [DateTimeOffset]($c.ToTime)
        if ($from -lt $to) {
            return ($now -ge $from) -and ($now -lt $to)
        }
        else {
            return ($now -lt $from) -or ($now -ge $to)
        }
    }
    return $false
}


#
# Login in Azure Account
#
function Connect-AzureContext {
    param
    (
        $ServicePrincipal,
        $IsAzureAutomationLogin
    )
    # Login in with automation connection.    
    if ($IsAzureAutomationLogin) {
        try {
            $servicePrincipalConnection = Get-AutomationConnection -Name $ServicePrincipal.AzureAutomationConnectionName
            Write-Log "Logging in to Azure by automation connection [$($ServicePrincipal.AzureAutomationConnectionName)] ..."
            Add-AzureRmAccount `
                -ServicePrincipal `
                -TenantId $servicePrincipalConnection.TenantId `
                -ApplicationId $servicePrincipalConnection.ApplicationId `
                -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
        }
        catch {
            if (!$servicePrincipalConnection) {
                $ErrorMessage = "Connection $connectionName not found."
                throw $ErrorMessage
            }
            else {
                Write-Error -Message $_.Exception
                throw $_.Exception
            }
        }
    }
    # Login with customized service principal.
    else {
        #Set the powershell credential object
        $cred = new-object -typename System.Management.Automation.PSCredential `
            -argumentlist $ServicePrincipal.ApplicationId, (ConvertTo-SecureString –String $ServicePrincipal.AuthKey -AsPlainText -Force)

        #log On To Azure Account
        Write-Log 'Logging in to Azure by customized service principal ...'
        Add-AzureRmAccount -ServicePrincipal -Credential $cred -TenantId $ServicePrincipal.TenantId
    }
}

#
# Log message 
#
function Write-Log {
    
    param($Msg, [switch]$IsError, [switch]$IsWarning)
    
    $logType = 'INF'
    if ($IsWarning) { 
        $logType = 'WAR'
    }
    if ($IsError) { 
        $logType = 'ERR'
    }
    $msgBody = "{0:yyyy-MM-dd HH:mm:ss} :: {1} :: {2} " -f (Get-Date), $logType, $Msg
    if ($IsError) {
        Write-Error $msgBody
    }
    elseif ($IsWarning) {
        Write-Warning $msgBody
    }
    else {
        Write-Output $msgBody
    }
    $msgBody | Out-File $LogFile -Append
}

#
# Resolve the power state of Azure VM
#
function Resolve-AzureVMPowerState {
    foreach ($rg in $config.ResourceGroup) {
        foreach ($vm in $rg.VM) {
            $onlineSchedule = Resolve-VMOnlineSchedule -GlobalSchedule $config.OnlineSchedule -VMSchedule $vm.OnlineSchedule
            # Nothing to do when no condition configured
            if ($onlineSchedule -eq $null) {
                Write-Log "No schedule configured for vm [$($vm.Name)]."
            }
    
            $vmInstance = Get-AzureRmVM -ResourceGroupName $rg.Name -Name $vm.Name -Status -ErrorAction SilentlyContinue
            if ( -not $?) {
                
                Write-Log "Get-AzureRmVM failed:$($Error[0])" -IsError
            }
    
            if ($vmInstance -eq $null) {
                Write-Log "VM [$($vm.Name)] does not exist."
                continue
            }
            Set-AzureVMPowerState -VM $vmInstance -ToOnline $onlineSchedule
        }
    }
}


$ErrorActionPreference = 'stop'

# Log file init
[string]$LogFile = "$PSScriptRoot\Set-AzureVMPowerState.{0:yyyy-MM-dd_HH-mm}.log" -f (Get-Date)

# Read json configuration file
$configText = Get-Content "$PSScriptRoot\vm-power-state-config.json"

#### In Azure automation runbook environment, you can replace above line with HERE-String in-line configuration
#$configText = @"
#"@
###
$config = $configText |ConvertFrom-Json


# login Azure account 
Connect-AzureContext -ServicePrincipal $config.ServicePrincipal -IsAzureAutomationLogin  $config.IsAzureAutomationLogin

#Resolve VM's state 
Resolve-AzureVMPowerState 