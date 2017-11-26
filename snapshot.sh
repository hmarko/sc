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
scExportProfile="${scpath}SnapCreatorExportProfile.bat"
scListClones="${scpath}SnapCreatorListClones.bat"

create_clone ()
{
	snapshot='*'
	dialog --ok-label "Create Clone" \
          --backtitle "Snapcreator create clone" \
          --title "Create Clone" \
          --form "Create Clone" 10 85 0 \
        "Snapshot (query with multiple answers wil pick the newest):" 1 1 "${snapshot}"  1 52 25 0 \
		"Clone Name:  " 2 1 "${clone}" 2 15 20 0 \
        "NFS Hosts (Seperated by :):" 3 1 "${nfshosts}" 3 30 35 0  2>/tmp/menuchoices.$$
	
	cloneparams=''
	while read line 
	do
		cloneparams+="\"${line}\" "
	done </tmp/menuchoices.$$		
	
	dialog --title "split clone from parent" \
	--backtitle "Snapcreator create clone" \
	--yesno "Do you want to split clone from parent ?" 7 60	
	response=$?
	case $response in
	   1) split='N';;
	   0) split='Y';;
	esac	
	clear;
	${sshsnapcreator} ${scClone} ${profile} ${config} ${cloneparams} ${split}

}

list_snapshots()
{
	dialog --title "Create clone " \
	--backtitle "you can use * for query (*daily* will list all snapshots countataining the word daily)"  \
	--inputbox "You can use * for query (*daily* will list all snapshots countataining the word daily) " 8 60 "*" 2>/tmp/menuchoices.$$
	snap=`cat /tmp/menuchoices.$$`
	clear
	${sshsnapcreator} ${scSnapshot} ${profile} ${config} "${snap}"
	read -r -p "Press enter to continue " response 
}

list_snapshots()
{
	dialog --title "List snapshots " \
	--backtitle "you can use * for query (*daily* will list all snapshots countataining the word daily)"  \
	--inputbox "You can use * for query (*daily* will list all snapshots countataining the word daily) " 8 60 "*" 2>/tmp/menuchoices.$$
	snap=`cat /tmp/menuchoices.$$`
	clear
	${sshsnapcreator} ${scSnapshot} ${profile} ${config} "${snap}"
	read -r -p "Press enter to continue " response 
}

create_backup() 
{
	${sshsnapcreator} ${scExportProfile} ${profile} ${config} > /tmp/configfile_${profile}_${config}.$$
	policies=`cat /tmp/configfile_${profile}_${config}.$$ | grep '^NTAP_SNAPSHOT_POLICIES=' | awk  'BEGIN{FS="="}  {print $2;}'| sed -e 's/\r//g'`
	#check if snapshot policies or retentions are used
	if ! [[ -z "$policies" ]]
	then
		IFS=',' read -r -a policiesarr <<< "$policies"
	else
		policies=`cat /tmp/configfile_${profile}_${config}.$$ | grep '^NTAP_SNAPSHOT_RETENTIONS=' | awk  'BEGIN{FS="="}  {print $2;}'|sed -e 's/\r//g'|sed -e 's/\:[0-9]\+//g'`;
		IFS=',' read -r -a policiesarr <<< "$policies";
	fi
	
	policiesmenuitems=''
	for p in "${policiesarr[@]}"
	do
        	policiesmenuitems+="${p} "
        	policiesmenuitems+="${p} "
	done 

	while :
	do
		dialog --backtitle "NetApp SnapCreator Managment" --title "Policies for Profile:${profile} Config:${config}" \
			--menu "Use [UP/DOWN] key to select config for Profile:${profile}" 12 70 8 `echo ${policiesmenuitems}` 2> /tmp/menuchoices.$$
		retopt=$?
		choice=`cat /tmp/menuchoices.$$`
		case $retopt in
			0)policy=${choice};clear; ${sshsnapcreator} ${scBackup} ${profile} ${config} ${policy}; read -r -p "Press enter to continue " response ;break;;
			*)clear ; break ;;
		esac
	done		
		
}
show_options() 
{
        while :
        do
                dialog --clear --backtitle "NetApp SnapCreator Managment" --title "Options" \
                        --menu "Use [UP/DOWN] key to select option for Profile:${profile} Config:${config}" 13 70 8 \
							"1" "Backup" \
							"2" "Snapmirror Update" \
							"3" "List Snapshots" \
							"4" "Create Clone" \
							"5" "List CLones" \
							"6" "Unmount Clone" 2> /tmp/menuchoices.$$
                retopt=$?
                choice=`cat /tmp/menuchoices.$$`

                case $retopt in
                     0)case $choice in
						1) create_backup;;
						2) clear; ${sshsnapcreator} ${scSnapmirror} ${profile} ${config};read -r -p "Press enter to continue " response ;;
						3) list_snapshots;;
						4) create_clone;;
						5) clear; ${sshsnapcreator} ${scListClones} ${profile} ${config};read -r -p "Press enter to continue " response ;;
						6) unmount_clone;;
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

