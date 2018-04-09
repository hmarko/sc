$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$GlobalFile = $PSScriptRoot+'\SCGlobalConfig.ps1'
if (!([System.IO.File]::Exists($GlobalFile))) {
   Write-Host "ERROR: Failed to locate required file $($PSScriptRoot)\GlobalConfig.ps1" 
   exit 1 
}
. $GlobalFile

$volumes = $Env:VOLUMES
$flexclonename = $Env:CLONENAME
$usersnap = $Env:USER_SNAP_NAME
$user_clone_name = $Env:USER_CLONE_NAME
$clone_prefix = $Env:CLONEPREFIXNAME

#get the hosting clusert name and username from golbal config
$cmode_cluster_users = $env:CMODE_CLUSTER_USERS
$clustername = ((($cmode_cluster_users.Split("/"))[0]).Split(":"))[0]
$clusteruser = ((($cmode_cluster_users.Split("/"))[0]).Split(":"))[1]
$clustercred = New-Object -typename System.Management.Automation.PSCredential -argumentlist $clusteruser, $secstr

if (!$volumes) {
	exit_with_error "Error: environment variable VOLUMES was not found, this script must run as part of snapcreator job"
}

if (!$Env:SNAP_TIME) {
	exit_with_error "Error: environment variable SNAP_TIME was not found, this script must run as part of snapcreator job" 
}
if (!$Env:CONFIG_NAME) {
	exit_with_error "Error: environment variable CONFIG_NAME was not found, this script must run as part of snapcreator job"
}

if (!$usersnap) {
	exit_with_error "Error: environment variable USER_SNAP_NAME was not found, this script must run as part of snapcreator job"
}

if (!$clone_prefix) {
	exit_with_error "Error: environment variable CLONEPREFIXNAME was not found, this script must run as part of snapcreator job"
}

Write-Log "" 

$volspersvm = $volumes.split(";")
$volspersvm | ForEach {
	$volpersvm = $_
	($svm, $vollist) = $volpersvm.split(":")

	#if powershell toolkit used to run the job
	if ($user_clone_name) {
		$vollist = $flexclonename -replace "^$($clone_prefix)",""
	}
		
	$vols = $vollist.split(",")
	$conn = Connect-NcController -name $svm -HTTPS -Credential $cred
	$vols | ForEach {
		$curvol = $_
		
		$flexclonename = $clone_prefix + $curvol
		
		$vol = Get-NcVol -Controller $conn | Where-Object {$_.Name -eq $flexclonename -and $_.VolumeIdAttributes.Comment -match "PARENTVOL:$curvol\,SCCLONENAME:(\S+)\,PROFILE:"}
		if (-not $vol) {
			exit_with_error "Error: could not locate clone volume $($svm):$($flexclonename) that has the required comment field (PARENTVOL:$($curvol),SCCLONENAME:snapname,PROFILE:)"
		}
		
		$origname = $matches[1]			
		
		$comment = '';
		$q = Get-NcVol -Template
		Initialize-NcObjectProperty $q VolumeIdAttributes
		$q.VolumeIdAttributes.Name = $vol.Name
		$voltemplate = Get-NcVol -Template
		Initialize-NcObjectProperty -Object $voltemplate -Name VolumeExportAttributes
		Initialize-NcObjectProperty -Object $voltemplate -Name VolumeIdAttributes
		$voltemplate.VolumeExportAttributes.Policy = 'default'
		
		Write-Log "resetting $($vol.Name) export-policy to default"
		$updatevol = Update-NcVol -Controller $conn -Query $q -Attributes $voltemplate				
		
		$exportpolicy = 'cl_'+$($vol.Name)
		Write-Log "deleting export-policy $exportpolicy"
		$e = Remove-NcExportPolicy -Name $exportpolicy -Controller $conn -Confirm:$false
		
		if ($vol.VolumeCloneAttributes) {
			Write-Log "rename clone from:$($vol.Name) to original clone name:$($origname)"
			$issplit = Get-NcVolCloneSplit | ? {$_.name -eq $vol.Name}
			if ($issplit) {
				Write-Log "aborting clone split for: $($vol.Name)"
				$abort = Stop-NcVolCloneSplit -Name $vol.Name
				sleep 2
			}
			
			$clusterconn = Connect-NcController -Name  $clustername -Credential $clustercred
			$issplit = Get-NcVolMove -Vserver $svm -Controller $clusterconn | ? {$_.Volume -eq $vol.Name -and $_.State -ne 'done'}
			if ($issplit) {
				Write-Log "aborting vol move for: $($vol.Name)"
				$abort = Stop-NcVolMove -Name $vol.Name -Vserver $svm -Controller $clusterconn
				sleep 10
			}
			
			
			$v = Rename-NcVol -Name $vol.Name -NewName $origname -Controller $conn
		} else {
			#snapcreate doesn't delete volumes which are not clones
			Write-Log "deleting volume:$($vol.Name) since it been splited after creation"
			$v = Dismount-NcVol -Name $vol.Name -Controller $conn
			$v = Set-NcVol -Name $vol.Name -Controller $conn -Offline 
			$i = 0
			While ( $i -lt 5) {
				$v = Get-NcVol -Name $vol.Name -Controller $conn
				if ($v.State -ne 'offline') {
					sleep 2
					$i++
					if ($i -eq 5) {
						exit_with_error "Error: cannot take volume offline"
					}
				} else {
					$i=5
				}
			}	
						
			Remove-NcVol -Name $($vol.Name) -Controller $conn -ErrorVariable err -Verbose -Confirm:$false
		
		}	
	}
}