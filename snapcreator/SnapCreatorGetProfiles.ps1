$sc = 1;
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

$p = Get-ScProfile -OutVariable profiles

if (-not @($profiles).Count) {
	Write-Log "ERROR: at least one profile should be set in the SnapCreator configuration"
	$host.SetShouldExit(1) 
	exit
}

$profiles | Foreach-Object {
	$profile = $_
	$configstr = ''
	$c = Get-ScConfig -Profile  $profile.ProfileName -OutVariable configs
	$configs | Foreach-Object {
		$config = $_
		if ( $config.ConfigName -ne 'global') {
			if ($configstr) {
				$configstr+=' '
			}
			$configstr += $config.ConfigName
		}
	}
	Write-Log "`tProfile:$($profile.ProfileName) Configs:$($configstr)" $True
}
	