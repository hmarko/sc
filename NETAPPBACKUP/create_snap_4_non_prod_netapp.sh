#!/bin/bash
#Script for automatic backup  NONPROD env.
#Set variable
#Updated by Haim Marko hmarko@netapp.com to support NetApp cDOT integration and SnapCreator

#snapcreator server configuration
NAS_USER=DEMO\\administrator
NAS_HOST=192.168.0.5
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


REPLICA_ERROR="0"

case "$1" in
	DEV)APPHOST1="tlvda4"
		ENV="DEV"
		DBHOST1="tlveddb4"
		APPUSER="appdev"
		DBUSER="oradev"
		ENV_DIR="/devl"
		PROCLIST_RED=" ora_smon_DEV "
		PROCLIST_YELLOW=" tnslsnr DEV"
		VOLLIST="data logout redolog orahome"
		APPHOST="10.61.228.111"
		IPDBHOST="10.61.228.136"
		SC_PROFILE="TEST"
		SC_CONFIG="DEV"
		SC_POLICY="Daily"		
		#SC_CREATE_SNAPSHOT should by Y to create snapshot. if not Y snapshot will not be created 
		SC_CREATE_SNAPSHOT="Y"
		#COLD_BACKUP_MODE should be Y if we want to run the snapshot while in cold backup (DB will be down)
		COLD_BACKUP_MODE="Y"		
		;;	
	*) /bin/echo "Please specify existing ENV. "
		exit
		;;
esac
#DONE



error_exit ()
{
   message=$1
   Subject="netapp snap for non prod $ENVNAME failed"
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
  Subject="netapp backup for non prod $ENVNAME success"
  for address in `cat /IT_DBA/dba/NETAPPBACKUP/mailaddress.conf` ; do
       mail -s "$Subject" $address <.
  done
  echo "`date` Session finished SUCCESSFULY"
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

APPLIST="app logout";
SNAPS="orasw db appsr12w"

DIRNAME=`dirname $0`;
DATETIME=`date '+%d-%b-%Y_%H_%M'`
LOGNAME=non_prod_snap_${DATETIME}.log


LOGDIR=${DIRNAME}/log/auto_backup_non_prod_${ENVNAME}
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
	echo "`date` : Please make sure SSH PKI authentication is allowed to ${SSH_USER}@${SSH_HOST} and storage side tools are installed in ${NETAPPTOOLDIR}." >> ${LOGFILE}
	echo "`date` : Exiting." >> ${LOGFILE}
	rm -f ${TMPFILE}
	exit 2
fi

##################################################################################
#Usage
print_usage () {
/bin/echo "Run create_snap_4_non_prod_netapp.sh ENV_name DAILY/LAST"
/bin/echo "Notes:"
/bin/echo "ENV_name is a destination name of environment"
/bin/echo ""
}

#Function to check HOST ALIVE
#####################################################################################
check_host()
{

  echo "`date` : INFO : Start check Application Host $APPHOST1 " >>   $LOGFILE
	for HOST in $APPHOST1; do  # for loop and the {} operator
	    ssh $HOST -l $APPUSER true > /dev/null 2> /dev/null  # ping and discard output
	    if [ $? -eq 0 ]; then  # check the exit code
	        echo "$HOST is up" >>   $LOGFILE  # display the output
	    else
	        echo "`date` : ERROR : $HOST is down, terminating script administartor will be informed by mail"
 	        error_exit "`date` : ERROR : $HOST is down, terminating script administartor will be informed by mail"
	    fi
	done

	for HOST in $DBHOST1; do  # for loop and the {} operator
	    ssh $HOST -l $DBUSER true > /dev/null 2> /dev/null  # ping and discard output
	    if [ $? -eq 0 ]; then  # check the exit code
	        echo "$HOST is up" # display the output
	    else
	        echo "$HOST is down, terminating script administartor will be informed by mail"
 	    	error_exit "`date` : ERROR : $HOST is down, terminating script administartor will be informed by mail or $HOST can't be reachable by SSH, backup script will be terminated"
	    fi
	done
}

check_if_mounted()
{
    echo "`date ` Running check for first directiry on DB hosts...">>$LOGFILE
	for HOST in $DBHOST1 ; do
	    for VOL in $VOLLIST ; do
	        echo "`date` : COMMAND ssh $HOST -l $DBUSER grep $ENV_DIR/$VOL /proc/mounts">>$LOGFILE
	        ssh $HOST -l $DBUSER grep ${ENV_DIR}/$VOL /proc/mounts
	        if [ $? = 0 ] ; then
 	            echo "`date` on $HOST $ENV_DIR/$VOL mounted...">>$LOGFILE
	        else
 	            echo "`date` ABORTED check for $ENV_DIR/$VOL on $HOST hosts...">>$LOGFILE
                error_exit "`date` : ERROR : ABORTED check for $ENV_DIR/$VOL on $HOST hosts"
 	        fi
	    done
	done

	for HOST in $APPHOST1 ;do
	    for APPVOL in $APPLIST ; do
			echo "`date` : COMMAND ssh $HOST -l $APPUSER grep $ENV_DIR/$APPVOL /proc/mounts">>$LOGFILE
			ssh $HOST -l $APPUSER grep $ENV_DIR/$APPVOL /proc/mounts
			if [ $? = 0 ] ;  then
				echo "`date` on $HOST $ENV_DIR/$APPVOL mounted...">>$LOGFILE
			else
				echo "`date` ABORTED check for $ENV_DIR/$APPVOL directiry on $HOST hosts...">>$LOGFILE
				CheckMount=1
		        #  error_exit "`date` : ERROR : ABORTED check for $ENV_DIR/$APPVOL directiry on $HOST hosts"
			fi
			echo "`date ` Running check for second directiry on APP hosts...">>$LOGFILE
		done

		
		if [ CheckMount = 1 ] ;then
		   error_exit "`date` : ERROR : ABORTED check for $ENV_DIR/$APPVOL directiry on $HOST hosts"
		else   
			echo "`date` All operations completed successfully!">>$LOGFILE
			OK_exit "OK"
		fi
	done
}


#Function to stop APP and DB
#rm $LOGFILE

######### Stop all  DBs, umount  ##################################################################
 stop_inst ()
 {
   #Function to stop APP and DB
	echo "`date`: Stopping application" >> $LOGFILE
	for HOST in $APPHOST1 ;     do
	  echo "`date` : COMMAND ssh $HOST -l $APPUSER /IT_DBA/dba/scripts/stopapp $ENV" >>$LOGFILE
	  ssh $HOST -l $APPUSER "/IT_DBA/dba/scripts/stopapp $ENV"
	done

	echo "`date`: Stopping database" >>$LOGFILE
	for HOST in $DBHOST1 ; 	do
     	echo "`date` : COMMAND ssh $HOST -l $DBUSER /IT_DBA/dba/scripts/stopdb $ENV" >>$LOGFILE
     	ssh $HOST -l $DBUSER "/IT_DBA/dba/scripts/stopdb $ENV"
	done

	#Kill processes
    echo "`date`: Kill all processes for APP servers " >>$LOGFILE
    for HOST in $APPHOST1 ; do
	    for APPVOL in $APPLIST ; do
			echo "`date` : COMMAND ssh $HOST -l $APPUSER /sbin/fuser -mk ${ENV_DIR}/$APPVOL" >>$LOGFILE
			ssh $HOST -l $APPUSER /sbin/fuser -mk ${ENV_DIR}/$APPVOL	
		done
    done

	echo "`date`: Kill all processes for DB servers " >>$LOGFILE
        for HOST in $DBHOST1 ;  do
          for VOL in $VOLLIST ; do
           if [ $VOL = "arc" ] ; then
              echo "`date` : COMMAND ssh $HOST -l $DBUSER /sbin/fuser -mk /$VOL" >>$LOGFILE
              ssh $HOST -l $DBUSER /sbin/fuser -mk /$VOL
           else
              echo "`date` : COMMAND ssh $HOST -l $DBUSER /sbin/fuser -mk ${ENV_DIR}/$VOL" >>$LOGFILE
              ssh $HOST -l $DBUSER /sbin/fuser -mk ${ENV_DIR}/$VOL
           fi
          done
       done
	
	#Umount
	echo "`date`: Umount all volumes on DB" >> $LOGFILE
	for HOST in $DBHOST1 ;  do
		for VOL in $VOLLIST ; do
	   if [ $VOL = "arc" ] ; then
		   echo "`date` : COMMAND ssh $HOST -l $DBUSER /usr/local/bin/sudo /bin/umount -l" >>$LOGFILE
		   ssh $HOST -l  $DBUSER /usr/local/bin/sudo /bin/umount -l /$VOL
	   else
		   echo "`date` : COMMAND ssh $HOST -l $DBUSER /usr/local/bin/sudo /bin/umount -l ${ENV_DIR}/$VOL" >>$LOGFILE
			   ssh $HOST -l  $DBUSER /usr/local/bin/sudo /bin/umount -l ${ENV_DIR}/$VOL
	   fi
		done
	done

    echo "`date`: Umount all volumes on APP" >> $LOGFILE
    for HOST in $APPHOST1  ;    do
	    for APPVOL in $APPLIST ; do
			echo "`date` : COMMAND ssh $HOST -l $DBUSER /usr/local/bin/sudo /bin/umount -l  $ENV_DIR/$APPVOL" >>$LOGFILE
			ssh $HOST -l $APPUSER /usr/local/bin/sudo /bin/umount -l  $ENV_DIR/$APPVOL
        done
    done
}

###########################################################################

#########################################################################
#Function to mount all volumes back
#########################################################################

mount_all ()
{
   echo "`date`: Mount all volumes on DB" >> $LOGFILE
	for HOST in $DBHOST1 ; 	do
           for VOL in $VOLLIST ; do
              if [ $VOL = "arc" ] ; then
                 echo "`date` : COMMAND ssh $HOST -l $DBUSER /usr/local/bin/sudo /bin/mount -l  /$VOL" >>$LOGFILE
                 ssh $HOST -l  $DBUSER /usr/local/bin/sudo /bin/mount -l /$VOL
               else
                  echo "`date` : COMMAND ssh $HOST -l $DBUSER /usr/local/bin/sudo /bin/mount -l  ${ENV_DIR}/$VOL" >>$LOGFILE
                  ssh $HOST -l  $DBUSER /usr/local/bin/sudo /bin/mount -l ${ENV_DIR}/$VOL
               fi
            done
	done
	echo "`date`: Mount all volumes on APP" >> $LOGFILE
	for HOST in $APPHOST1 ; do
	    for APPVOL in $APPLIST ; do
			echo "`date` : COMMAND ssh $HOST -l $DBUSER /usr/local/bin/sudo /bin/mount -l  $ENV_DIR/$APPVOL" >>$LOGFILE
			ssh $HOST -l $APPUSER /usr/local/bin/sudo /bin/mount  $ENV_DIR/$APPVOL
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
	for HOST in $DBHOST1 ; 	do
		echo "`date` : COMMAND ssh $HOST -l $DBUSER /IT_DBA/dba/scripts/startdb $ENV" >>$LOGFILE
		ssh $HOST -l $DBUSER "/IT_DBA/dba/scripts/startdb $ENV" >>$LOGFILE
	done
	
	echo "`date` : sleeping 30 seconds to let the DB go up" >>$LOGFILE
	sleep 30	
	
	########      start DB ###################
	echo "`date`: Start application" >> $LOGFILE
	for HOST in $APPHOST1 ;do
		echo "`date` : COMMAND ssh $HOST -l $APPUSER /IT_DBA/dba/scripts/startapp $ENV" >>$LOGFILE
		ssh $HOST -l $APPUSER "/IT_DBA/dba/scripts/startapp $ENV" >>$LOGFILE
	done
	###################################################################################
}

#########################################################################
#### Function to make backup  ############################################
#########################################################################
snapshot ()
{

	#check if SC_CREATE_SNAPSHOT is Y (need to create snapshot)
	if [ "${SC_CREATE_SNAPSHOT}" = "Y" ]; then
	
		#if backup mode is HOT (HOT BACKUP mode on the production DB) 
		if [ "${COLD_BACKUP_MODE}" = "Y" ]; then
			echo "`date` : INFO : Stopping the App and DB to take snapshot..." >> $LOGFILE
			stop_inst
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
	
		#mount and start instance 
		if [ "${COLD_BACKUP_MODE}" = "Y" ]; then
			echo "`date` : INFO : Mounting filesystems..." >> $LOGFILE
			mount_all
			start_inst
		fi
		
		if [ "${REPLICA_ERROR}" = "1" ]; then 
			echo "`date` : Snapshot backup creation failed "  >> $LOGFILE
			error_exit "`date` : ERROR :  Snapshot backup creation failed !"
		fi
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
#---check_host

########## Create snapshot : ##############################################################################
/bin/echo "Running snapshot " >>$LOGFILE 

####################################################################
#### Create backup according to the configuration       #
####################################################################

snapshot

#######################################################################################################
# Get profile snapshot times
#######################################################################################################
SNAPS="*${SC_POLICY}*"
echo "`date` : Listing snapshot using SnapCreator Profile:${SC_PROFILE} Config:${SC_CONFIG} Snapshot:${SNAPS}" >> $LOGFILE
echo "${scSnapshot} ${SCE_PROFILE} ${SC_CONFIG} ${SNAPS}"  >> $LOGFILE 2>&1	
${scSnapshot} ${SC_PROFILE} ${SC_CONFIG} ${SNAPS} >> $LOGFILE 2>&1
#######################################################################################################################################################

/bin/echo "Snapshot finished." >> $LOGFILE

OK_exit "`date` - Process finished successfully "

