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

$sshsnapcreator $scGetProfiles > /tmp/profileinfo.$$
awk '/Profile:/ {print $1;}' /tmp/profileinfo.$$ | awk 'BEGIN{FS=":"}{print $2;}' > /tmp/profiles.$$

profiles=''
i=0
while read line 
do
	grep "Profile:${line} Configs" /tmp/profileinfo.$$ | awk 'BEGIN{FS=":"}  {print $3;}' | tr " " "\n" > /tmp/configs_${line}.$$
	((i+=1))
	profiles+="${i} "
	profiles+="${line} "
done </tmp/profiles.$$

# Dialog utility to display options list

echo $profiles

while :
do
    declare -a profiles
    dialog --clear --backtitle "NetApp SnapCreator Managment" --title "MAIN MENU" \
    --menu "Use [UP/DOWN] key to select profile" 12 60 6 `echo ${profiles}`  2> /tmp/menuchoices.$$

    retopt=$?
    choice=`cat /tmp/menuchoices.$$`

    case $retopt in

          0) case $choice in
                  PROD)  profile=PROD; show_time ;;
                  TEST)  diskstats ;;
                  EXIT)  clear; exit 0;;
              esac ;;
          *)clear ; exit ;;
    esac

done

