##############################################################################
#
#	SCCM Worker Script, used  by the revised DC_CreationMain script
#	
#		Created by: Hyusein Hyuseinov / SERVER-RSRVPXT 2022.12.30
#
#       Requirements: Must be run under an engineer's Server-Bensl/Server-ATA account in order for the SCCM, AD and XD cmdlets to run
#
#       Function: Imports a machine to the SCCM Database using the passed parameters
#
#       If the ConfigurationManager Powershell Module can't be loaded, or the ScriptDir doesn't change correctly after Loading the module
#       The input machine will NOT be imported in SCCM AND a handy .csv File (SCCM_MachineImportFails_$DateTime.csv) with info for Fails will be created in Folder
#       FailSkipLogs. That .csv can be used to manually import machines in bulk to SCCM
#
##############################################################################


param (
[string]$ComputerName,
[string]$MAC,
[string]$CollectionName,
[string]$SCCMDir
)

$BeginningScriptRoot = $PSScriptRoot

function debug($message)
{
    write-host "$(Get-Date -Format yyyy-MM-dd--HH-mm-ss) $message" -BackgroundColor Black -ForegroundColor Cyan
    Add-Content -Path "$BeginningScriptRoot\VerboseLogs\SCCM_Worker.log" -Value "$(Get-Date -Format yyyy-MM-dd--HH-mm-ss) $message" 
}

function debug_FailSkip([string]$DCName,[string]$Type,[string]$Reason)
{
    $FileExists = Test-Path -Path "$BeginningScriptRoot\FailSkipLogs\SCCM_FailSkip.txt" -PathType Leaf

    if($false -eq $FileExists)
    {
        Add-Content -Path "$BeginningScriptRoot\FailSkipLogs\SCCM_FailSkip.txt" -Value "--Timestamp(UTC)--`tMachineName`tType`tReason" 
    }

    Add-Content -Path "$BeginningScriptRoot\FailSkipLogs\SCCM_FailSkip.txt" -Value "$($(Get-Date).ToUniversalTime())`t$DCName`t$Type`t$Reason" 
}

function debug_FailCSV([string]$DCName,[string]$MACAddress,[string]$DateTime)
{
     $entry = [PSCustomObject]@{
        Name = $DCName
        MACAddress = $MACAddress
     }

     Export-Csv -InputObject $entry -Path "$BeginningScriptRoot\FailSkipLogs\SCCM_MachineImportFails_$DateTime.csv" -Force -Append -NoTypeInformation -Confirm:$false -ErrorAction Ignore
}

function debug_Success([string]$DCName,[string]$MACAddress,[string]$Collection)
{
    $FileExists = Test-Path -Path "$BeginningScriptRoot\SuccessLogs\SCCM_Success_OUT.txt" -PathType Leaf

    if($false -eq $FileExists)
    {
        Add-Content -Path "$BeginningScriptRoot\SuccessLogs\SCCM_Success_OUT.txt" -Value "--Timestamp(UTC)--`tMachineName`tMAC Address`tSCCM Collection" 
    }

    Add-Content -Path "$BeginningScriptRoot\SuccessLogs\SCCM_Success_OUT.txt" -Value "$($(Get-Date).ToUniversalTime())`t$DCName`t$MACAddress`t$Collection" 
}


$FailSkipReason = "blank"

debug "------SCCM Worker Initiated------"

debug "Working on $ComputerName with MAC Address of: $MAC and importing to $CollectionName."

debug "Proceeding to Load the SCCM PowerShell Module..."

Import-Module ConfigurationManager

debug "Verifying if the SCCM Powershell Module has been loaded..."

$ModuleCheck = Get-Module -Name ConfigurationManager

if($null -eq $ModuleCheck)
{
    debug "SCCM Powershell Module FAILED to be imported."

    $FailSkipReason = "SCCM Powershell Module FAILED to be imported."

    debug_FailSkip -DCName $ComputerName -Type "FAIL" -Reason $FailSkipReason

    $FailSkipReason = "$ComputerName will NOT be imported. Adding $ComputerName to the manual import CSV..."

    debug_FailCSV -DCName $ComputerName -MACAddress $MAC -DateTime $($(Get-Date -Format yyyy_MM_dd__HH_mm))

    debug "Script execution finished. Exiting..."

    exit 0
}

debug "SCCM Powershell Module loaded. Proceeding to change directory..."

cd $SCCMDir

$CurrentScriptRoot = Get-Location

debug "Current Script root: $CurrentScriptRoot"

if($SCCMDir -ne $CurrentScriptRoot)
{
    debug "Failed to change working directory to $SCCMDir"

    $FailSkipReason = "Failed to change working directory to $SCCMDir"

    debug_FailSkip -DCName $ComputerName -Type "FAIL" -Reason $FailSkipReason

    $FailSkipReason = "$ComputerName will NOT be imported. Adding $ComputerName to the manual import CSV..."

    debug_FailCSV -DCName $ComputerName -MACAddress $MAC -DateTime $($(Get-Date -Format yyyy_MM_dd__HH_mm))

    debug "Script execution finished. Exiting..."

    exit 0
}

debug "Working dir successfully changed to $SCCMDir"

debug "Proceeding to import $ComputerName..."

Import-CMComputerInformation -ComputerName $ComputerName -MacAddress $MAC -CollectionName $CollectionName -Confirm:$false

debug "Successfully imported $ComputerName. Reverting to the beginning directory..."

cd $BeginningScriptRoot

debug "Appending data to the success log..."

debug_Success -DCName $ComputerName -MACAddress $MAC -Collection $CollectionName

debug "Data appended. Script execution finished. Exiting..."

exit 0


