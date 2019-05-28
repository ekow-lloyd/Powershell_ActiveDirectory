<#
.SYNOPSIS
Create a new or modify an existing CloudCom user in the CloudCom AD.

.DESCRIPTION
Create a new or modify an existing CloudCom user in the CloudCom AD.

Two parameter sets ("Init" and "Scheduled") exist.  This is to make it easier to call the script when it's initially called (when you want to read CSV files) or when it's called as part of a scheduled task.

Only paramaters that are members of a parameter set can be called in an single instance.

This is used so the script can read the CSV file(s) (init) and process the request based on the startdate value in the read CSV file.

If the startdate of the user is within 48 hours of the scrpit run then it'll automatically add the user to AD at the time of script run.
Otherwise, if the startdate of the user is beyond 48 hours of the script run, the script will *automatically* create a scheduled tasks to add the user within 48 hours of the CSV startdate value.

.PARAMETER isScheduled

Type: SWITCH 

Mandatory: Yes (Init)

Set: Init, Scheduled

Tells the script whether or not to run in a scheduled task mode ($true) or 'input from csv' mode ($false)

SWITCH paramaters do not need values associated.  In our case, running Update-CloudComAD.ps1 -isScheduled is the same as saying Update-CloudComAD.ps1 -isScheduled $true 

.PARAMETER pFirstName

Type: String
Mandatory: Yes
Set: Scheduled

The firstname of the user.  Supplied as a parameter and value to the script when run from a scheduled task.

.PARAMETER pLastName
Type: String
Mandatory: Yes
Set: Scheduled

The last name of the user.  Supplied as a parameter and value to the scirpt when run from a scheduled task.

.PARAMETER pSAM
Type: String
Mandatory: Yes
Set: Scheduled

The SamAccountName of the user.  Supplied as a parameter and value to the scirpt when run from a scheduled task.

.PARAMETER pUserName

Type: String
Mandatory: Yes
Set: Scheduled

The username of the user.  Supplied as a parameter and value to the scirpt when run from a scheduled task.

.PARAMETER pOU
Type: String
Mandatory: Yes
Set: Scheduled

The OU the user will belong to.  Supplied as a parameter and value to the scirpt when run from a scheduled task.

.PARAMETER pStartDate
Type: String
Mandatory: Yes
Set: Scheduled

The Start Date of the user.  Supplied as a parameter and value to the scirpt when run from a scheduled task.

.PARAMETER pEndDate
Type: String
Mandatory: Yes
Set: Scheduled

The End Date of the user.  Supplied as a parameter and value to the scirpt when run from a scheduled task.

.PARAMETER pCompany
Type: String
Mandatory: Yes
Set: Scheduled

The Company the user belongs to. Supplied as a parameter and value to the scirpt when run from a scheduled task.

.INPUTS
When run in "Init" set the path of the CSV file(s) are required.

.OUTPUTS
Outputs a transaction log to the user's Desktop ($env:username\desktop\).

.EXAMPLE
.\New-CloudComUser.ps1
#>
#Requires -RunAsAdministrator

Param(
    [CmdletBinding(DefaultParameterSetName='Init')]
    # Whether or not this is a scheduled task...
    [Parameter(Mandatory=$true,ParameterSetName="Scheduled")] #include $isScheduled in both (scheudled and init) parameter sets.
    [Parameter(Mandatory=$false,ParameterSetName="Init")]
    [switch]
    $isScheduled,
    # Let's define all required parameters when creating a user when it's a scheduled task.  Scheduled tasks require additional parameters because the initial CSV that was loaded will no longer be used.  Instead, all values from the CSV will be stored as arguments (parameters) to the script within the scheduled task.
    # First Name
    [Parameter(Mandatory=$true,ParameterSetName="Scheduled")]
    [string]
    $pFirstName,
    # Last Name
    [Parameter(Mandatory=$true,ParameterSetName="Scheduled")]
    [string]
    $pLastName,
    # SAM
    [Parameter(Mandatory=$true,ParameterSetName="Scheduled")]
    [string]
    $pSAM,
    # end date
    [Parameter(Mandatory=$true,ParameterSetName="Scheduled")]
    [string]
    $pEndDate,
    # company
    [Parameter(Mandatory=$true,ParameterSetName="Scheduled")]
    [string]
    $pCompany,
    # copyuser name
    [Parameter(Mandatory=$true,ParameterSetName="Scheduled")]
    [string]
    $pCopyUser,
    # UPN
    [Parameter(Mandatory=$true,ParameterSetName="Scheduled")]
    [string]
    $pUPN,
    # Full Name
    [Parameter(Mandatory=$true,ParameterSetName="Scheduled")]
    [string]
    $pFullName,
    # Email Address
    [Parameter(Mandatory=$true,ParameterSetName="Scheduled")]
    [string]
    $pEmail
)
Write-Debug "Current parameter set: $($PSCmdlet.ParameterSetName)"

$DebugPreference = "Continue" #comment this line out when you don't want to enable the debugging output.
#$VerbosePreference = "Continue"
#$ErrorActionPreference = "Stop"

$LogFolder = "$env:userprofile\desktop\logs" #log file location.
$TranscriptLog = -join($LogFolder,"\transcript.log")
Start-Transcript -Path $TranscriptLog -Force
$csvPath = "C:\testfc\" #changeme - Location where the website is delivering the CVS files.  Only a directory path is needed, do not enter a full path to a specific CSV file.
$ScriptFullName = -join($PSScriptRoot,"\$($MyInvocation.MyCommand.Name)") #Dynamically create this script's path and name for use later in scheduled task creation.
<# Uncomment this block to get your $failedusers and $successUsers log writing functionality back.
$a = 1;
$b = 1;
$failedUsers = @()
$successUsers = @()
#>


function Format-CsvValue {
    [CmdletBinding()]
    param (
        #Sets whether or not we want to format the provided string into 'title' (aka Proper) case when using named values.
        #When isTitleCase = $true the function will take the input string ($sValue) and format it to proper(title) case and will also remove leading and trailing whitespaces.  Example; "JoHN SmITH" will return "John Smith" or "   JaNE " will return "Jane" (removed whitespaces and set to title case).
        [Parameter(Mandatory = $false)]
        [bool]
        $isTitleCase = $false,
        #The string value that's passed into the function to properly format.
        #Example: Format-CsvValue -isTitleCase $true -sValue $mvar
        #Example: To only remove whitespace from a string-> Format-CsvValue -sValue $myvar
        [Parameter(Mandatory = $true)]
        [string]
        $sValue
    
    ) #=>Params
  
    begin {
        #no variables or intitializations to declare.
    } #=>begin
  
    process {
        if ($isTitleCase) {
            #isTitleCase is set to true so let's format it...
            $rValue = $((Get-Culture).TextInfo.ToTitleCase($sValue.ToLower())).Trim() #trim leading/trailing whitespace AND convert to title case string format.
        }
        else {
            #only whitespace trim is required, process that request.
            $rValue = $sValue.Trim() #Remove leading/trailing whitespace.
        }#=>if/isTitleCase
    }#=>process
  
    end {
        #return the value through the function.
        $rValue
    }
} #=>Format-CsvValue



Function Write-CustomEventLog {
    [CmdletBinding()]
    param(
        # What message to write to the event viewer.
        [Parameter(Mandatory=$true)]
        [string]
        $message,
        # Type
        [Parameter(Mandatory=$true)]
        [ValidateSet('Information','Warning','Error')]
        [string]
        $entryType
    )

    Begin {
        $eventSourceExists = [System.Diagnostics.EventLog]::SourceExists("Update-CloudComAD")
        if(-not($eventSourceExists)) {
            try {
                New-EventLog -LogName Application -Source 'Update-CloudComAD'
            }
            catch {
                Write-Debug 'Unable to create new application source.'
            }
        }#=>if not $eventSourceExists
    }#=>Begin

    Process {
        switch ($entryType) {
            "Information" { [int]$EventID = 1000 }
            "Warning" { [int]$EventID = 2000 }
            "Error" { [int]$EventID = 3000}
        }
        Write-EventLog -LogName Application -Source 'Update-CloudComAD' -EntryType $entryType -EventId $EventID -Message $message
    }
}

Import-Module ActiveDirectory

if (!($isScheduled)) {
    Write-Debug "This is not a scheduled task so we can safely assume this is an initial read of a CSV file. Looking for all CSV files in $($csvPath) that are NOT readonly."
    #since we are anticipating *dynamically* named CSV files let's find all CSV files we have yet to process.
    $csvFiles = Get-ChildItem -Path $csvPath -Filter "*.csv" -Attributes !readonly+!directory
    $csvCount = ($csvFiles | Measure-Object).Count
    Write-Debug "Found $($csvCount) CSV files in $($csvPath) to process: `n`n `$csvFiles: $($csvFiles)"
    if ($csvFiles) {
        Write-Debug "Found unprocessed CSV files..."
        foreach ($csvFile in $csvFiles) {
            Write-Debug "Processing CSV file $($csvFile.FullName)"
            try {
                $Users = Import-CSV $csvFile.FullName
            }
            catch {
                
                
                #We need to check if the csvFiles count is greater than 1. If it is, we can move to the next file. If it's not, we need to throw an error and exit this script.
                if ($csvCount -gt '1') {
                    Write-CustomEventLog -message "Unable to import CSV file: $($csvFile.FullName). This is a fatal error for this csv file. Continuing to next file. Error message is: `n`n $($Error[0].Exception.Message)" -entryType "Warning"
                    Write-Debug "Unable to import our CSV file: $($csvFile.FullName). This is a fatal error for this CSV file.  Continuing to next file. Error message is: $Error[0].Exception.Message"
                    Continue
                } else {
                    Write-CustomEventLog -message "Unable to import CSV file: $($csvFile.FullName). This is a fatal error for this csv file and this script. Exiting script. Error message is: `n`n $($Error[0].Exception.Message)" -entryType "Error"
                    Write-Debug "Unable to import our CSV file: $($csvFile.FullName). This is a fatal error for this CSV file and this script. Exiting script. Error message is: $Error[0].Exception.Message"
                    Throw $csvFile.FullName
                }
                

            }#=> try $Users
        
            #imported our CSV file properly.  Let's process the file for new users...
            ForEach ($User in $Users){
                #debugging purposes...
                Write-Debug "First Name (CSV): $($User.Firstname)"
                Write-Debug "Last Name (CSV): $($User.Lastname)"
                Write-Debug "StartDate (CSV): $($User.startdate)"
                Write-Debug "End Date (CSV): $($User.enddate)"
                Write-Debug "Company (CSV): $($User.Company)"
                #=>debugging purposes.
        
                #Let's properly format all the values in this *ROW* of the CSV. Trim() where necessary and change to Title Case where necessary - also create a new variable so we can use it later when creating the user in AD using the New-ADuser cmdlet.
                $FirstName = Format-CsvValue -isTitleCase $true -sValue $User.FirstName #trim and title case
                $LastName = Format-CsvValue -isTitleCase $true -sValue $User.LastName #trim and title case.
                $Email = Format-CsvValue -sValue $User.Email #trim only.
                $StartDate = Format-CsvValue -sValue $User.startdate #trim only.
                $EndDate = Format-CsvValue -sValue $User.enddate #trim only.
                $Company = Format-CsvValue -sValue $User.company #trim only since company names are rather specific on how they're spelled out.
                if ($csvFile.Name -like "NU*") {
                    #This csvFile that we're working on seems to be a New User request as defined by the "NU" in the CSV file name so we add more details.
                    $copyUser = -join(($User.copyuser).Trim()," ", ($User.copyuserLN).Trim()) #We need the fullname of the user we're copying from.
                }
                #=> End of CSV values.

                #Let's build other necessary variables that we want to use as parameters for the New-ADuser cmdlet out of the information provided by the CSV file or other sources...
                $FullName = -join($($FirstName)," ",$($LastName)) #join $Firstname and $Lastname and a space to get FullName
                $SAM = (-join(($FirstName).Substring(0,1),$LastName)).ToLower() #this assumes that your SAM naming convention is firstinitialLASTNAME and makes everything lowercase.
                $Username = (-join($FirstName,".",$LastName)).ToLower() #this assumes that your usernames have a naming convention of firstname.lastname and makes everything lowercase.
                $DNSroot = "@$((Get-ADDomain).dnsroot)"
                $UPN = -join($Username, $dnsroot)
                $Password = (ConvertTo-SecureString -AsPlainText 'Cloudcom.1' -Force)
                $oStartDate = [datetime]::ParseExact(($User.StartDate).Trim(), "dd/MM/yyyy", $null) #This converts the CSV "startdate" field from a string to a datetime object so we can use it for comparison.
                $oEndDate = [datetime]::ParseExact(($User.EndDate).Trim(), "dd/MM/yyyy", $null) #This conerts to CSV 'EndDate' field from a string to a datetime object which is required for the New-AdUser cmdlet 'AccountExpirationDate' parameter.

                #debugging purposes...
                Write-Debug "`$FirstName:  $($FirstName)"
                Write-Debug "`$LastName: $($LastName)"
                Write-Debug "`$Email: $($Email)"
                Write-Debug "`$StartDate: $($StartDate)"
                Write-Debug "`$EndDate: $($EndDate)"
                Write-Debug "`$copyUser: $($copyUser)"
                Write-Debug "`$FullName: $($FullName)"
                Write-Debug "`$SAM: $($SAM)"
                Write-Debug "`$Username: $($Username)"
                Write-Debug "`$DNSRoot: $($DNSroot)"
                Write-Debug "`$UPN: $($UPN)"
                Write-Debug "`$oStartDate: $($oStartDate)"
                #=>debugging puproses

                #Now, let's check the user's startdate as listed in the CSV file.  If startdate is within 48 hours of today's (Get-Date) date we'll create the user directly in AD.  Otherwise, we'll schedule a task to create the user at a later date.
                #First, we need to check if this is a New User request, 'startdate' only applies to new users...
                if ($csvFile.name -like "NU*") {
                    if ( $(get-date) -ge ($oStartDate).AddHours(-48) ) {
                        Write-Debug "$(Get-Date) (current script run time/date) is greater than or equal to 48 hours minus employee start date: $($oStartDate).AddHours(-48)) so we are creating the user immediately."

                        #Checking to see if a user already exists in AD with the same email address...
                        if (Get-AdUser -Filter {mail -eq $Email}) {
                            Write-Debug "A user with email address $($email) already exists in AD.  We cannot add this user."
                            #$failedUsers+= -join($Fullname,",",$SAM,",","A user with email address $($email) already exists in AD. Skipping this user.")
                            Write-CustomEventLog -message "When attempting to create user $($FullName) [SAM: $($SAM)] we found another user that exists in AD using the same email address of $($email). We have to skip this user." -entryType "Warning"
                            Continue #go to next csv record.
                        }#=if get-aduser
                        else {
                            Write-Debug "No existing user in AD with email address $($email) so we can create our user."

                            $newUserAD = @{
                                'SamAccountName'            = $SAM
                                'UserPrincipalName'         = $UPN
                                'Name'                      = $FullName
                                'Company'                   = $Company
                                'EmailAddress'              = $Email
                                'GivenName'                 = $FirstName
                                'Surname'                   = $LastName
                                'AccountPassword'           = $Password
                                'AccountExpirationDate'     = $oEndDate
                                'ChangePasswordAtLogon'     = $true
                                'Enabled'                   = $true
                                'PasswordNeverExpires'      = $false
                            }#=>$newUserAD

                            Write-Debug "Attempting to get properties of our user to copy from..."
                            $templateUser = Get-ADUser -filter {name -eq $copyUser} -Properties MemberOf
                            if (-not($templateUser)) {
                                Write-Debug "We were unable to find the template user $($copyUser) so we have to skip this new AD user and go to the next row in the CSV file."
                                #$failedUsers+= -join($Fullname,",",$SAM,",","We were unable to find the template user $($copyUser) so we have to skip creating new user $($FullName) and go to the next row in the CSV file.")
                                Write-CustomEventLog -message "We were unable to find the template user $($copyUser) when attempting to create new user $($FullName) with SAM $($SAM).  Skipping the creation of this user." -entryType "Warning"
                                continue #move to next CSV row.
                            } else {
                                #Let's get the OU that our template user belongs to and apply that to our new user...
                                $OU = ($templateUser.DistinguishedName).Substring(($templateUser.DistinguishedName).IndexOf(",")+1)
                                Write-Debug "Our OU for new user $($FullName) is $($OU) from copy of our template user $($copyUser) with OU of $($templateUser.DistinguishedName)"
                                #Let's update our $newUserAD properties with this OU...
                                $newUserAD['Path'] = $OU
                            }#=>if/else $templateuser

                            Write-Debug "Adding user $($FullName) to AD with the following paramaters; `n $($newUserAD | Out-String)"
                            try {
                                $oNewADUser = New-ADUser @newUserAD                                
                            }
                            catch {
                                Write-Debug "Unable to create new user $($FullName) to AD.  Error message `n`n $Error"
                                if(-not($oNewADUser)) {
                                    Write-Debug "Something went wrong with adding our new $($FullName) user to AD. `n`n $error"
                                    #$failedUsers+= -join($Fullname,",",$SAM,",","We were unable to add our new user $($FullName) to AD. `n`n $error `n`n Moving to next user...")
                                    Write-CustomEventLog -message "We were unable to add our new user $($FullName) to AD. Skipping this user.  Full error details below; `n`n $($Error)." -entryType "Warning"
                                    continue
                                }
                            }
                            #Adding user went well..
                            Write-Debug "We created our new user $($FullName) in AD."
                            #$successUsers += -join($FullName,",",$SAM,",","Successfully created new AD user.")
                            Write-CustomEventLog -message "Successfully created new AD User $($FullName).  AD Details included below; `n`n $($newuserAD | Out-String)" -entryType "Information"
                        }#=>else get-aduser


                    } else {
                        Write-Debug "$(Get-Date) (current script run time/date) is NOT greater than or equal to 48 hours minus employee start date: $($oStartDate).AddHours(-48)) so we are scheduling a task to create the user later."
                        <#
                        $taskNewUserParams= @{
                            'isScheduled'   = $true
                            'pSAM'          = $SAM
                            'pUPN'          = $UPN
                            'pFullName'     = $FullName
                            'pCompany'      = $Company
                            'pEmail'        = $Email
                            'pFirstName'    = $FirstName
                            'pLastName'     = $LastName
                            'pEndDate'      = $EndDate
                            'pCopyUser'     = $copyUser
                        }#=>$newUserAD
                        #>
                        $taskaction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -windowStyle Hidden -Command `"& $($ScriptFullName) -isScheduled -pSAM '$($SAM)' -pUPN '$($UPN)' -pFullName '$($FullName)' -pCompany '$($Company)' -pEmail '$($Email)' -pFirstName '$($FirstName)' -pLastName '$($LastName)' -pEndDate '$($EndDate)' -pCopyUser '$($copyuser)'`""
                        $tasktrigger = New-ScheduledTaskTrigger -Once -At ($oStartDate).AddHours(-48)
                        try {
                            $taskregister = Register-ScheduledTask -Action $taskaction -Trigger $tasktrigger -TaskName "Add AD User - $($FullName)" -Description "Automatic creation of AD User $($FullName) 48 hours prior to the user's startdate." -ErrorAction 'Stop'
                        }
                        catch {
                            Write-Warning $_
                        }
                        $findTask = Get-ScheduledTask -TaskName "Add AD User - $($FullName)"
                        if(-not($findTask)) {
                            Write-Debug "Our scheduled task | Add AD User - $($FullName) | was NOT created."
                            Write-CustomEventLog -message "We were unable to create a scheduled task to create user $($FullName) - $($SAM) on $($StartDate)." -entryType "Warning"
                        } else {
                            Write-Debug "Our scheduled task | Add AD User - $($FullName) | was created."
                            Write-CustomEventLog -message "Created a scheduled task to create AD User $($FullName) $($SAM) on $(($oStartDate).AddHours(-48))" -entryType "Information"
                        } #=>if/else not $findTask
                    }#=>if/get-date -ge startdate-48
                }#=>if $csvFile.name NU*
                elseif ($csvFile.name -like "CU*") {
                    Write-Debug "This is a 'change user' request so we are making these changes immediately. We will NOT schedule these types of requests and will ignore CSV 'startdate' field."
                    $changeUserAD = @{
                        'SamAccountName'            = $SAM
                        'UserPrincipalName'         = $UPN
                        'Company'                   = $Company
                        'EmailAddress'              = $Email
                        'GivenName'                 = $FirstName
                        'Surname'                   = $LastName
                        'AccountExpirationDate'     = $oEndDate
                    }#=>$changeUserAD
                    try {
                        $oChangeADUser = Get-ADUser -Filter {mail -eq $Email} -ErrorAction 'Stop'
                        Set-ADUser $oChangeADUser @changeUserAD -ErrorAction 'Stop'
                    }
                    catch {
                        Write-Debug "Unable to change user $($FullName) in AD. Error is `n`n $Error"
                        #$failedUsers+= -join($Fullname,",",$SAM,",","Unable to change user $($Fullname) in AD.")
                        Write-CustomEventLog -message "Unable to modify AD User $($Fullname) with SAM $($SAM) in AD.  Full error details below; `n`n $($Error)" -entryType "Warning"
                    }
                    if(-not($oChangeADUser)) {
                        Write-Debug "Unable to change user $($FullName) in AD."
                        #$failedUsers+= -join($Fullname,",",$SAM,",","Unable to change user $($Fullname) in AD.")
                        Write-CustomEventLog -message "Unable to modify AD User $($Fullname) with SAM $($SAM) in AD.  Full error details below; `n`n $($oChangeUser.Error)" -entryType "Warning"
                    } else {
                        #change user request was fine...
                        Write-Debug "Successfully changed AD user $($FullName)"
                        #$successUsers += -join($FullName,",",$SAM,",","Successfully changed AD user $($FullName)")
                        Write-CustomEventLog -message "Successfully updated AD User Name: $($FullName) - SAM: $($SAM) in AD. Details are below. `n`n $($changeUserAD | Out-String)" -entryType "Information"
                    }
                    
                }#=> elseif $csvFile.name -like CU*
            }#=>ForEach $user !$isScheduled
            Write-Debug "Renaming our current csv file $($csvFile.FullName) and addding a .done extension. Also making the file read-only."
            Rename-Item -Path $csvFile.FullName -NewName "$($csvFile.FullName).done" -Force
            Set-ItemProperty -Path "$($csvFile.FullName).done" -name IsReadOnly -Value $true
        }#=>foreach $csvFile
    }#=>if $csvFiles
    else {
        Write-Debug "No CSV files found in $($csvPath) that require processing.  Nothing to do this round."
    }#=>else $csvFiles
}#=>if !$isScheduled
else {
    Write-Debug "This is a scheduled task to create a new user.  Let's build our request and create the user."
    #Checking to see if a user already exists in AD with the same email address...
    if (Get-AdUser -Filter {mail -eq $pEmail}) {
        Write-Debug "A user with email address $($pEmail) already exists in AD.  We cannot add this user."
        #$failedUsers+= -join($pFullname,",",$pSAM,",","A user with email address $($pEmail) already exists in AD. Skipping this user.")
        Write-CustomEventLog -message "A user with email address $($pEmail) already exists in AD.  Skipping the creation of user $($pFullName) with SAM $($pSAM)" -entryType "Warning"
    }#=if get-aduser
    else {
        Write-Debug "No existing user in AD with email address $($pEmail) so we can create our user."
        Write-Debug "Attempting to get properties of our user to copy from..."
        $templateUser = Get-ADUser -filter {name -eq $pCopyUser} -Properties MemberOf
        if (-not($templateUser)) {
            Write-Debug "We were unable to find the template user $($pCopyUser) so we cannot create teh new user $($pFullName)"
            #$failedUsers+= -join($pFullname,",",$pSAM,",","We were unable to find the template user $($pCopyUser) so we cannot create new user $($pFullName)")
            Write-CustomEventLog -message "We are unable to find the template user $($pCopyUser) in AD.  Unable to create new user $($pFullName) due to this error." -entryType "Warning"
        } else {
            $Password = (ConvertTo-SecureString -AsPlainText 'Cloudcom.1' -Force)
            $oEndDate = [datetime]::ParseExact(($pEndDate).Trim(), "dd/MM/yyyy", $null) #This conerts to CSV 'EndDate' field from a string to a datetime object which is required for the New-AdUser cmdlet 'AccountExpirationDate' parameter.
            $newUserAD = @{
                'SamAccountName'            = $pSAM
                'UserPrincipalName'         = $pUPN
                'Name'                      = $pFullName
                'Company'                   = $pCompany
                'EmailAddress'              = $pEmail
                'GivenName'                 = $pFirstName
                'Surname'                   = $pLastName
                'AccountPassword'           = $Password
                'AccountExpirationDate'     = $oEndDate
                'ChangePasswordAtLogon'     = $true
                'Enabled'                   = $true
                'PasswordNeverExpires'      = $false
            }#=>$newUserAD

            #Let's get the OU that our template user belongs to and apply that to our new user...
            $OU = ($templateUser.DistinguishedName).Substring(($templateUser.DistinguishedName).IndexOf(",")+1)
            Write-Debug "Our OU for new user $($pFullName) is $($OU) from copy of our template user $($pCopyUser) with OU of $($templateUser.DistinguishedName)"

            #Let's update our $newUserAD properties with this OU...
            $newUserAD['Path'] = $OU

            Write-Debug "Adding user $($pFullName) to AD with the following paramaters; `n $($newUserAD | Out-String)"
            $oNewADUser = New-ADUser @newUserAD
            if(-not($oNewADUser)) {
                Write-Debug "Something went wrong with adding our new $($pFullName) user to AD."
                #$failedUsers+= -join($pFullname,",",$pSAM,",","We were unable to add our new user $($pFullName) to AD. Moving to next user..")
                Write-CustomEventLog -message "We were unable to add our new user $($pFullName) to AD using file $($csvFile.Fullname).  Moving to next user." -entryType "Warning"
                continue
            } else {
                Write-Debug "We created our new user $($pFullName) in AD."
                #$successUsers += -join($pFullName,",",$pSAM,",","Successfully created new AD user.")
                Write-CustomEventLog -message "Created new user $($pFullName) in AD.  Values are below; `n $($newUserAD | Out-String)" -entrypType "Information"
            }#=>if/else $oNewADUser
        }#=>if/else $templateuser
    }#=>else get-ADUser
}#=>if isScheduled
#$failedUsers | ForEach-Object { "$($b).) $($_)"; $b++ } | out-file -FilePath  $LogFolder\FailedUsers.log -Append -Force -Verbose #write failed users.
#$successUsers | ForEach-Object { "$($a).) $($_)"; $a++ } | out-file -FilePath  $LogFolder\successUsers.log -Append -Force -Verbose #write success users.
Stop-Transcript
$transcriptContent = Get-Content -Path $TranscriptLog -RAW
Write-CustomEventLog -message "Finished running script. Full transaction log details are below; `n`n` $($transcriptContent)" -entryType "Information"

Move-Item -Path C:\testfc\*.done -Destination C:\logfc