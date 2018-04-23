#
# Set power state of VM
#
function Set-AzureVMPowerState {
    param($VM, $OnlineCondition)
    if ($VM -eq $null) {
        return
    }

    $status = ($VM.Statuses[1].Code) -split '/' | select -Last 1
    if ( ($status -eq 'deallocated') -and $OnlineCondition) {
        Log-Message "Try to start VM [$($VM.Name)] ..."
        Start-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Confirm:$false
        return
    }
    if (($status -eq 'running') -and ( -not $OnlineCondition) ) {
        Log-Message "Try to stop VM [$($VM.Name)] ..."
        Stop-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Confirm:$false -Force
        return
    }
    Log-Message "VM [$($VM.Name)]'s current state is [$status], and consistent with expected status."
}

#
# Resolve online condition of VM, and return expected status.
#
# Return Value:
# $null:      nothing to do, 
# $true:      online,
# $false:     offline
#
function Resolve-VMOnlineCondition {
    param($GlobalCondition, $VMCondition)

    # take vm condition as hign priority
    $conditionPara = @($VMCondition, $GlobalCondition) | where {$_.Count -gt 0 } | select -First 1
    if ($conditionPara -eq $null) {
        return $null
    }

    $conditions = New-Object System.Collections.ArrayList($null)
    if ($conditionPara -is [array]) {
        $conditions.AddRange($conditionPara) | Out-Null
    }
    else {
        $conditions.Add($conditionPara) |Out-Null
    }

    if ($conditions.Count -eq 0) {
        return $null
    }
    $now = Get-Date
    foreach ($c in $conditions) {
        if ($c.DayOfWeek.Count -eq 0) {
            continue 
        }
        if ($now.DayOfWeek.ToString() -notin $c.DayOfWeek) {
            continue
        }
        if (($c.FromTime -eq $null) -and ($c.ToTime -eq $null)) {
            return $false
        }
        $from = [datetime]($c.FromTime)
        $to = [datetime]($c.ToTime)
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
    param($ServicePrincipal)

    #Set the powershell credential object\
    $cred = new-object -typename System.Management.Automation.PSCredential `
        -argumentlist $ServicePrincipal.ApplicationId, (ConvertTo-SecureString –String $ServicePrincipal.AuthKey -AsPlainText -Force)

    #log On To Azure Account
    Log-Message 'Log on azure account...'
    Add-AzureRmAccount -ServicePrincipal -Credential $cred -TenantId $ServicePrincipal.TenantId
}

#
# Log message 
#
function Log-Message {
    
    param($Msg, [switch]$IsError, [switch]$IsWarning)
    
    $logType = 'INF'
    $forcoler = 'White'
    if ($IsWarning) { 
        $logType = 'WAR'
        $forcoler = 'Yellow' 
    }
    if ($IsError) { 
        $logType = 'ERR'
        $forcoler = 'Red' 
    }
    $msgBody = "{0:yyyy-MM-dd HH:mm:ss} :: {1} :: {2} " -f (Get-Date), $logType, $Msg
    
    Write-Host $msgBody -ForegroundColor $forcoler
    $msgBody | Out-File $LogFile -Append
}

#
# Resolve the power state of Azure VM
#
function Resolve-AzureVMPowerState {
    foreach ($rg in $config.ResourceGroup) {
        foreach ($vm in $rg.VM) {
            $onlineCondition = Resolve-VMOnlineCondition -GlobalCondition $config.OnlineCondition -VMCondition $vm.OnlineCondition
            # Nothing to do when no condition configured
            if ($onlineCondition -eq $null) {
                Log-Message "No condition configured for vm [$($vm.Name)], since no online condition configured" -IsWarning
            }
    
            $vmInstance = Get-AzureRmVM -ResourceGroupName $rg.Name -Name $vm.Name -Status -ErrorAction SilentlyContinue
            if ( -not $?) {
                
                Log-Message "Get-AzureRmVM failed:$($Error[0])" -IsError
            }
    
            if ($vmInstance -eq $null) {
                Log-Message "VM [$($vm.Name)] does not exist."
                continue
            }
            Set-AzureVMPowerState -VM $vmInstance -OnlineCondition $onlineCondition
        }
    }
}


$ErrorActionPreference = 'stop'

# Log file init
[string]$LogFile = "$PSScriptRoot\Set-AzureVMPowerState.{0:yyyy-MM-dd_HH-mm}.log" -f (Get-Date)

# Read json configuration file
$config = Get-Content "$PSScriptRoot\vm-power-state-config.json" |ConvertFrom-Json

# login Azure account 
Connect-AzureContext -ServicePrincipal $config.ServicePrincipal

#Resolve VM's state 
Resolve-AzureVMPowerState 