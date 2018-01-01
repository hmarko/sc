Param (
    [Parameter(Mandatory=$True)]
    [String]$profile,
	
    [Parameter(Mandatory=$True)]
    [String]$config
)

$sc = 1;  $na=1;
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

$v = Get-ScVolume -ProfileName $profile -ConfigName $config -OutVariable vols

if (-not @($vols).Count) {
	Write-Log "ERROR: at least one volume should be set in the SnapCreator configuration"
	$host.SetShouldExit(1) 
	exit 1
}

$conn = $false
$vol = $false
$svm = $false
$snap = $false

$vols | Foreach-Object {
	
	if ($svm -and $_.Storage -ne $svm) {
		Write-Log "ERROR: only one SVM is supported for cloning (in the configuration there is at least 2: $($svm) and $($_.Storage)"
		$host.SetShouldExit(1) 
		exit 1	
	}
	$svm = $_.Storage 
	$vol = $_.Name
	
	Write-Log "listing clones for $($svm):$($vol):"

	if (-not $conn) {
		Write-Log "connecting to SVM $svm"
		$conn = Connect-NcController -Name $svm -Credential $cred 
		$allsvmvols = Get-NcVol
	}
	
	$allsvmvols | Foreach-Object {
		$currvol = $_

		$volprofile = ''
		$volconfig = '' 
		$volsnap = ''
		$volparentname = ''
		$volsplit = 'Y'
		if ($currvol.VolumeCloneAttributes.VolumeCloneParentAttributes) {
			$volsplit = 'N'
		}		
		$volcomment = $currvol.VolumeIdAttributes.Comment

		if ($volcomment) {
			if ($volcomment.Contains('CONFIG:')) {
				$comments = $volcomment.Split(',')
				$comments | ForEach {
					$comment = $_
					$param,$value = $comment.Split(':') 
					if ($param -eq 'SNAP') {
						$volsnap = $value
					}
					if ($param -eq 'PARENTVOL') {
						$volparentname = $value
					}
					if ($param -eq 'CONFIG') {
						$volconfig = $value
					}	
					if ($param -eq 'PROFILE') {
						$volprofile = $value
					}			
				}
				
				if ($volprofile  -eq $profile -and $volconfig -eq $config -and $volparentname -eq $vol) {
					$prefix = $($currvol.Name).substring(0,$($currvol.Name).Length-$volparentname.Length)
					Write-Log "`tClone Prefix:$($prefix) Clone Volume:$($currvol.Name) Base Snapshot:$volsnap Split:$($volsplit)" 1
				}
				
			}
		}
	}
}