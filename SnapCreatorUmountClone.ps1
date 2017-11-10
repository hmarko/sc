Param (
    [Parameter(Mandatory=$True)]
    [String]$profile,
	
    [Parameter(Mandatory=$True)]
    [String]$config,

	[Parameter(Mandatory=$True)]
	[String]$clonename,	
	
	[Parameter(Mandatory=$False)]
	[String]$scpasswd,

	[Parameter(Mandatory=$False)]
	[String]$svmpasswd	
)

#include Snapcreator connectivity and netapp svm connectivity
$sc = 1; $na = 1;
$Env:SVMPASSWD = $svmpasswd

$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$GlobalFile = $PSScriptRoot+'\SCGlobalConfig.ps1'
if (!([System.IO.File]::Exists($GlobalFile))) {
   Write-Host "ERROR: failed to locate required file $($PSScriptRoot)\SCGlobalConfig.ps1" 
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
	
	$clonedetails = Get-NcVol -Controller $conn -Name $fullclonename
	if (!$clonedetails) {
		Write-Log "ERROR:could not locate clone volume $($svm):$($fullclonename)"
		$host.SetShouldExit(1) 
		exit
	}

	$volcomment = $clonedetails.VolumeIdAttributes.Comment
	$comments = $volcomment.Split(',')
	$comments | ForEach {
		$comment = $_
		$param,$value = $comment.Split(':') 
		if ($param -eq 'SNAP') {
			$snapshot = $value
		}
		if ($param -eq 'SCCLONENAME') {
			$origclonename = $value
		}	
	}
	if (!$snapshot -or !$origclonename) {
		Write-Log "ERROR:could not find required information on $($svm):$($fullclonename) comment field"
		$host.SetShouldExit(1) 
		exit
	}

	$clonesnapshot = $snapshot
	if ($clonedetails.VolumeCloneAttributes.VolumeCloneParentAttributes) {
		$clonesnapshot = $clonedetails.VolumeCloneAttributes.VolumeCloneParentAttributes.SnapshotName
	} else {
		$conesnapshot = ''
	}

	if ($clonesnapshot -ne $snapshot -and  $clonesnapshot) {
		Write-Log "Warning: original base snapshot:$($snapshot) been renamed to $clonesnapshot, the snapshot will probably wont be deleted"
		$snapshot = $clonesnapshot
	} elseif ($clonesnapshot -eq $snapshot) {
		Write-Log "clone:$($fullclonename) is based on snapshot $snapshot"
	} else {
		Write-Log "Warning: volume:$($fullclonename) is not a flexclone and probebly been splited from its parent volume"	
	}

	if ($clonedetails.VolumeCloneAttributes.CloneChildCount -gt 0) {
		Write-Log "ERROR: clone:$($fullclonename) cannot be destroyed since it is the father of $($clonedetails.VolumeCloneAttributes.CloneChildCount) clones"
		$host.SetShouldExit(1) 
		exit	
	}

	Write-Log "invoking snapcreator clone un-mount for profile:$profile config:$config snapshot:$snapshot snapcreator clone:$fullclonename original clone:$origclonename "
	$parameters = @{}
	$parameters.Add("CLONENAME",$fullclonename)
	$parameters.Add("CLONEPREFIXNAME",$clonename)

	$scwf = Start-ScWorkflow -Action APP_UNMOUNT -ProfileName $profile -ConfigName $config -Server $scconn -SnapName $snapshot -CloneName $origclonename -parameters $parameters -PassThru 
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
			Write-Log "clone un-mount job completed successfully"
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

$host.SetShouldExit(0)
exit 