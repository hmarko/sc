Param (
    [Parameter(Mandatory=$True)]
    [String]$profile,
	
    [Parameter(Mandatory=$True)]
    [String]$config,
    
	[Parameter(Mandatory=$True)]
    [String]$cluster,
	
	[Parameter(Mandatory=$False)]
    [String]$clusteruser='admin',	

	[Parameter(Mandatory=$False)]
    [int]$MaxCloneAgeHours=24
	
)

$MaxCloneAgeHours

$sc = 1; $na = 1;
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$GlobalFile = $PSScriptRoot+'\SCGlobalConfig.ps1'
if (!([System.IO.File]::Exists($GlobalFile))) {
	Write-Host "ERROR: failed to locate required file $($PSScriptRoot)\GlobalConfig.ps1" 
	$host.SetShouldExit(1) 
	exit
}

. $GlobalFile

$clustercred = New-Object -typename System.Management.Automation.PSCredential -argumentlist $clusteruser, $secstr	
Write-Log "connecting to cluster $clustername"
$clusterconn = Connect-NcController -Name $cluster -Credential $clustercred -HTTPS

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
		exit 1	
	}
	$svm = $_.Storage 
	$vol = $_.Name
	
	Write-Log "listing clones for $($svm):$($vol):"

	if (-not $conn) {
		Write-Log "connecting to SVM $svm"
		$conn = Connect-NcController -Name $svm -Credential $cred 
		$allsvmvols = Get-NcVol
		$allsnaps = Get-NcSnapshot

		
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
				
				if ($volprofile  -eq $profile -and $volconfig -eq $config -and $volparentname -eq $vol -and $volsplit -eq 'N') {
					$prefix = $($currvol.Name).substring(0,$($currvol.Name).Length-$volparentname.Length)
					$snapinfo = $allsnaps | ? {$_.Vserver -eq $svm  -and $_.Volume -eq $volparentname -and $_.Name -eq $volsnap}
					$span = New-TimeSpan -Start ($snapinfo.Created) -End (Get-Date)
					if ($span.Hours -ge $MaxCloneAgeHours) {
											
						$aggrdetails = Get-NcAggr -Controller $clusterconn
						$maxavail = 0
						$destaggr = ''
						$aggrinfo = Get-NcVserverAggr -Controller $conn	
						if ($aggrinfo) {
							$aggrinfo | Foreach-Object {
								$curraggr = $_
								$curraggravailspace = ($aggrdetails| ?{$_.Name -eq $curraggr.AggregateName}).Available 
								if ($curraggravailspace -gt $maxavail) {
									$maxavail = $curraggravailspace
									$destaggr = $curraggr.AggregateName
								}
							}
						}
						Write-Log "clone:$($currvol) is based on a snapshot which been taken $($span.Hours)h ago, which is more than the allowed maximum of $($MaxCloneAgeHours)h"
						Write-Log "destination aggr for clone split is $destaggr"
						if ($currvol.Aggregate -eq $destaggr -or !$destaggr) {
							Write-Log "start split of $currvol from parent volume"
							$out = Start-NcVolCloneSplit -Controller $conn -Name  $currvol
						} else {
							Write-Log "start vol move of $currvol to destination aggregate $destaggr"
							Start-NcVolMove -Name $currvol -DestinationAggregate $destaggr -Vserver $svm -Controller $clusterconn
						}		
					}

				}
				
			}
		}
	}
}
