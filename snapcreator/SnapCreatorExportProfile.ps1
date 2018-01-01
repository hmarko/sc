Param (
    [Parameter(Mandatory=$True)]
    [String]$profile,
	
    [Parameter(Mandatory=$True)]
    [String]$config
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

Write-Log "exporting configuration file  for profile:$profile config:$config policy:$policy"
Export-ScConfig -ProfileName $profile -ConfigName $config 
if ($err) {
	Write-Log "ERROR:snapcreator job failed, please check the logs"
	$host.SetShouldExit(1) 
	exit 1
} else {
	$host.SetShouldExit(0)
	exit 
}

