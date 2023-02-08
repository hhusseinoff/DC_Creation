##############################################################################
#
#	XenDesktop Worker Script, used  by the revised DC_CreationMain script
#	
#		Created by: Hyusein Hyuseinov / SERVER-RSRVPXT 2022.12.30
#
#       Requirements: Must be run under an engineer's Server-Bensl/Server-ATA account in order for the SCCM, AD and XD cmdlets to run
#
#       Function: Imports an input machines to the XD Catalog and Delivery group based on input
#       
#       WARNING: The script will fail if executed immediately after the AD object for a machines has been created using the AD_Worker script
#       A few minutes are needed until the AD data for a machine is available for use by this script
#
##############################################################################

param (
[string]$ComputerName,
[string]$ComputerDomain,
[string]$XD_Controller,
[string]$XD_Hypervisor,
[string]$XD_CatalogName,
[string]$XD_DeliveryGroup,
[string]$MachineUUID
)

function debug($message)
{
    write-host "$(Get-Date -Format yyyy-MM-dd--HH-mm-ss) $message" -BackgroundColor Black -ForegroundColor Magenta
    Add-Content -Path "$PSScriptRoot\VerboseLogs\XD_Worker.log" -Value "$(Get-Date -Format yyyy-MM-dd--HH-mm-ss) $message" 
}

function debug_FailSkip([string]$DCName,[string]$Type,[string]$Reason)
{
    $FileExists = Test-Path -Path "$PSScriptRoot\FailSkipLogs\XD_FailSkip.txt" -PathType Leaf

    if($false -eq $FileExists)
    {
        Add-Content -Path "$PSScriptRoot\FailSkipLogs\XD_FailSkip.txt" -Value "--Timestamp(UTC)--`tMachineName`tType`tReason" 
    }

    Add-Content -Path "$PSScriptRoot\FailSkipLogs\XD_FailSkip.txt" -Value "$($(Get-Date).ToUniversalTime())`t$DCName`t$Type`t$Reason" 
}

function debug_Success([string]$DCName,[string]$XDControllerName,[string]$XDHypervisorName,[string]$XDCatalogName,[string]$XDDeliveryGroupName,[string]$DC_UUID)
{
    $FileExists = Test-Path -Path "$PSScriptRoot\SuccessLogs\XD_Success_OUT.txt" -PathType Leaf

    if($false -eq $FileExists)
    {
        Add-Content -Path "$PSScriptRoot\SuccessLogs\XD_Success_OUT.txt" -Value "--Timestamp(UTC)--`tMachineName`tXenDesktop Controller`tXenDesktop Hypervisor`tXenDesktop Catalog`tXenDesktop DeliveryGroup`tVM UUID" 
    }

    Add-Content -Path "$PSScriptRoot\SuccessLogs\XD_Success_OUT.txt" -Value "$($(Get-Date).ToUniversalTime())`t$DCName`t$XDControllerName`t$XDHypervisorName`t$XDCatalogName`t$XDDeliveryGroupName`t$DC_UUID" 
}

$FailSkipReason = "blank"

debug "------XD Worker Initiated------"

debug "Working on $ComputerName at domain $ComputerDomain on Controller $XD_Controller via Hypervisor $XD_Hypervisor"

debug "Set to go to Catalog $XD_CatalogName and DeliveryGroup $XD_DeliveryGroup"

debug "Given VM UUID is: $MachineUUID"

debug "Adding the Citrix Broker Snapin..."

Add-PSSnapin -Name "Citrix.Broker.Admin.V2"

debug "Checking if the Broker snapin has been loaded..."

$SnapinCheck = Get-PSSnapin -Name "Citrix.Broker.Admin.V2"

if($null -eq $SnapinCheck)
{
    debug "Failed to load the Broker Snapin. Exiting script..."

    $FailSkipReason = "Failed to load the Citrix Broker Snapin."

    debug_FailSkip -DCName $ComputerName -Type "FAIL" -Reason $FailSkipReason

    exit 0
}

debug "Ctrix Snapin loaded. Retrieving the Catalog Uid for $XD_CatalogName at $XD_Controller..."

$XD_CatalogObj = Get-BrokerCatalog -Name $XD_CatalogName -AdminAddress $XD_Controller

if($null -eq $XD_CatalogObj)
{
    debug "Failed to retrieve XD data for catalog $XD_CatalogName at $XD_Controller. Exiting script..."

    $FailSkipReason = "Failed to retrieve XD data for catalog $XD_CatalogName at $XD_Controller."

    debug_FailSkip -DCName $ComputerName -Type "FAIL" -Reason $FailSkipReason

    exit 0
}

$XD_CatalogUid = $XD_CatalogObj.Uid

debug "Successfully retrieved Catalog Uid $XD_CatalogUid for $XD_CatalogName."



debug "Retrieving Hypervisor Uid for $XD_Hypervisor at $XD_Controller..."

$XD_HyperVisorObj = Get-BrokerHypervisorConnection -Name $XD_Hypervisor -AdminAddress $XD_Controller

if($null -eq $XD_HyperVisorObj)
{
    debug "Failed to retrieve XD data for hypervisor $XD_Hypervisor at $XD_Controller. Exiting script..."

    $FailSkipReason = "Failed to retrieve XD data for hypervisor $XD_Hypervisor at $XD_Controller."

    debug_FailSkip -DCName $ComputerName -Type "FAIL" -Reason $FailSkipReason

    exit 0
}

$XD_HypervisorUid = $XD_HyperVisorObj.Uid

debug "Successfully retrieved Hypervisor Uid $XD_HypervisorUid for $XD_Hypervisor."


debug "Importing $ComputerName to XenDesktop..."

$CreationResult = New-BrokerMachine -CatalogUid $XD_CatalogUid -HypervisorConnectionUid $XD_HypervisorUid -MachineName "$ComputerDomain\$ComputerName" -HostedMachineId $VmUUID -AdminAddress $XD_Controller -ErrorAction Ignore

debug "Verifying if the import was successful..."

if($null -eq $CreationResult)
{
    debug "Failed to import $ComputerName to XD Catalog $XD_CatalogName at $XD_Controller. Verify the VM UUID. Exiting script..."

    $FailSkipReason = "Failed to import $ComputerName to XD Catalog $XD_CatalogName at $XD_Controller."

    debug_FailSkip -DCName $ComputerName -Type "FAIL" -Reason $FailSkipReason

    exit 0
}

debug "Importing $ComputerName was successful."

debug "Adding $ComputerName to Delivery Group $XD_DeliveryGroup..."

Add-BrokerMachine -InputObject $CreationResult -DesktopGroup $XD_DeliveryGroup -AdminAddress $XD_Controller -ErrorAction Ignore

debug "Verifying if the addition was successful..."

$PostAddResult = Get-BrokerMachine -HostedMachineId $VmUUID -AdminAddress $XD_Controller -ErrorAction Ignore

$PostAddResult_DG = $PostAddResult.DesktopGroupName

if($XD_DeliveryGroup -ne $PostAddResult_DG)
{
    debug "Failed to add $ComputerName to XD DeliveryGroup $XD_DeliveryGroup at $XD_Controller. Exiting script..."

    $FailSkipReason = "Failed to add $ComputerName to XD DeliveryGroup $XD_DeliveryGroup at $XD_Controller."

    debug_FailSkip -DCName $ComputerName -Type "FAIL" -Reason $FailSkipReason

    exit 0
}

debug "Successfully added $ComputerName to $XD_DeliveryGroup"

debug "Setting Maintenance Mode to ON..."

Set-BrokerPrivateDesktop -MachineName "$ComputerDomain\$ComputerName" -InMaintenanceMode:$true -AdminAddress $XD_Controller

debug "Verifying if MM is successfuly set ON..."

$PostMMResult = Get-BrokerMachine -MachineName "$ComputerDomain\$ComputerName" -AdminAddress $XD_Controller

$PostAddResult_MM = $PostMMResult.InMaintenanceMode

if($false -eq $PostAddResult_MM)
{
    debug "Failed to set MaintenaceMode ON for $ComputerName. Exiting script..."

    $FailSkipReason = "Failed to set MaintenaceMode ON."

    debug_FailSkip -DCName $ComputerName -Type "FAIL" -Reason $FailSkipReason

    exit 0
}

debug "Successfully set MaintenanceMode ON for $ComputerName."

debug "Appending to the success OUT file..."

debug_Success -DCName $ComputerName -XDControllerName $XD_Controller -XDHypervisorName $XD_Hypervisor -XDCatalogName $XD_CatalogName -XDDeliveryGroupName $XD_DeliveryGroup -DC_UUID $VmUUID

debug "Script Execution finished. Exiting..."

exit 0