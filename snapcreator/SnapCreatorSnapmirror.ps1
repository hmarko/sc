Param (
    [Parameter(Mandatory=$True)]
    [String]$profile,
	
    [Parameter(Mandatory=$True)]
    [String]$config
)

$sc = 1; $na = 1;
$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$GlobalFile = $PSScriptRoot+'\SCGlobalConfig.ps1'
if (!([System.IO.File]::Exists($GlobalFile))) {
	Write-Host "ERROR: failed to locate required file $($PSScriptRoot)\GlobalConfig.ps1" 
	$host.SetShouldExit(1) 
	exit
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
$notcompleted = $true

$connhash = @{}
$smstagehash = @{}

while ($notcompleted) {
	
	$notcompleted = $false
	
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

		$snapmirrordests = Get-NcSnapmirrorDestination -Source "$($svm):$($vol)" -Controller $conn
				
		if (-not $snapmirrordests ) {
			if (-not $smstagehash.ContainsKey("$($svm):$($vol):notexists")) {
				Write-Log "WARNING: $($svm):$($vol) doesn't have snapmirror destinations"
				$smstagehash.Add("$($svm):$($vol):notexists","completed")
			}
		} else {	
			$snapmirrordests | ForEach-Object {
				$destsvm = $_.DestinationVserver
				$destvol = $_.DestinationVolume
				if ($connhash.ContainsKey($destsvm)) {
					$conn1 = $connhash.$destsvm
				} else {
					$conn1 = Connect-NcController -Name $destsvm -Credential $cred 
					if (-not $conn1) {
						Write-Log "ERROR: cannot connect to destination SVM: $destsvm"
						$host.SetShouldExit(1) 
						exit 1
					}
					$connhash.Add($destsvm,$conn1)
				}
				
				$sm = Get-NcSnapmirror -Controller $conn1 -Destination "$($destsvm):$($destvol)"
						
				if ($sm) {
					if ($smstagehash.ContainsKey("$($destsvm):$($destvol)")) {
						if ($sm.Status -eq "transferring" -and $smstagehash.Get_Item("$($destsvm):$($destvol)") -ne 'completed') {
							Write-Log "$($svm):$($vol) -> $($destsvm):$($destvol) - update is still running, waiting for it to complete"
							$notcompleted = $true
						} elseif ($sm.Status -eq "idle" -and $smstagehash.Get_Item("$($destsvm):$($destvol)") -ne 'completed') {
							Write-Log "$($svm):$($vol) -> $($destsvm):$($destvol) - transfer completed"
							if (-not $sm.IsHealthy) {
								Write-Log "WARNING: $($svm):$($vol) -> $($destsvm):$($destvol) status is not healthy"
							}
							$smstagehash.Set_Item("$($destsvm):$($destvol)","completed")
						} 
					} else {
						if ($sm.MirrorState -ne "snapmirrored") {
							Write-Log "ERROR: $($destsvm):$($destvol) is not in mirrored state"
							$host.SetShouldExit(1) 
							exit 1						
						} elseif ($sm.Status -eq "transferring") {
							Write-Log "$($svm):$($vol) -> $($destsvm):$($destvol) - earlier transfer running, waiting for it to complete"
							$notcompleted = $true
						} elseif ($sm.Status -eq "idle") {
							Write-Log "$($svm):$($vol) -> $($destsvm):$($destvol) - starting update"
							$update = Invoke-NcSnapmirrorUpdate -Controller $conn1 -Destination "$($destsvm):$($destvol)" #-MaxTransferRate 10
							$smstagehash.Add("$($destsvm):$($destvol)","update")
							$notcompleted = $true
						}
					}
					#$smstagehash
				}
				if ($notcompleted) {
					Sleep 3
				}		
			}
		}
	}
}

Write-Log "snapmirror update completed successfuly"
$host.SetShouldExit(0) 
exit
