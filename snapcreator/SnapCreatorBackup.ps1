Param (
    [Parameter(Mandatory=$True)]
    [String]$profile,
	
    [Parameter(Mandatory=$True)]
    [String]$config,
	
	[Parameter(Mandatory=$True)]
	[String]$policy,

	[Parameter(Mandatory=$False)]
	[Boolean]$offline,

	[Parameter(Mandatory=$False)]
	[String]$scpasswd	
)

$sc = 1;
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$GlobalFile = $PSScriptRoot+'\SCGlobalConfig.ps1'
if (!([System.IO.File]::Exists($GlobalFile))) {
	Write-Host "ERROR: failed to locate required file $($PSScriptRoot)\GlobalConfig.ps1" 
	$host.SetShouldExit(1) 
	exit 1
}
. $GlobalFile

Write-Log "connecting to snapcreator server $scserver"
$snapcreator = Connect-ScServer -Name $scserver -Port $scport -Credential $sccred
if (!$snapcreator) {
	Write-Log "ERROR:could not connect to snapcreator server"
	$host.SetShouldExit(1) 
	exit 1
}

Write-Log "invoking snapcreator backup for profile:$profile config:$config policy:$policy"
$scwf = Start-ScWorkflow -Action backup -ProfileName $profile -ConfigName $config -Policy $policy -Server $scconn -PassThru -ErrorVariable err
if ($err) {
	Write-Log "ERROR:snapcreator job failed, please check the logs"
	$host.SetShouldExit(1) 
	exit 1
} else {
	Write-Log "waiting for snapcreator job ($($scwf.workflowId)) to complete"
	Wait-ScWorkflow -InputObject $scwf -Server $scconn
	$jobdetails = Get-ScWorkflowHistory -WorkflowId $scwf.workflowId 
	$errorlog = $sclogpath + $profile + '\' + $jobdetails.outLogFilename
	$debuglog = $sclogpath + $profile + '\' + $jobdetails.debugLogFilename
	if ($jobdetails.jobStatus -eq 0) {
		Write-Log "backup job completed successfully - timestamp $($jobdetails.timestamp)"
	} else {
		Write-Log "ERROR: job failed with the following details:"
		if (Test-Path $errorlog) {
			Get-Content $errorlog
		}
		Write-Log "detailed debug log is available on sc server ($scserver):$debuglog"
		$host.SetShouldExit(1) 
		exit 1
	}
	Write-Log "detailed debug log is available on: $debuglog (on $scserver)"
	$host.SetShouldExit(0)
	exit 
}

