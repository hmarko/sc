Param (
    [Parameter(Mandatory=$True)]
    [String]$profile,
	
    [Parameter(Mandatory=$True)]
    [String]$config,

	[Parameter(Mandatory=$True)]
	[String]$snapshot,

	[Parameter(Mandatory=$True)]
	[String]$clonename,	

	[Parameter(Mandatory=$True)]
	[String]$nfshosts,	
	
	[Parameter(Mandatory=$True)]
	[String]$split,	

	[Parameter(Mandatory=$False)]
	[String]$junction,		
	
	[Parameter(Mandatory=$False)]
	[String]$scpasswd	
)

$sc = 1; $na = 1;
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$GlobalFile = $PSScriptRoot+'\SCGlobalConfig.ps1'
if (!([System.IO.File]::Exists($GlobalFile))) {
   Write-Host "ERROR: failed to locate required file $($PSScriptRoot)\GlobalConfig.ps1" 
   exit 1 
}
. $GlobalFile

Write-Log "connecting to snapcreator server $scserver"
$snapcreator = Connect-ScServer -Name $scserver -Port $scport -Credential $sccred
if (!$snapcreator) {
	Write-Log "ERROR:could not connect to snapcreator server"
	$host.SetShouldExit(1) 
	exit
}

if ($split.ToLower() -eq 'yes' -or $split.ToLower() -eq 'y') {
	$split = 'y'
}

$v = Get-ScVolume -ProfileName $profile -ConfigName $config -OutVariable vols

if (-not @($vols).Count) {
	Write-Log "ERROR: at least one volume should be set in the SnapCreator configuration"
	$host.SetShouldExit(1) 
	exit
}


$conn = $false
$vol = $false
$svm = $false
$snap = $false

$vols | Foreach-Object {
	
	if ($svm -and $_.Storage -ne $svm) {
		Write-Log "ERROR: only one SVM is supported for cloning (in the configuration there is at least 2: $($svm) and $($_.Storage)"
		$host.SetShouldExit(1) 
		exit		
	}
	
	$svm = $_.Storage 
	$vol = $_.Name

	if (-not $conn) {
		Write-Log "connecting to SVM $svm"
		$conn = Connect-NcController -Name $svm -Credential $cred 
	}
	
	$fullclonename = $clonename+$vol
	Write-Log "validating clone doesn't exists $($svm):$($fullclonename)"
	$volumedetails = Get-NcVol -Controller $conn -Name $fullclonename 
	if ($volumedetails) {
		Write-Log "ERROR:clone already exists $($svm):$($fullclonename)"
		$host.SetShouldExit(1) 
		exit
	}


	$snaps = Get-NcSnapshot -Volume $vol -SnapName $snapshot | Sort-Object -Descending:$true Created
	if (@($snaps).Count -lt 1) {
		Write-Log "ERROR: snapshot $snapshot does not exists on $($svm):$($vol)"
		$host.SetShouldExit(1) 
		exit
	} elseif (@($snaps).Count -gt 1) {
		$snap1 = $snaps[0].Name
		Write-Log "more than one snapshot ($($snaps.Count)) found on $($svm):$($vol) using $snap1 which is the newest one"
	} else {
		$snap1 = $snaps.Name
		Write-Log "snapshot $snap1 found on $($svm):$($vol)"
	}
	
	if ($snap -and $snap1 -ne $snap) {
		Write-Log "ERROR: snapshot $snap does not exists on $($svm):$($vol)"
		$host.SetShouldExit(1) 
		exit	
	}
	$snap = $snap1
	if (-not $snap) {
		Write-Log "ERROR:requested snapshot $snapshot name was not found on $($svm):$($vol)"
		$host.SetShouldExit(1) 
		exit	
	}
	$snapshot = $snap
}

$vols | Foreach-Object {
	
	$svm = $_.Storage 
	$vol = $_.Name
	Write-Log "invoking snapcreator clone for profile:$profile config:$config clone prefix:$clonename volume:$vol snapshot:$snapshot nfshosts:$nfshosts"
	$parameters = @{}
	$parameters.Add("CLONENAME",$clonename)
	$parameters.Add("NFSHOSTS",$nfshosts)
	if ($junction -and $junction -ne "*") {
		$parameters.Add("JUNCTION",$junction)
	}
	$parameters.Add("SPLIT",$split)

	$scwf = Start-ScWorkflow -Action APP_MOUNT -ProfileName $profile -ConfigName $config -Server $scconn -SnapName $snapshot -Parameters $parameters -volName $vol -PassThru 
	$exitcode = $?

	if ($exitcode -ne $True) {
		Write-Log "ERROR:snapcreator job failed, please check the logs"
		$host.SetShouldExit(1) 
		exit
	} else {
		Write-Log "waiting for snapcreator job ($($scwf.workflowId)) to complete"
		Wait-ScWorkflow -InputObject $scwf -Server $scconn
		$jobdetails = Get-ScWorkflowHistory -WorkflowId $scwf.workflowId 
		$errorlog = $sclogpath + $profile + '\' + $jobdetails.outLogFilename
		$debuglog = $sclogpath + $profile + '\' + $jobdetails.debugLogFilename
		if ($jobdetails.jobStatus -eq 0) {
			Write-Log "clone job completed successfully"
		} else {
			Write-Log "ERROR: job failed with the following details:"
			if (Test-Path $errorlog) {
				Get-Content $errorlog
			}
			Write-Log "detailed debug log is available on sc server ($scserver):$debuglog"
			$host.SetShouldExit(1) 
			exit
		}
		Write-Log "detailed debug log is available on: $debuglog (on $scserver)"
	}
}

Write-Log "all clones created successfully "
$host.SetShouldExit(0)
exit 