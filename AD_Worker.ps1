##############################################################################
#
#	ActiveDirectory Worker Script, used  by the revised DC_CreationMain script
#	
#		Created by: Hyusein Hyuseinov / SERVER-RSRVPXT 2022.12.30
#
#       Requirements: Must be run under an engineer's Server-Bensl/Server-ATA account in order for the SCCM, AD and XD cmdlets to run
#
#       Function: Creates a Computer Object for the machine that's passed as an input parameter
#       
#       WARNING: A few minutes of time is necessary in order for the machine's data to be replicated across all AD Domain controlers
#       and in order for the machine to show up in ActiveDirectory.
#       This is why there is a Hardcoded 180 second Timeout after creating the AD object
#
##############################################################################

param (
[string]$ComputerName,
[string]$AD_OU,
[string]$AD_Server
)

#
##-------------------------Function for timeouts with a progress bar and counter-------------------------------------------------------------------
Function Sleep-Progress($Seconds) {
    $s = 0;
    Do {
        $p = [math]::Round(100 - (($Seconds - $s) / $seconds * 100));
        Write-Progress -Activity "Waiting..." -Status "$p% Complete:" -SecondsRemaining ($Seconds - $s) -PercentComplete $p;
        [System.Threading.Thread]::Sleep(1000)
        $s++;
    }
    While($s -lt $Seconds);
    
}

##-------------------------------------------------------------------------------------------------------------------------------------------------


function debug($message)
{
    write-host "$(Get-Date -Format yyyy-MM-dd--HH-mm-ss) $message" -BackgroundColor Black -ForegroundColor DarkYellow
    Add-Content -Path "$PSScriptRoot\VerboseLogs\AD_Worker.log" -Value "$(Get-Date -Format yyyy-MM-dd--HH-mm-ss) $message" 
}

function debug_FailSkip([string]$DCName,[string]$Type,[string]$Reason)
{
    $FileExists = Test-Path -Path "$PSScriptRoot\FailSkipLogs\AD_FailSkip.txt" -PathType Leaf

    if($false -eq $FileExists)
    {
        Add-Content -Path "$PSScriptRoot\FailSkipLogs\AD_FailSkip.txt" -Value "--Timestamp(UTC)--`tMachineName`tType`tReason" 
    }

    Add-Content -Path "$PSScriptRoot\FailSkipLogs\AD_FailSkip.txt" -Value "$($(Get-Date).ToUniversalTime())`t$DCName`t$Type`t$Reason" 
}

function debug_Success([string]$DCName,[string]$OU,[string]$ADPath)
{
    $FileExists = Test-Path -Path "$PSScriptRoot\SuccessLogs\AD_Success_OUT.txt" -PathType Leaf

    if($false -eq $FileExists)
    {
        Add-Content -Path "$PSScriptRoot\SuccessLogs\AD_Success_OUT.txt" -Value "--Timestamp(UTC)--`tMachineName`tActiveDirectory OU`tActiveDirectory Object Path" 
    }

    Add-Content -Path "$PSScriptRoot\SuccessLogs\AD_Success_OUT.txt" -Value "$($(Get-Date).ToUniversalTime())`t$DCName`t$OU`t$ADPath" 
}


$FailSkipReason = "blank"

debug "------AD Worker Initiated------"

debug "Working on $ComputerName in $AD_OU ."

debug "Checking if an object for $ComputerName already exists..."

try
{
    $AlreadyExistsCheck = Get-ADComputer -Identity $ComputerName -Server $AD_Server -Properties CanonicalName
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
{
    debug "No other objects for $ComputerName found. Continuing script execution..."

}

if($AlreadyExistsCheck)
{
    $AlreadyExistsLocation = $AlreadyExistsCheck.CanonicalName
    
    debug "An ActiveDirectory object for $ComputerName already exists at $AlreadyExistsLocation"

    $FailSkipReason = "An ActiveDirectory object for $ComputerName already exists at $AlreadyExistsLocation"

    debug_FailSkip -DCName $ComputerName -Type "FAIL" -Reason $FailSkipReason

    exit 0
}

debug "Creating the AD object for $ComputerName..."

try
{
    New-ADComputer -Name $ComputerName -SAMAccountName $ComputerName -Path $AD_OU
}
catch [Microsoft.ActiveDirectory.Management.Commands.NewADComputer]
{
    debug "AD Object Creation Failed."

    $FailSkipReason = "AD Object Creation using New-ADComputer FAILED."

    debug_FailSkip -DCName $ComputerName -Type "FAIL" -Reason $FailSkipReason

    exit 0
}

debug "AD Object Creation successful."

debug "Entering 60 secons of downtime..."

## New, Jan 11th, to reduce the disk of properly created AD objects not being detected immediately after due to inter-server delay between OMS and AD Controllers

Sleep-Progress -Seconds 60

debug "Preparing Data to append to the success output file..."

try
{
    $AD_object = Get-ADComputer -Identity $ComputerName -Server $AD_Server -Properties CanonicalName

    $CheckPath = $AD_object.CanonicalName
}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
{
    $CheckPath = "Fail"

    $FailSkipReason = "Failed to retrieve AD data for $ComputerName."

    debug_FailSkip -DCName $ComputerName -Type "FAIL" -Reason $FailSkipReason

    exit 0

}

debug_Success -DCName $ComputerName -OU $AD_OU -ADPath $CheckPath

debug "Data appended. Script Execution Finished. Exiting..."

exit 0