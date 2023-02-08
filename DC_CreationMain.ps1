##############################################################################
#
#	Script to automatically create Dedicated Clients across all layers:
#   VMWare, XenDesktop, ActiveDirectory and SCCM
#	
#		Created by: Hyusein Hyuseinov / SERVER-RSRVPXT 2022.12.30
#
#       Requirements: Must be run under an engineer's Server-Bensl/Server-ATA account in order for the AD and XD cmdlets to run
#
#       During a run of the script, please put ONLY 1 SCCM Collection per input/script run, if the Input.csv has multiple different collections for each machine,
#       They will not be automatically updated and therefore the machines might not start executing the BFS immediately on PowerOn
#
#       The script can be run from any OMS, since all necessary input data is provided in the Input.csv (Delivery groups, Vcenters, etc)
#
#       Multiple different Vcenters, XND Controllers, ResourcePools, Datastores and XND Controllers can be specified in the Input.csv for each machine
#
#       If the Keyword 'Auto' is given in the Input.csv for Datastore, then the Datastore with the most free space that's available to the Resource Pool (CPM, TPM) will be used.
#
#       In order to minize strain on the SCCM Infrastructure, updating of memberships for the ALL SYSTEMS and Input Collections are performed
#       only AFTER the creation and importing of machines in VMWare, SCCM, XD, AD.
#
#       Expected the Machines to show up in SCCM at best 10 minutes after an update of the ALL Systems collection is triggered.
#
#       That's why there is a hardcoded variable: '$PreVerificationSCCMTimeoutSeconds' = 900 seconds (15 minutes).
#       Verifying whether or not a machine was successfully imported in SCCM will be performed only after that amount of time
#       and only on VM's that were successfully created by the script (taking input from the VMWare_Success_OUT.txt file in the SuccessLogs Folder)
#
#       All folders for logs are created automatically -> If you're copying the script to a new OMS, copy only the following files:
#
#       1) DC_CreationMain.ps1
#       2) AD_Worker.ps1
#       3) SCCM_worker.ps1
#       4) SCCM_verifier.ps1
#       5) XD_Worker.ps1
#       6) The Input.csv
#
#       Avoid using OMS-s that everybody uses (AALOMSFRK004, AALOMSPAR004),
#       since the script will hang during the 15 minutes timeout after updating ALL Systems, because of high utilization of server Resources (CPU/RAM).
#
#
##############################################################################

function Connect_E1_Vcenters {

$passwordE1 = ConvertTo-SecureString "6NnIC%k*M@VW07h7125n" -AsPlainText -Force 


$E1_VMWareCred = New-Object System.Management.Automation.PSCredential ("WWG00M\e1avcp36",$passwordE1)

Connect-VIServer -Server aalvcsfrk102.dcm.allianz -Credential $E1_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcsfrk103.dcm.allianz -Credential $E1_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcsfrk202.dcm.allianz -Credential $E1_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcsfrk203.dcm.allianz -Credential $E1_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcsfrk302.dcm.allianz -Credential $E1_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcsfrk303.dcm.allianz -Credential $E1_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcsfrk402.dcm.allianz -Credential $E1_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcsfrk403.dcm.allianz -Credential $E1_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcsfrk802.dcm.allianz -Credential $E1_VMWareCred -ErrorAction SilentlyContinue

}

function Connect_E2_Vcenters{

$passwordE2 = ConvertTo-SecureString "7uQqN6%%990@7%eD9+4G" -AsPlainText -Force


$E2_VMWareCred = New-Object System.Management.Automation.PSCredential ("WWG00M\e2avcp36",$passwordE2)

Connect-VIServer -Server aalvcspar102.dcm.allianz -Credential $E2_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcspar103.dcm.allianz -Credential $E2_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcspar202.dcm.allianz -Credential $E2_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcspar203.dcm.allianz -Credential $E2_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcspar302.dcm.allianz -Credential $E2_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcspar303.dcm.allianz -Credential $E2_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcspar402.dcm.allianz -Credential $E2_VMWareCred -ErrorAction SilentlyContinue
Connect-VIServer -Server aalvcspar403.dcm.allianz -Credential $E2_VMWareCred -ErrorAction SilentlyContinue

}

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
    write-host "$(Get-Date -Format yyyy-MM-dd--HH-mm-ss) $message" -BackgroundColor Black -ForegroundColor Green
    Add-Content -Path "$PSScriptRoot\VerboseLogs\Main_Vmware.log" -Value "$(Get-Date -Format yyyy-MM-dd--HH-mm-ss) $message" 
}

function debug_FailSkip([string]$DCName,[string]$Type,[string]$Reason)
{
    $FileExists = Test-Path -Path "$PSScriptRoot\FailSkipLogs\VMWare_FailSkip.txt" -PathType Leaf

    if($false -eq $FileExists)
    {
        Add-Content -Path "$PSScriptRoot\FailSkipLogs\VMWare_FailSkip.txt" -Value "--Timestamp(UTC)--`tMachineName`tType`tReason" 
    }

    Add-Content -Path "$PSScriptRoot\FailSkipLogs\VMWare_FailSkip.txt" -Value "$($(Get-Date).ToUniversalTime())`t$DCName`t$Type`t$Reason" 
}

function debug_Success([string]$DCName,[string]$VCenterr,[string]$MAC,[string]$VLAN)
{
    $FileExists = Test-Path -Path "$PSScriptRoot\SuccessLogs\VMWare_Success_OUT.txt" -PathType Leaf

    if($false -eq $FileExists)
    {
        Add-Content -Path "$PSScriptRoot\SuccessLogs\VMWare_Success_OUT.txt" -Value "--Timestamp(UTC)--`tMachineName`tVCenter`tMAC`tVLAN" 
    }

    Add-Content -Path "$PSScriptRoot\SuccessLogs\VMWare_Success_OUT.txt" -Value "$($(Get-Date).ToUniversalTime())`t$DCName`t$VCenterr`t$MAC`t$VLAN" 
}

Connect_E1_Vcenters
Connect_E2_Vcenters

$BeginningScriptRoot = $PSScriptRoot

$SkipFailReason = "blank"

$VerboseLogsFolderExists = Test-path -Path "$PSScriptRoot\VerboseLogs" -PathType Container

if($false -eq $VerboseLogsFolderExists)
{
    New-Item -Path "$PSScriptRoot" -Name "VerboseLogs" -ItemType Directory -Force -Confirm:$false -ErrorAction Stop | Out-Null
}

$SuccessLogsFolderExists = Test-path -Path "$PSScriptRoot\SuccessLogs" -PathType Container

if($false -eq $SuccessLogsFolderExists)
{
    New-Item -Path "$PSScriptRoot" -Name "SuccessLogs" -ItemType Directory -Force -Confirm:$false -ErrorAction Stop | Out-Null
}

$FailSkiLogsFolderExists = Test-path -Path "$PSScriptRoot\FailSkipLogs" -PathType Container

if($false -eq $FailSkiLogsFolderExists)
{
    New-Item -Path "$PSScriptRoot" -Name "FailSkipLogs" -ItemType Directory -Force -Confirm:$false -ErrorAction Stop | Out-Null
}



$inputData = Import-Csv -Path "$PSScriptRoot\Input.csv"

$inputSCCM_Collection = $inputData[0].SCCMCollection

$InputSCCMDrive = $inputData[0].SCCMDrive

$PreVerificationSCCMTimeoutSeconds = 1200

Write-Host "Input Data Loaded."

debug "Input SCCM Collection: $inputSCCM_Collection, Input SCCM Drive: $InputSCCMDrive"

debug "SCCM Pre-verifiction of import Timetout in seconds (hardcoded): $PreVerificationSCCMTimeoutSeconds"

debug "------VM Creation script by Señor José Garcia initiated------"

debug "-----Beginning Phase 1: VM Creation-----"

foreach($entry in $inputData)
{
    $current_Vcenter = $entry.VCenter
    $current_VM_ResourcePool = $entry.VMResourcePool
    $current_VM_Datastore = $entry.VMDatastore
    $current_VM_Folder = $entry.VMFolder
    $current_VM_TemplateName = $entry.VMTemplate
    $current_VM_VLAN = $entry.VLAN
    $current_VMDomain = $entry.Domain
    $current_VMName = $entry.VMName    

    debug "Working on: $current_VMName"

    debug "Checking if $current_VMName is already taken..."

    $VMObj_Check = Get-VM -Name $current_VMName -ErrorAction SilentlyContinue

    if($null -ne $VMObj_Check)
    {
        $VMObj_FoundLocation = $VMObj_Check.Uid
        
        debug "$current_VMName already exists at: $VMObj_FoundLocation"

        debug "Skipping to the next entry..."

        $SkipFailReason = "VM Already Exists at $VMObj_FoundLocation"

        debug_FailSkip -DCName $current_VMName -Type "Skip" -Reason $SkipFailReason

        continue

    }
    else
    {
        debug "No other VM-s with the same name are found. Proceeding to create $current_VMName at $current_Vcenter"

        debug "Checking DataStore assignment mode..."

        if("Auto" -eq $current_VM_Datastore)
        {
            debug "DataStore assignment mode is AUTOMATIC. The datastore with most free space, available to the Resource Pool will be used."

            $available_Datastores = Get-Datastore -RelatedObject $current_VM_ResourcePool -Server $current_Vcenter | Sort-Object -Property FreeSpaceGB -Descending

            if($null -eq $available_Datastores)
            {
                debug "No Datastores available to Resource Pool $current_VM_ResourcePool. Skipping to the next VM..."

                $SkipFailReason = "No Datastores available to $current_VM_ResourcePool"

                debug_FailSkip -DCName $current_VMName -Type "Skip" -Reason $SkipFailReason

                continue
            }

            $DatastoreWithMostFreeSpace = $available_Datastores[0]

            $DatastoreWithMostFreeSpace_Name = $DatastoreWithMostFreeSpace.Name

            $DatastoreWithMostFreeSpace_FreeSpace = $DatastoreWithMostFreeSpace.FreeSpaceGB

            debug "Datastore with the most free space available is:"

            debug "$DatastoreWithMostFreeSpace_Name with $DatastoreWithMostFreeSpace_FreeSpace GB Free. "

            debug "Setting it as the Datastore to use..."

            $current_VM_Datastore = $DatastoreWithMostFreeSpace_Name
        }
        else
        {
            debug "Datastore Assignment Mode is PREDEFINED. Checking if $current_VM_Datastore is available to $current_VM_ResourcePool..."

            $Check = Get-Datastore -Name $current_VM_Datastore -RelatedObject $current_VM_ResourcePool -Server $current_Vcenter

            if($null -eq $Check)
            {
                debug "$current_VM_Datastore is not available to $current_VM_ResourcePool. Skipping to the next VM..."

                $SkipFailReason = "Input Datastore $current_VM_Datastore not available to $current_VM_ResourcePool"

                debug_FailSkip -DCName $current_VMName -Type "Skip" -Reason $SkipFailReason

                continue
            }

            debug "Check Passed."
        }


        $CreationResult = New-VM -Name $current_VMName -Template $current_VM_TemplateName -Location $current_VM_Folder -ResourcePool $current_VM_ResourcePool -Datastore $current_VM_Datastore -Server $current_Vcenter

        if($null -eq $CreationResult)
        {
            debug "VM Creation for $current_VMName FAILED. Skipping to the next VM..."

            $SkipFailReason = "Failed to create VM"

            debug_FailSkip -DCName $current_VMName -Type "FAIL" -Reason $SkipFailReason
        }

        debug "VM Created. Checking if the Network Adapter from the Template matches the wished VLAN from the input file and is set to Connect at Power On..."

        $VLAN_Object = Get-VM -Name $current_VMName -Server $current_Vcenter | Get-NetworkAdapter

        $VLAN_ObjectNWName = $VLAN_Object.NetworkName

        $VLAN_ObjectStartState = $VLAN_Object.ConnectionState.StartConnected

        if(($current_VM_VLAN -eq $VLAN_ObjectNWName) -and ($true -eq $VLAN_ObjectStartState))
        {
            debug "VLAN matches and is set to connect automatically at PowerOn"
        }
        else
        {
            debug "VLAN Mismatch, resetting..."

            $OldVLAN = Get-NetworkAdapter -VM $CreationResult -Server $current_Vcenter

            Remove-NetworkAdapter -NetworkAdapter $OldVLAN -Confirm:$false

            New-NetworkAdapter -VM $CreationResult -NetworkName $current_VM_VLAN -StartConnected:$true -Confirm:$false -Server $current_Vcenter | Out-Null

            debug "Checking if the setting was successful..."

            $VLAN_Object = Get-VM -Name $current_VMName -Server $current_Vcenter | Get-NetworkAdapter

            $VLAN_ObjectNWName = $VLAN_Object.NetworkName

            $VLAN_ObjectStartState = $VLAN_Object.ConnectionState.StartConnected

            if(($current_VM_VLAN -eq $VLAN_ObjectNWName) -and ($true -eq $VLAN_ObjectStartState))
            {
                debug "VLAN $current_VM_VLAN setup for $current_VMName successful."
            }
            else
            {
                debug "VLAN $current_VM_VLAN setup for $current_VMName FAILED. Will append data to the success out file with the current VLAN..."

                $SkipFailReason = "Error setting up $current_VM_VLAN(differs from the Template default for $current_VM_TemplateName : $VLAN_ObjectNWName) for $current_VMName"

                debug_FailSkip -DCName $current_VMName -Type "FAIL" -Reason $SkipFailReason
            }
        }

        debug "VM Creation finished. Appending to the VMWare Success log..."

        $VM_Mac = Get-VM -Name $current_VMName -Server $current_Vcenter | Get-NetworkAdapter

        debug_Success -DCName $current_VMName -VCenterr $current_Vcenter -MAC $($VM_Mac.MacAddress) -VLAN $($VM_Mac.NetworkName)
    }
}

debug "Clearing the Input Data..."

$inputData = $null

debug "-----Phase 1: VM Creation complete-----"

debug "-----Beginning Phase 2: SCCM Importing-----"

debug "Acquiring the list of successfully created VM's from $PSScriptRoot\SuccessLogs\VMWare_Success_OUT.txt ..."

$VMWare_Successes = (Get-Content -Path "$PSScriptRoot\SuccessLogs\VMWare_Success_OUT.txt")

debug "List acquired."

foreach($line in $VMWare_Successes)
{
    if($line -like "*X???-D?????*")
    {
        $InputTextArray = $line.Split("`t")
        
        $Current_VMName = $InputTextArray[1]

        $Current_VCenter = $InputTextArray[2]

        $Current_VM_MAC = $InputTextArray[3]

        & "$PSScriptRoot\SCCM_Worker.ps1" -ComputerName $Current_VMName -MAC $Current_VM_MAC -CollectionName $inputSCCM_Collection -SCCMDir $InputSCCMDrive -ErrorAction Ignore
    }
}

debug "Clearing the VMWare Successes array..."

$VMWare_Successes = $null

debug "-----Phase 2: SCCM Importing complete-----"

debug "-----Entering Intermission A: Updating collection Memberships-----"

debug "Memberships of the collections 'All systems' and '$inputSCCM_Collection' will be updated,"

debug "so that the imported machines can show up while the other phases are running..."

Import-Module ConfigurationManager

debug "Verifying if the SCCM Powershell Module has been loaded..."

$ModuleCheck = Get-Module -Name ConfigurationManager

if($null -eq $ModuleCheck)
{
    debug "SCCM Powershell Module FAILED to be imported."

    debug "Script will exit prematurely..."

    exit 1
}

debug "SCCM Powershell Module loaded. Proceeding to change directory..."

cd $InputSCCMDrive

$CurrentScriptRoot = Get-Location

debug "Current Script root: $CurrentScriptRoot"

if($InputSCCMDrive -ne $CurrentScriptRoot)
{
    debug "Failed to change working directory to $SCCMDir"

    debug "Script will exit prematurely..."

    exit 1
}

debug "Working dir successfully changed to $InputSCCMDrive"

debug "Proceeding to update ALL SYSTEMS..."

Invoke-CMCollectionUpdate -Name "All Systems" -Confirm:$false

debug "ALL SYSTEMS collection updated."

debug "Marking timestamp..."

$IntermissionA_Timestamp = Get-Date

debug "Proceeding to update $inputSCCM_Collection..."

Invoke-CMCollectionUpdate -Name $inputSCCM_Collection -Confirm:$false

debug "$inputSCCM_Collection updated."

debug "Reverting back to the original script root of $BeginningScriptRoot"

cd $BeginningScriptRoot

debug "-----Intermission A finished-----"

debug "-----Beginning Phase 3: ActiveDirectory Objects creation-----"

debug "Acquiring the list of successfully imported machines from $PSScriptRoot\SuccessLogs\SCCM_Success_OUT.txt ..."

$SCCM_ImportSuccesses = (Get-Content -Path "$PSScriptRoot\SuccessLogs\SCCM_Success_OUT.txt" )

debug "Reaquiring the Input.csv..."

$inputData = Import-Csv -Path "$PSScriptRoot\Input.csv"

foreach($line in $SCCM_ImportSuccesses)
{
    if($line -like "*X???-D?????*")
    {
        $InputTextArray = $line.Split("`t")

        $Current_VMName = $InputTextArray[1]

        $current_AD_OU = "Placeholder"

        $current_AD_Server = "Placeholder"

        :AD_Variables_Capture foreach($entry in $inputData)
        {
            $entry_Name = $entry.VMName

            if($entry_Name -eq $Current_VMName)
            {
                $current_AD_OU = $entry.AD_OU
                
                $current_AD_Server = $entry.AD_Server

                break AD_Variables_Capture
            }
        }
        
        & "$PSScriptRoot\AD_Worker.ps1" -ComputerName $current_VMName -AD_OU $current_AD_OU -AD_Server $current_AD_Server -ErrorAction Ignore
    }
}

debug "Entering 180 seconds of downtime to ensure that even the last created AD Machine doesn't fail when importing to XD..."

Sleep-Progress -Seconds 180

debug "Clearing the SCCM Import successes array..."

$SCCM_ImportSuccesses = $null

debug "-----Phase 3: ActiveDirectory Objects creation complete-----"

debug "-----Beginning Phase 4: XenDesktop Importing-----"

debug "Acquiring the list of successfully created AD objects from $PSScriptRoot\SuccessLogs\AD_Success_OUT.txt ..."

$AD_CreationSuccesses = (Get-Content -Path "$PSScriptRoot\SuccessLogs\AD_Success_OUT.txt" )

foreach($line in $AD_CreationSuccesses)
{
    if($line -like "*X???-D?????*")
    {
        $InputTextArray = $line.Split("`t")

        $Current_VMName = $InputTextArray[1]

        $current_VCenter = "Blank"

        :VCenter_Capture foreach($entry in $inputData)
        {
            $entry_Name = $entry.VMName

            if($entry_Name -eq $Current_VMName)
            {
                $current_VCenter = $entry.VCenter

                break VCenter_Capture
            }
        }

        $current_VMDomain = "Placeholder"

        $current_XD_Controller = "Placeholder"

        $current_XD_Hypervisor = "Placeholder"

        $current_XD_CatalogName = "Placeholder"

        $current_XD_DeliveryGroup = "Placeholder"

        debug "Aquiring VM UUID for $Current_VMName..."

        $VMData = Get-VM -Name $Current_VMName -Server $current_VCenter

        $VMUUID = $VMData.ExtensionData.Config.Uuid

        if(($VMUUID -is [array]))
        {
            $ArraySize = $VMUUID.Length

            $VMUUID_ToKeep = $VMUUID[$($ArraySize - 1)]

            $VMUUID = $null

            $VMUUID = $VMUUID_ToKeep
        }

        :XD_Variables_Capture foreach($entry in $inputData)
        {
            $entry_Name = $entry.VMName

            if($entry_Name -eq $Current_VMName)
            {
                $current_VMDomain = $entry.Domain

                $current_XD_Controller = $entry.XDController

                $current_XD_Hypervisor = $entry.XDHypervisor

                $current_XD_CatalogName = $entry.XDCatalog

                $current_XD_DeliveryGroup = $entry.XDDeliveryGroup

                break XD_Variables_Capture
            }
        }

        & "$PSScriptRoot\XD_Worker.ps1" -ComputerName $current_VMName -ComputerDomain $current_VMDomain -XD_Controller $current_XD_Controller -XD_Hypervisor $current_XD_Hypervisor -XD_CatalogName $current_XD_CatalogName -XD_DeliveryGroup $current_XD_DeliveryGroup -MachineUUID $VMUUID
    }
}

debug "-----Phase 4: XenDesktop Importing complete-----"

debug "-----Entering Intermission B: Time Validation-----"

debug "Getting current timestamp..."

$IntermissionB_Timestamp = Get-Date

debug "Comparing elapsed time..."

$TimeElapsed = New-TimeSpan -Start $IntermissionA_Timestamp -End $IntermissionB_Timestamp

$TimeElapsedSeconds = $TimeElapsed.TotalSeconds

if($PreVerificationSCCMTimeoutSeconds -ge $TimeElapsedSeconds)
{
    $RemainingTimeout = $PreVerificationSCCMTimeoutSeconds - $TimeElapsedSeconds
    
    debug "Time elapsed since Intermission A is $TimeElapsedSeconds seconds and is less than the hardcoded $PreVerificationSCCMTimeoutSeconds seconds"

    debug "An additional $RemainingTimeout seconds of downtime will be incurred to ensure that all properly imported machines in SCCM are detected accurately"

    Sleep-Progress -Seconds $RemainingTimeout
}

debug "Enough time has elapsed to proceed to Phase 5."

debug "-----Intermission B has finished-----"

debug "-----Beginning Phase 5: SCCM Import verification-----"

debug "Acquiring the list of successfully imported XD machines from $PSScriptRoot\SuccessLogs\VMWare_Success_OUT.txt ..."

$VerificationInput = (Get-Content -Path "$PSScriptRoot\SuccessLogs\VMWare_Success_OUT.txt")

foreach($line in $VerificationInput)
{
    if($line -like "*X???-D?????*")
    {
        $InputTextArray = $line.Split("`t")

        $current_VMName = $InputTextArray[1]

        $ExtractedMAC = $InputTextArray[3]

        debug "Working on $ExtractedMachineName..."

        debug "Launching the SCCM Verifier Script..."

        & "$PSScriptRoot\SCCM_Verifier.ps1" -ComputerName $current_VMName -MAC $ExtractedMAC -CollectionName $inputSCCM_Collection -SCCMDir $InputSCCMDrive -ErrorAction Ignore
    }
}

debug "-----Phase 5: SCCM Import verification finished-----"

debug "Script run complete. Exiting..."

exit 0

