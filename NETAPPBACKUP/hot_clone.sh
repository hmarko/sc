#!/bin/bash
#Script for automatic backup,clone,replicate  PROD env.
#Set variable
#Updated by Haim Marko hmarko@netapp.com to support NetApp cDOT integration and SnapCreator

#snapcreator server configuration
NAS_USER=VERINT\\svcnetapp
NAS_HOST=TLVPNAMIGR1
SSHSNAPCREATOR="ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey ${NAS_USER}@${NAS_HOST}"
NETAPPTOOLDIR="c:\\Scripts\\SnapCreator\\"

scBackup="${SSHSNAPCREATOR} ${NETAPPTOOLDIR}SnapCreatorBackup.bat"
scClone="${SSHSNAPCREATOR} ${NETAPPTOOLDIR}SnapCreatorClone.bat"
scGetProfiles="${SSHSNAPCREATOR} ${NETAPPTOOLDIR}SnapCreatorGetProfiles.bat"
scSnapmirror="${SSHSNAPCREATOR} ${NETAPPTOOLDIR}SnapCreatorSnapmirror.bat"
scSnapshot="${SSHSNAPCREATOR} ${NETAPPTOOLDIR}SnapCreatorSnapshotList.bat"
scUnmountClone="${SSHSNAPCREATOR} ${NETAPPTOOLDIR}SnapCreatorUmountClone.bat"
scExportProfile="${SSHSNAPCREATOR} ${NETAPPTOOLDIR}SnapCreatorExportProfile.bat"
scListClones="${SSHSNAPCREATOR} ${NETAPPTOOLDIR}SnapCreatorListClones.bat"

BASEDIR="/IT_DBA/dba/NETAPPSCRIPTS"
ENVNAME=$1

REPLICA_ERROR="0"

case "$1" in

        PROD_BACKUP_DAILY)	
                #SC_CREATE_SNAPSHOT should by Y to create snapshot. if not Y clone will be based on the latest exists snapshot
                SC_CREATE_SNAPSHOT="Y"
                #BACKUPMODE should be Y if we need to put the PRODUCTION DB in HOT backup mode before taking a snapshot otherwise crash consistent snapshot will be taken
                BACKUP_MODE="Y"
				#Production database user and host, used for backup mode 
				PROD_SSH_USER="oratest"
				PROD_SSH_HOST="tlvetdb3"	
                SC_PROFILE="PROD"
                SC_CONFIG="TEST"
                SC_POLICY="Daily"
				
                #SC_PROD_UPDATE_MIRROR should by Y to update mirror from prod to CLONE
                SC_PROD_UPDATE_MIRROR="Y"				
		;;
		
        FRZ_DAILY_CLONE)				
                #if SC_CLONE_UNMOUNT is Y previous clone will be destroyed prior clone creation
                SC_CLONE_UNMOUNT="Y"				
                #if SC_CLONE_CREATE is Y clone will be created
                SC_CLONE_CREATE="Y"
            	CLONE_APP_HOST1="tlvda5"
                CLONE_ENV="PROJ07"
                CLONE_DB_HOST1="tlveddb5"
                CLONE_APP_USER="appproj7"
                CLONE_DB_USER="oraproj7"	
				CLONE_EXPORT_IP_APP_HOST="10.61.248.100"
                CLONE_EXPORT_IP_DB_HOST="10.61.248.121:10.61.247.121"
                CLONE_DB_SMON=" ora_smon_PROJ07"
                CLONE_DB_LSNR=" tnslsnr PROJ07"
                CLONE_DB_VOL_LIST="data logout redolog orahome"		
				CLONE_APP_VOL_LIST="app logout";
                SC_CLONE_PROFILE="TEST"
                SC_CLONE_CONFIG="TEST"				
                SC_CLONE_NAME="PROJ07_"
                SC_CLONE_SNAPSHOT="*Daily*"
                SC_CLONE_CLONE_SPLIT="N"
		;;	
		
        PROJ07_CLONE)				
                #if SC_CLONE_UNMOUNT is Y previous clone will be destroyed prior clone creation
                SC_CLONE_UNMOUNT="Y"				
                #if SC_CLONE_CREATE is Y clone will be created
                SC_CLONE_CREATE="Y"
            	CLONE_APP_HOST1="tlvda5"
                CLONE_ENV="PROJ07"
                CLONE_DB_HOST1="tlveddb5"
                CLONE_APP_USER="appproj7"
                CLONE_DB_USER="oraproj7"	
				CLONE_EXPORT_IP_APP_HOST="10.61.248.100"
                CLONE_EXPORT_IP_DB_HOST="10.61.248.121:10.61.247.121"
                CLONE_DB_SMON=" ora_smon_PROJ07"
                CLONE_DB_LSNR=" tnslsnr PROJ07"
                CLONE_DB_VOL_LIST="data logout redolog orahome"		
				CLONE_APP_VOL_LIST="app logout";
                SC_CLONE_PROFILE="TEST"
                SC_CLONE_CONFIG="TEST"				
                SC_CLONE_NAME="PROJ07_"
                SC_CLONE_SNAPSHOT="*Daily*"
                SC_CLONE_CLONE_SPLIT="Y"
	;;	

	*) /bin/echo "Please specify existing ENV. "
		exit
		;;
esac
#DONE



error_exit ()
{
   message=$1
   Subject="netapp_clone for $ENVNAME failed"
   for address in `cat /IT_DBA/dba/NETAPPBACKUP/mailaddress.conf` ; do
       cat $LOGFILE | mail -s "$Subject" $address
   done
   for phone in `cat /IT_DBA/dba/NETAPPBACKUP/phonenumber.conf`; do
      send_sms $Subject $phone
   done

   exit
}


OK_exit ()
{
  Subject="netapp_clone for $ENVNAME success"
  for address in `cat /IT_DBA/dba/NETAPPBACKUP/mailaddress.conf` ; do
       mail -s "$Subject" $address <.
  done
  echo "`date` Session finished SUCCESSFULY" ### information for script frozenautoclone.sh
  exit
}
send_sms ()
{
   Subject=$1
   echo "====$Subject $phone"
   /usr/bin/perl /IT_DBA/infraScripts/pager.pl $phone@smscenter.co.il "verint:985ac13e59b31501896654fb1a925cf7" mail.smscenter.co.il \
"${Subject}" 1>/tmp/send_sms$$ 2>/tmp/send_sms$$
}
######################################################
# Processes to check
######################################################

ARGS=1

DIRNAME=`dirname $0`;
DATETIME=`date '+%d-%b-%Y_%H_%M'`
LOGNAME=auto_clone_${DATETIME}.log


LOGDIR=${DIRNAME}/log/auto_clone_${ENVNAME}
if [ ! -d  $LOGDIR ] ; then
   mkdir -p $LOGDIR
fi
LOGFILE=$LOGDIR/$LOGNAME

PATH="/usr/bin:/usr/sbin:/bin:/sbin"
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4
##################################################################################
#/bin/echo $*

TMPFILE=`mktemp`
echo "`date` : Check connectivity to Control Station..." >> ${LOGFILE}
${SSHSNAPCREATOR} "hostname" >/dev/null 2>${TMPFILE}
if [ $? -ne 0 ]; then
	echo "`date` : Failed to find storage side tools on ${NAS_HOST} . See error below:" >> ${LOGFILE}
	cat ${TMPFILE}  >> ${LOGFILE}
	echo "`date` : Please make sure SSH PKI authentication is allowed to ${PROD_SSH_USER}@${PROD_SSH_HOST} and storage side tools are installed in ${NETAPPTOOLDIR}." >> ${LOGFILE}
	echo "`date` : Exiting." >> ${LOGFILE}
	rm -f ${TMPFILE}
	exit 2
fi

##################################################################################
#Usage
print_usage () {
/bin/echo "Run netapp_clone.sh ENV_name "
/bin/echo "Notes:"
/bin/echo "ENV_name is a destination name of environment"
/bin/echo ""
}


#Function to check HOST ALIVE
#####################################################################################
check_host()
{

  echo "`date` : INFO : Start check Application Host $CLONE_APP_HOST1 " >>   $LOGFILE
	for HOST in $CLONE_APP_HOST1; do  # for loop and the {} operator
	    ssh $HOST -l $CLONE_APP_USER true > /dev/null 2> /dev/null  # ping and discard output
	    if [ $? -eq 0 ]; then  # check the exit code
	        echo "$HOST is up" >>   $LOGFILE  # display the output
	    else
	        echo "`date` : ERROR : $HOST is down, terminating script administartor will be informed by mail"
 	        error_exit "`date` : ERROR : $HOST is down, terminating script administartor will be informed by mail"
	    fi
	done

	for HOST in $CLONE_DB_HOST1; do  # for loop and the {} operator
	    ssh $HOST -l $CLONE_DB_USER true > /dev/null 2> /dev/null  # ping and discard output
	    if [ $? -eq 0 ]; then  # check the exit code
	        echo "$HOST is up" # display the output
	    else
	        echo "$HOST is down, terminating script administartor will be informed by mail"
 	    	error_exit "`date` : ERROR : $HOST is down, terminating script administartor will be informed by mail or $HOST can't be reachable by SSH, clone script will be terminated"
	    fi
	done
}

check_if_clone_mounted()
{
    echo "`date ` Running check for first directiry on DB hosts...">>$LOGFILE
	for HOST in $CLONE_DB_HOST1 ; do
	    for VOL in $CLONE_DB_VOL_LIST ; do
	        echo "`date` : COMMAND ssh $HOST -l $CLONE_DB_USER grep $CLONE_ENV_DIR/$VOL /proc/mounts">>$LOGFILE
	        ssh $HOST -l $CLONE_DB_USER grep ${CLONE_ENV_DIR}/$VOL /proc/mounts
	        if [ $? = 0 ] ; then
 	            echo "`date` on $HOST $CLONE_ENV_DIR/$VOL mounted...">>$LOGFILE
	        else
 	            echo "`date` ABORTED check for $CLONE_ENV_DIR/$VOL on $HOST hosts...">>$LOGFILE
                error_exit "`date` : ERROR : ABORTED check for $CLONE_ENV_DIR/$VOL on $HOST hosts"
 	        fi
	    done
	done

	for HOST in $CLONE_APP_HOST1 ;do
	    for APPVOL in $CLONE_APP_VOL_LIST ; do
			echo "`date` : COMMAND ssh $HOST -l $CLONE_APP_USER grep $CLONE_ENV_DIR/$APPVOL /proc/mounts">>$LOGFILE
			ssh $HOST -l $CLONE_APP_USER grep $CLONE_ENV_DIR/$APPVOL /proc/mounts
			if [ $? = 0 ] ;  then
				echo "`date` on $HOST $CLONE_ENV_DIR/$APPVOL mounted...">>$LOGFILE
			else
				echo "`date` ABORTED check for $CLONE_ENV_DIR/$APPVOL directiry on $HOST hosts...">>$LOGFILE
				CheckMount=1
		        #  error_exit "`date` : ERROR : ABORTED check for $CLONE_ENV_DIR/$APPVOL directiry on $HOST hosts"
			fi
			echo "`date ` Running check for second directiry on APP hosts...">>$LOGFILE
		done

		
		if [ CheckMount = 1 ] ;then
		   error_exit "`date` : ERROR : ABORTED check for $CLONE_ENV_DIR/$APPVOL directiry on $HOST hosts"
		else   
			echo "`date` All operations completed successfully!">>$LOGFILE
			OK_exit "OK"
		fi
	done
}


#Function to stop APP and DB
#rm $LOGFILE

######### Stop all  DBs, umount  ##################################################################
 stop_clone_inst ()
 {
   #Function to stop APP and DB
	echo "`date`: Stopping application" >> $LOGFILE
	for HOST in $CLONE_APP_HOST1 ;     do
	  echo "`date` : COMMAND ssh $HOST -l $CLONE_APP_USER /IT_DBA/dba/scripts/stopapp $CLONE_ENV" >>$LOGFILE
	  ssh $HOST -l $CLONE_APP_USER "/IT_DBA/dba/scripts/stopapp $CLONE_ENV"
	done

	echo "`date`: Stopping database" >>$LOGFILE
	for HOST in $CLONE_DB_HOST1 ; 	do
     	echo "`date` : COMMAND ssh $HOST -l $CLONE_DB_USER /IT_DBA/dba/scripts/stopdb $CLONE_ENV" >>$LOGFILE
     	ssh $HOST -l $CLONE_DB_USER "/IT_DBA/dba/scripts/stopdb $CLONE_ENV"
	done

	#Kill processes
    echo "`date`: Kill all processes for APP servers " >>$LOGFILE
    for HOST in $CLONE_APP_HOST1 ; do
	    for APPVOL in $CLONE_APP_VOL_LIST ; do
			echo "`date` : COMMAND ssh $HOST -l $CLONE_APP_USER /sbin/fuser -mk ${CLONE_ENV_DIR}/$APPVOL" >>$LOGFILE
			ssh $HOST -l $CLONE_APP_USER /sbin/fuser -mk ${CLONE_ENV_DIR}/$APPVOL	
		done
    done

	echo "`date`: Kill all processes for DB servers " >>$LOGFILE
	for HOST in $CLONE_DB_HOST1 ;  do
		for VOL in $CLONE_DB_VOL_LIST ; do
			echo "`date` : COMMAND ssh $HOST -l $CLONE_DB_USER /sbin/fuser -mk ${CLONE_ENV_DIR}/$VOL" >>$LOGFILE
			ssh $HOST -l $CLONE_DB_USER /sbin/fuser -mk ${CLONE_ENV_DIR}/$VOL
		done
	done
	
	#Umount
	echo "`date`: Umount all volumes on DB" >> $LOGFILE
	for HOST in $CLONE_DB_HOST1 ;  do
		for VOL in $CLONE_DB_VOL_LIST ; do
			echo "`date` : COMMAND ssh $HOST -l $CLONE_DB_USER /usr/local/bin/sudo /bin/umount -l ${CLONE_ENV_DIR}/$VOL" >>$LOGFILE
			ssh $HOST -l  $CLONE_DB_USER /usr/local/bin/sudo /bin/umount -l ${CLONE_ENV_DIR}/$VOL
		done
	done

    echo "`date`: Umount all volumes on APP" >> $LOGFILE
    for HOST in $CLONE_APP_HOST1  ;    do
	    for APPVOL in $CLONE_APP_VOL_LIST ; do
			echo "`date` : COMMAND ssh $HOST -l $CLONE_DB_USER /usr/local/bin/sudo /bin/umount -l  $CLONE_ENV_DIR/$APPVOL" >>$LOGFILE
			ssh $HOST -l $CLONE_APP_USER /usr/local/bin/sudo /bin/umount -l  $CLONE_ENV_DIR/$APPVOL
        done
    done
}

###########################################################################

#########################################################################
#Function to mount all volumes back
#########################################################################

mount_clone_fs ()
{
   echo "`date`: Mount all volumes on DB" >> $LOGFILE
	for HOST in $CLONE_DB_HOST1 ; 	do
		for VOL in $CLONE_DB_VOL_LIST ; do
			echo "`date` : COMMAND ssh $HOST -l $CLONE_DB_USER /usr/local/bin/sudo /bin/mount -l  ${CLONE_ENV_DIR}/$VOL" >>$LOGFILE
			ssh $HOST -l  $CLONE_DB_USER /usr/local/bin/sudo /bin/mount -l ${CLONE_ENV_DIR}/$VOL
		done
	done
	echo "`date`: Mount all volumes on APP" >> $LOGFILE
	for HOST in $CLONE_APP_HOST1 ; do
	    for APPVOL in $CLONE_APP_VOL_LIST ; do
			echo "`date` : COMMAND ssh $HOST -l $CLONE_DB_USER /usr/local/bin/sudo /bin/mount -l  $CLONE_ENV_DIR/$APPVOL" >>$LOGFILE
			ssh $HOST -l $CLONE_APP_USER /usr/local/bin/sudo /bin/mount  $CLONE_ENV_DIR/$APPVOL
		done		
	done
}

#########################################################################
#function to start the db and app following a cold backup 
#########################################################################
start_inst ()
{
	########      start DB ###################
	echo "`date`: Sstart database" >>$LOGFILE
	for HOST in $CLONE_DB_HOST1 ; 	do
		echo "`date` : COMMAND ssh $HOST -l $CLONE_DB_USER /IT_DBA/dba/scripts/startdb $CLONE_ENV" >>$LOGFILE
		ssh $HOST -l $CLONE_DB_USER "/IT_DBA/dba/scripts/startdb $CLONE_ENV" >>$LOGFILE
	done
	
	echo "`date` : sleeping 30 seconds to let the DB go up" >>$LOGFILE
	sleep 30	
	
	########      start DB ###################
	echo "`date`: Start application" >> $LOGFILE
	for HOST in $CLONE_APP_HOST1 ;do
		echo "`date` : COMMAND ssh $HOST -l $CLONE_APP_USER /IT_DBA/dba/scripts/startapp $CLONE_ENV" >>$LOGFILE
		ssh $HOST -l $CLONE_APP_USER "/IT_DBA/dba/scripts/startapp $CLONE_ENV" >>$LOGFILE
	done
	###################################################################################
}

#########################################################################
#### Function to make clone  ############################################
#########################################################################
backup_and_clone ()
{

	#check if SC_CREATE_SNAPSHOT is Y (need to create snapshot)
	if [ "${SC_CREATE_SNAPSHOT}" = "Y" ]; then
	
		#if backup mode is HOT (HOT BACKUP mode on the production DB) 
		if [ "${BACKUP_MODE}" = "Y" ]; then
			echo "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${PROD_SSH_USER}@${PROD_SSH_HOST} $BASEDIR/backup_mode.sh START"  >> $LOGFILE 2>&1
			ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${PROD_SSH_USER}@${PROD_SSH_HOST} $BASEDIR/backup_mode.sh START

			DBF_BACKUP_COUNT=`cat /tmp/backup_status | sed 's/\s//g'`
			if [ "${DBF_BACKUP_COUNT}" != "0" ]; then
				echo "`date` : There are still files in backup mode. BEGIN HOT BACKUP failed! Continuing anyway."  >> $LOGFILE
				echo "`date` : Please issue END BACKUP for database ASAP!!!"                                       >>$LOGFILE
					error_exit "`date` : ERROR :  There are still files in backup mode. BEGIN HOT BACKUP failed!"
				else
				echo "`date` :  BEGIN HOT BACKUP SUCCESSFULY."  >> $LOGFILE
			fi
			REPLICA_ERROR="0"
		fi
		
		#create snapshot
		echo "`date` : Creating snapshot using SnapCreator Profile:${SC_PROFILE} Config:${SC_CONFIG} Policy:${SC_POLICY}" >> $LOGFILE
		echo "${scBackup} ${SC_PROFILE} ${SC_CONFIG} ${SC_POLICY}"  >> $LOGFILE 2>&1	
		${scBackup} ${SC_PROFILE} ${SC_CONFIG} ${SC_POLICY} >> $LOGFILE 2>&1
		if [ $? -ne 0 ]; then
			echo "`date` ERROR : Snapshot backup failed. Look into the log for details." >> $LOGFILE
			error_list ${res}
			REPLICA_ERROR="1"
		else
			echo "`date` : Session create snapshot finished SUCCESSFULY"  >> $LOGFILE
		fi		
	
		#end backup mode 
		if [ "${BACKUP_MODE}" = "Y" ]; then
			echo "`date` : INFO : Leaving backup mode..." >> $LOGFILE
			ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${PROD_SSH_USER}@${PROD_SSH_HOST} $BASEDIR/backup_mode.sh END

			F_BACKUP_COUNT=`cat /tmp/backup_status  | sed 's/\s//g'`
			if [ "${DBF_BACKUP_COUNT}" != "0" ]; then
				echo "`date` : There are still files in backup mode. END HOT BACKUP failed!"  >> $LOGFILE
				echo "`date` : Please issue END BACKUP for database ASAP!!!"                                     >> $LOGFILE
				error_exit "`date` : ERROR :  There are still files in backup mode. END HOT BACKUP failed!"
			else
				echo "`date` :  END HOT BACKUP SUCCESSFULY."  >> $LOGFILE
			fi	
		fi
		
		if [ "${REPLICA_ERROR}" = "1" ]; then 
			echo "`date` : Snapshot backup creation failed "  >> $LOGFILE
			error_exit "`date` : ERROR :  Snapshot backup creation failed !"
		fi
	fi

	#update mirror if SC_PROD_UPDATE_MIRROR="Y"
	if [ "${SC_PROD_UPDATE_MIRROR}" = "Y" ]; then
		#update mirror
		echo "`date` : Updating mirror using SnapCreator Profile:${SC_PROFILE} Config:${SC_CONFIG}" >> $LOGFILE
		echo "${scSnapmirror} ${SC_PROFILE} ${SC_CONFIG}"  >> $LOGFILE 2>&1	
		${scSnapmirror} ${SC_PROFILE} ${SC_CONFIG} >> $LOGFILE 2>&1
		if [ $? -ne 0 ]; then
			echo "`date` ERROR : Session update mirror failed. Look into the log for details." >> $LOGFILE
			error_list ${res}
			REPLICA_ERROR="1"
			if [ "${REPLICA_ERROR}" = "1" ]; then 
				echo "`date` : Snapmirror update failed "  >> $LOGFILE
				error_exit "`date` : ERROR :  Snapmirror update failed !"
			fi			
		else
			echo "`date` : Session update mirror finished SUCCESSFULY"  >> $LOGFILE
		fi		
	fi
	
	#destroy existing clone if exists 
	if [ "${SC_CLONE_UNMOUNT}" = "Y" ]; then
		
		#stopping the current clone instance 
		stop_clone_inst
		
		#destroy (umount) clone 
		echo "`date` : Un-mounting clone using SnapCreator Profile:${SC_CLONE_PROFILE} Config:${SC_CLONE_CONFIG} Clone Name:${SC_CLONE_NAME}" >> $LOGFILE
		echo "${scUnmountClone} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} ${SC_CLONE_NAME}"  >> $LOGFILE 2>&1	
		${scUnmountClone} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} ${SC_CLONE_NAME} >> $LOGFILE 2>&1
		if [ $? -ne 0 ]; then
			echo "`date` : ERROR :  Clone doesn't exists !"
		fi
		
	fi

	
	#create clone if SC_CLONE_CREATE="Y"
	if [ "${SC_CLONE_CREATE}" = "Y" ]; then
		#create clone 
		echo "`date` : Creating clone using SnapCreator Profile:${SC_CLONE_PROFILE} Config:${SC_CLONE_SNAPSHOT} Clone Name:${SC_CLONE_NAME} Split:${SC_CLONE_CLONE_SPLIT}" >> $LOGFILE
		echo "${scClone} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} ${SC_CLONE_SNAPSHOT} ${SC_CLONE_NAME} ${CLONE_EXPORT_IP_DB_HOST}:${CLONE_EXPORT_IP_APP_HOST} ${SC_CLONE_CLONE_SPLIT}"  >> $LOGFILE 2>&1	
		${scClone} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} ${SC_CLONE_SNAPSHOT}  ${SC_CLONE_NAME} ${CLONE_EXPORT_IP_DB_HOST}:${CLONE_EXPORT_IP_APP_HOST} ${SC_CLONE_CLONE_SPLIT} >> $LOGFILE 2>&1
		if [ $? -ne 0 ]; then
			echo "`date` ERROR : Create clone failed. Look into the log for details." >> $LOGFILE
			error_list ${res}
			REPLICA_ERROR="1"
			if [ "${REPLICA_ERROR}" = "1" ]; then 
				echo "`date` : Clone create failed "  >> $LOGFILE
				error_exit "`date` : ERROR :  Clone create failed !"
			fi					
		else
			echo "`date` : Create clone finished SUCCESSFULY"  >> $LOGFILE
		fi		
		#mount file systems 
		mount_clone_fs
		######### Check if all mounted after create ENVNAMEOMENT ########################################################################
		check_if_clone_mounted		
		######## oracle will be started by another script 
	fi	
}

#########################################################################
###############                   M A I N         #######################
#########################################################################
# Test number of arguments to script (always a good idea).
if [ $# -ne $ARGS ]; then
   print_usage
   exit
fi

########## Check if host can be reachable by SSH #########################################################
check_host

########## Create clone : ##############################################################################
/bin/echo "Running clone " >>$LOGFILE 

####################################################################
#### Create backup and clones according to the configuration       #
####################################################################
backup_and_clone

#######################################################################################################
# Get profile snapshot times
#######################################################################################################
SNAPS="*${SC_POLICY}*"
echo "`date` : Listing snapshot using SnapCreator Profile:${SC_CLONE_PROFILE} Config:${SC_CLONE_CONFIG} Snapshot:${SNAPS}" >> $LOGFILE
echo "${scSnapshot} ${SCE_PROFILE} ${SC_CONFIG} ${SNAPS}"  >> $LOGFILE 2>&1	
${scSnapshot} ${SC_PROFILE} ${SC_CONFIG} ${SNAPS} >> $LOGFILE 2>&1
#######################################################################################################################################################


#######################################################################################################
# Listing all clones on the system
#######################################################################################################
if [ "${SC_CLONE_CREATE}" = "Y" ]; then
	echo "`date` : Listing clones using SnapCreator Profile:${SC_CLONE_PROFILE} Config:${SC_CLONE_CONFIG}" >> $LOGFILE
	echo "${scListClones} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG}"  >> $LOGFILE 2>&1	
	res=`${scListClones} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} >> $LOGFILE 2>&1`
fi
#######################################################################################################################################################

/bin/echo "Clone finished." >> $LOGFILE

OK_exit "`date` - Process finished successfully "


