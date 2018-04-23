# Set-AzureVMPowerState
Start and Stop Azure computer on schedule to save your cost.
## Feature
1. Secure design : run as on Azure service principal to access only limited resource.
2. Flexible to configure schedule. It supports to specify one or more global online schedules for multiple VMs, or specify one or more different online schedules for one VMs.
3. Easly intergate  with Windows task scheduler and Azure automation runbooks.

## Requirements
1. Windows PowerShell 5.0 +
2. Microsoft Azure PowerShell model 5.6.0 +
https://github.com/Azure/azure-powershell/releases

## Geting started

1. [Create an Azure AD application](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal#create-an-azure-active-directory-application) and record below parameters.
then save them into ServicePrincipal node in configuration file 
[vm-power-state-config.json](https://github.com/mosserlee/Set-AzureVMPowerState/blob/master/vm-power-state-config.json)

```json
    "ServicePrincipal": {
        "SubscriptionId": "c4698380-b489-4659-b95b-ca4bb8c7d602",
        "TenantId": "9da1f20e-f031-41fb-9d45-5c994d54753b",
        "ApplicationId": "34f3c0a3-c214-49b1-b960-eaeb421d2486",
        "AuthKey": "0fvxa97ANbCEA8ScWJhfSxD0Za1dK2LNpQ3zqcaMjdw#"
    },
```

2. Configue the resource group name and VM's name as below format:

```json
    "ResourceGroup": [
        {
            "Name": "resource-group-name-1",
            "VM": [
                {
                    "Name": "vm-name-1",
                },
                {
                    "Name": "vm-name-2"
                },
                {
                    "Name": "vm-name-3"
                }
            ]
        }
    ],
```
3. Confiure a global online schdeule in root node for all VMs, and a specific schedule for vm-name-1 as below:

**Notes :** Schedule configuraiton in VM node will **orverride** root node.

```json
{
    "ResourceGroup": [
        {
            "Name": "resource-group-name-1",
            "VM": [
                {
                    "Name": "vm-name-1",
                    "OnlineCondition": [
                        {
                            "DayOfWeek": [
                                "Monday",
                                "Tuesday"
                            ],
                            "FromTime": "06:00",
                            "ToTime": "18:00"
                        },
                        {
                            "DayOfWeek": [
                                "Thursday",
                                "Friday"
                            ],
                            "FromTime": "09:00",
                            "ToTime": "12:00"
                        }
                    ]
                },
                {
                    "Name": "vm-name-2"
                },
                {
                    "Name": "vm-name-3"
                }
            ]
        }
    ],
    "OnlineCondition": [
        {
            "DayOfWeek": [
                "Monday",
                "Tuesday",
                "Wednesday",
                "Thursday",
                "Friday"
            ],
            "FromTime": "18:00",
            "ToTime": "19:00"
        }
    ]
}
```

4. Test your script in PowerShell console.
``` PowerShell 
    PS D:\Set-AzureVMPowerState> .\Set-AzureVMPowerState.ps1
```

## More integrations

### Windows task scheduler
Need to do.

### Azure automation runbooks.
Need to do.