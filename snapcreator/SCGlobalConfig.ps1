#password file and default username
$passwordfile = 'pwd_do_not_delete'
$svmusername = 'vsadmin'

#password file and default username for snapcreator server 
$scpasswordfile = 'snapcreator_pwd_do_not_delete'
$scusername = 'admin'
$scserver = 'localhost'
$scport = '8443'
$sclogpath = "\\localhost\Logs\"

#Gate current Date and Time
$date = get-date -format `yyyyMMdd_hhmmsstt` 
$date = $date -replace " ","" #remove Spaces from $Date

#General write-log function
function Write-Log ($log,$notime){
	if ($log) {
		if (!$notime) {
			$log = "$(get-date) - $log" # <--- Prompt to screen.
		}
		Write-Host "$log"
	}
}


#validate password file exists and convert to PS-Credential object
if (!$sc -or $na) {
	$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
	$passwordfile = "$($PSScriptRoot)\$($passwordfile)"
	if (!(Test-Path $passwordfile)) {
		$svmpasswd  = $Env:SVMPASSWD
		if (!$svmusername -or !$svmpasswd) {
			[Console]::Error.WriteLine("Password file does not exist and SVMUSERNAME,SVMPASSWD was not provided in the SnapCreator command line!")
			exit 1
		}
		$secstr = New-Object -TypeName System.Security.SecureString
		$svmpasswd.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
		$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $svmusername, $secstr
		$cred.Password | ConvertFrom-SecureString | Set-Content $passwordfile
		if (!(Test-Path $passwordfile) ) {
			Write-Log "password did not saved !"
			exit 1
		} else {
			Write-Log "password were hashed and saved to $passwordfile"
		}
	}
	$secstr = Get-Content $passwordfile | ConvertTo-SecureString 
	$cred = New-Object -typename System.Management.Automation.PSCredential -argumentlist $svmusername, $secstr

	$module = Get-Module DataOnTap
	if (!$module) {
		Import-Module DataOnTap
	}
	try
	{
		$requiredVersion = New-Object System.Version(4.1)
		if ((Get-NaToolkitVersion).CompareTo($requiredVersion) -lt 0) { 
			throw
		}
	}
	catch [Exception]
	{
	   [Console]::Error.WriteLine("This script requires Data ONTAP PowerShell Toolkit 1.2 or higher")
	   exit 1
	}	
}

#configure snapcreator credentials in case the caller script requires access to snapcreator ($sc=1)

if ($sc) {
	$passwordfile = "$($PSScriptRoot)\$($scpasswordfile)"
	if (!(Test-Path $passwordfile)) {
		if (!$scusername -or !$scpasswd) {
			[Console]::Error.WriteLine("password file for snapcreator does not exist and scusername,scpasswd parameters were not provided!")
			exit 1
		}
		
		$secstr = New-Object -TypeName System.Security.SecureString
		$scpasswd.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
		$sccred = new-object -typename System.Management.Automation.PSCredential -argumentlist $scusername, $secstr
		$sccred.Password | ConvertFrom-SecureString | Set-Content $passwordfile
		
		if (!(Test-Path $passwordfile) ) {
			Write-Log "snapcreator password did not saved to the file !"
			exit 1
		} else {
			Write-Log "snapcreator password were hashed and saved to $passwordfile"
		}
	}	
	
	$secstrsc = Get-Content $passwordfile | ConvertTo-SecureString 
	$sccred = new-object -typename System.Management.Automation.PSCredential -argumentlist $scusername, $secstrsc
	
	$module = Get-Module SnapCreator
	if (!$module) {
		Import-Module SnapCreator
	}
	try
	{
		$module = Get-Module SnapCreator
		if (!$module) { 
			throw
		}
	}
	catch [Exception]
	{
	   [Console]::Error.WriteLine("this script requires Data SnapCreator PowerShell Toolkit 1.0 or higher")
	   exit 1
	}		
}

function exit_with_error ([string]$msg,[boolean]$forceclonedelete) {
	[Console]::Error.WriteLine($msg)
	if ($forceclonedelete -eq $True) {
		Write-Host "####################################  deleting clones created due to error ##############################";
		$volumes = $Env:VOLUMES		
		$volspersvm = $volumes.split(";")	
		$volspersvm | ForEach {
			$volpersvm = $_
			($svm, $vollist) = $volpersvm.split(":")
		
			$conn = Connect-NcController -name $svm -Credential $cred
			#if powershell toolkit used to run the job
			if ($currentvol) {
				$allvols = Get-NcVol -Controller $conn
				$vols = $vollist.split(",");
				$vols | ForEach {
					$vol = $_
					$clone = $flexcloneprefix+$vol
					if ($allvols | Where-Object {$_.Name -eq $clone}) {
						Write-Log "delete clone name:$clone"
						$out = Dismount-NcVol -Name $clone -Controller $conn
						$out = Set-NcVol -Name $clone -Offline -Controller $conn
						$out = Remove-NcVol -Name $clone -Confirm:$false -Controller $conn	
					}
				}
				$vollist = $currentvol
			}
			
			$vols = $vollist.split(",");
			$vols | ForEach {
				$vol = $_
				$clone = 'cl_'+$($Env:CONFIG_NAME)+'_'+$vol+'_'+$($Env:SNAP_TIME)
				Write-Log "delete clone name:$clone"
				$out = Dismount-NcVol -Name $clone -Controller $conn
				$out = Set-NcVol -Name $clone -Offline -Controller $conn
				$out = Remove-NcVol -Name $clone -Confirm:$false -Controller $conn			
				Write-Host $out 
			}
		}
	}
	exit 1
}


