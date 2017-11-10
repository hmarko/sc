$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$GlobalFile = $PSScriptRoot+'\SCGlobalConfig.ps1'
if (!([System.IO.File]::Exists($GlobalFile))) {
   Write-Host "ERROR: Failed to locate required file $($PSScriptRoot)\GlobalConfig.ps1" 
   exit 1 
}
. $GlobalFile

$volumes = $Env:VOLUMES
$flexcloneprefix = $Env:CLONENAME
$usersnap = $Env:USER_SNAP_NAME
$nfshosts = $Env:NFSHOSTS
$junction = $Env:JUNCTION
$currentvol = $Env:USER_VOLUME_NAME

$split = $Env:SPLIT

#get the hosting clusert name and username from golbal config
$cmode_cluster_users = $env:CMODE_CLUSTER_USERS
$clustername = ((($cmode_cluster_users.Split("/"))[0]).Split(":"))[0]
$clusteruser = ((($cmode_cluster_users.Split("/"))[0]).Split(":"))[1]
$clustercred = New-Object -typename System.Management.Automation.PSCredential -argumentlist $clusteruser, $secstr

if (!$volumes) {
	exit_with_error "Error: environment variable VOLUMES was not found, this script must run as part of snapcreator job"
}
if (!$flexcloneprefix) {
	exit_with_error "Error: environment variable CLONENAME (custom) was not found, this script must run as part of snapcreator job" $true
}
if (!$nfshosts) {
	exit_with_error "Error: environment variable NFSHOSTS (custom) was not found, this script must run as part of snapcreator job" $true
}
if (!$Env:SNAP_TIME) {
	exit_with_error "Error: environment variable SNAP_TIME was not found, this script must run as part of snapcreator job" $true
}
if (!$Env:CONFIG_NAME) {
	exit_with_error "Error: environment variable CONFIG_NAME was not found, this script must run as part of snapcreator job" $true
}

Write-Log " " 

$exportmaps = @{}

$volspersvm = $volumes.split(";")
$volspersvm | ForEach {
	$volpersvm = $_
	($svm, $vollist) = $volpersvm.split(":")
	
	#if powershell toolkit used to run the job
	if ($currentvol) {
		$vollist = $currentvol
	}
	$vols = $vollist.split(",")
	$conn = Connect-NcController -name $svm -HTTPS -Credential $cred
	$vols | ForEach {
		$vol = $_
		
		$clone = 'cl_'+$($Env:CONFIG_NAME)+'_'+$vol+'_'+$($Env:SNAP_TIME)
		$exportpolicy = 'cl_'+$flexcloneprefix+$vol
		$junctionpath = '/'+$flexcloneprefix+$vol;
		if ($junction) {
			$junctionpath = $junction+'/'+$flexcloneprefix;
		}		
		$vol = Get-NcVol -Controller $conn | Where-Object {$_.JunctionPath -eq $junctionpath}
		if ($vol) {
			exit_with_error "Error: volume junction path $junctionpath is already used by another volume" $true
		}
		$exp = Get-NcExportPolicy -Controller $conn -Name $exportpolicy
		if ($exp) {
			$exportmaps.Add($svm+$exportpolicy,1)
		}
	}
}

$volspersvm = $volumes.split(";")
$volspersvm | ForEach {
	$volpersvm = $_
	($svm, $vollist) = $volpersvm.split(":")
	
	#if powershell toolkit used to run the job
	if ($currentvol) {
		$vollist = $currentvol
	}
	
	$vols = $vollist.split(",")
	$conn = Connect-NcController -name $svm -HTTPS -Credential $cred
	$vols | ForEach {
		$vol = $_
		$clone = 'cl_'+$($Env:CONFIG_NAME)+'_'+$vol+'_'+$($Env:SNAP_TIME)
		$exportpolicy = 'cl_'+$flexcloneprefix+$vol
		$junctionpath = '/'+$flexcloneprefix+$vol
		$flexclonename = $flexcloneprefix+$vol

		if ($junction) {
			$junctionpath = $junction+'/'+$flexcloneprefix;
		}

		Write-Log "dismounting $clone from the default name space mount"
		$out = Dismount-NcVol -Name $clone -Controller $conn
		Write-Log "remounting $clone on $junctionpath" 
		$out = Mount-NcVol -Name $clone -Controller $conn -JunctionPath $junctionpath

		if (!$exportmaps.ContainsKey($svm+$exportpolicy)) {
			Write-Log "creating new export-policy $exportpolicy"
			$out = New-NcExportPolicy -Name $exportpolicy -Controller $conn 
		}

		$nfshosts.Split(":") | ForEach {
			$nfshost = $_
			Write-Log "adding nfs access to host:$($nfshost) on export policy:$($exportpolicy)"
			$rule = New-NcExportRule -Policy $exportpolicy -ClientMatch $nfshost -ReadOnlySecurityFlavor sys -ReadWriteSecurityFlavor sys -SuperUserSecurityFlavor sys
		}

		$comment = 'SNAP:'+$usersnap+',PARENTVOL:'+$vol+',SCCLONENAME:'+$clone+',PROFILE:'+$Env:PROFILE_NAME+',CONFIG:'+$Env:CONFIG_NAME;
		$q = Get-NcVol -Template
		Initialize-NcObjectProperty $q VolumeIdAttributes
		$q.VolumeIdAttributes.Name = $clone
		$voltemplate = Get-NcVol -Template
		Initialize-NcObjectProperty -Object $voltemplate -Name VolumeExportAttributes
		Initialize-NcObjectProperty -Object $voltemplate -Name VolumeIdAttributes
		$voltemplate.VolumeExportAttributes.Policy = $exportpolicy
		$voltemplate.VolumeIdAttributes.Comment = $comment

		Write-Log "setting $clone export-policy as:$($exportpolicy) comment as:$($comment)"
		$updatevol = Update-NcVol -Controller $conn -Query $q -Attributes $voltemplate

		Write-Log "rename clone from:$($clone) to:$($flexclonename)"
		$vol = Rename-NcVol -Name $clone -NewName $flexclonename -Controller $conn	

		$basesnapshot = $flexclonename+'_base'
		Write-Log "creating base snapshot on the clone:$basesnapshot"
		$snap = New-NcSnapshot -Volume  $flexclonename -Snapshot $basesnapshot -Controller $conn	
		
		if ($split -eq 'y') {
			$clusterconn = Connect-NcController -Name  $clustername -Credential $clustercred
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
			Write-Log "destination aggr for clone split is $destaggr"
			$vol = Get-NcVol -name $flexclonename -Controller $conn 
			if ($vol.Aggregate -eq $destaggr -or !$destaggr) {
				Write-Log "start split of $flexclonename from parent volume"
				$out = Start-NcVolCloneSplit -Controller $conn -Name  $flexclonename
			} else {
				Write-Log "start vol move of $flexclonename to destination aggregate $destaggr"
				Start-NcVolMove -Name $flexclonename -DestinationAggregate $destaggr -Vserver $svm -Controller $clusterconn
			}
		}
	}
}
	
exit 0
