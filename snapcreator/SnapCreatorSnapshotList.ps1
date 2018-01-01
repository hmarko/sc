Param (
    [Parameter(Mandatory=$True)]
    [String]$profile,
	
    [Parameter(Mandatory=$True)]
    [String]$config,

	[Parameter(Mandatory=$False)]
	[String]$snapshot,
	
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
	exit 1
}

$v = Get-ScVolume -ProfileName $profile -ConfigName $config -OutVariable vols

if (-not @($vols).Count) {
	Write-Log "ERROR: at least one volume should be set in the SnapCreator configuration"
	$host.SetShouldExit(1) 
	exit 1
}

$v = Get-ScVolume -ProfileName $profile -ConfigName $config -OutVariable vols
$vols | Foreach-Object {
	if ($svm -and $_.Storage -ne $svm) {
		Write-Log "ERROR: only one SVM is supported for cloning (in the configuration there is at least 2: $($svm) and $($_.Storage)"
		$host.SetShouldExit(1) 
		exit 1
	}
	
	$svm = $_.Storage 
	$vol = $_.Name	

	if (-not $conn) {
		Write-Log "connecting to SVM $svm"
		$conn = Connect-NcController -Name $svm -Credential $cred 
	}

	$volumedetails = Get-NcVol -Controller $conn -Name $vol 
	if (!$volumedetails) {
		Write-Log "ERROR:volume $($svm):$($vol) does not exist"
		$host.SetShouldExit(1) 
		exit 1
	}
	if (!$snapshot) {
		$snapshot = '*'
	}
	$snaps = Get-NcSnapshot -Volume $vol -SnapName $snapshot | Sort-Object -Descending:$true Created

	if (@($snaps).Count -lt 1) {
		Write-Log "ERROR: could not locate snapshots on $($svm):$($vol)"
		$host.SetShouldExit(1) 
		exit
	} else {
		Write-Log "snapshot list on $($svm):$($vol) available for cloning:"
		$snaps | ForEach-Object {
			$snap = $_
			Write-Log "`t$($snap.Name)  ($($snap.Created))" 1
		}
	}
}