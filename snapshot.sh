#!/bin/bash
# SCRIPT  : snapcreator menu
# PURPOSE : A menu driven Shell script using dialog utility to launch snapcreator
#


##############################################################################
#                 Checking availability of dialog utility                    #
##############################################################################
which dialog &> /dev/null
[ $? -ne 0 ]  && echo "Dialog utility is not available, Install it" && exit 1

##############################################################################
#	check that it is possable to ssh the windows snapcreator server      #
##############################################################################
sshsnapcreator="ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey demo\\administrator@192.168.0.5"
$sshsnapcreator hostname &> /dev/null
[ $? -ne 0 ]  && echo "cannot ssh to snapcreator server" && exit 1 

##############################################################################
#           snapcreator CLI on the snapcreator server                        #
##############################################################################
scpath="C:\\Scripts\\Snapcreator\\"
scBackup="${scpath}SnapCreatorBackup.bat"
scClone="${scpath}SnapCreatorClone.bat"
scGetProfiles="${scpath}SnapCreatorGetProfiles.bat"
scSnapmirror="${scpath}SnapCreatorSnapmirror.bat"
scSnapshot="${scpath}SnapCreatorSnapshotList.bat"
scRemoveClone="${scpath}SnapCreatorUmountClone.bat"

show_options() 
{
        while :
        do
                dialog --clear --backtitle "NetApp SnapCreator Managment" --title "Options" \
                        --menu "Use [UP/DOWN] key to select option for Profile:${profile} Config:${config}" 13 70 8 \
			"1" "Daily Snapshot" \
			"2" "Weekly Snapshot" \
			"3" "Manual Snapshot - This snashot will remain until it will be deleted" \
			"4" "Snapmirror Update" \
			"5" "Create Clone" \
			"6" "List Snapshots" 2> /tmp/menuchoices.$$
                retopt=$?
                choice=`cat /tmp/menuchoices.$$`

                case $retopt in
                     0)case $choice in
						1) clear; ${sshsnapcreator} ${scBackup} ${profile} ${config} daily; exit $?;;
						2) clear; ${sshsnapcreator} ${scBackup} ${profile} ${config} weekly; exit $?;;
						3) clear; ${sshsnapcreator} ${scBackup} ${profile} ${config} manual; exit $?;;
						4) clear; ${sshsnapcreator} ${scSnapmirror} ${profile} ${config} manual; exit $?;;
						5) create_clone;;
						6) list_snapshots;;
					esac ;;
					*)clear ; break ;;
                esac
        done

}

show_configs()
{
	configs=''
	while read line
	do
        	configs+="${line} "
        	configs+="${line} "
	done </tmp/configs_${profile}.$$

	while :
	do
		dialog --backtitle "NetApp SnapCreator Managment" --title "Configs" \
			--menu "Use [UP/DOWN] key to select config for Profile:${profile}" 12 70 8 `echo ${configs}` 2> /tmp/menuchoices.$$
		retopt=$?
		choice=`cat /tmp/menuchoices.$$`
		case $retopt in
			0)config=${choice};show_options;;
			*)clear ; break ;;
		esac
	done
}



$sshsnapcreator $scGetProfiles > /tmp/profileinfo.$$
awk '/Profile:/ {print $1;}' /tmp/profileinfo.$$ | awk 'BEGIN{FS=":"}{print $2;}' > /tmp/profiles.$$

profiles=''
while read line 
do
	grep "Profile:${line} Configs" /tmp/profileinfo.$$ | awk 'BEGIN{FS=":"}  {print $3;}' | tr " " "\n" > /tmp/configs_${line}.$$
	profiles+="${line} "
	profiles+="${line} "
done </tmp/profiles.$$

# Dialog utility to display options list

while :
do
    dialog --clear --backtitle "NetApp SnapCreator Managment" --title "MAIN MENU" \
    --menu "Use [UP/DOWN] key to select profile" 12 60 6 `echo ${profiles}` 2> /tmp/menuchoices.$$

    retopt=$?
    choice=`cat /tmp/menuchoices.$$`

    case $retopt in

          0)profile=${choice};show_configs;; 
          *)clear ; exit ;;
    esac

done

