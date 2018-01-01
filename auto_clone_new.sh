#!/bin/bash
#Script for automatic clone PROD env.
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

SSH_HOST=`hostname`
SSH_USER=oraprod
BASEDIR="/IT_DBA/dba/NETAPPBACKUP"
ENVNAME=$1

DM="db_rep"
AM12="appsr12w_rep"
SM="orasw_rep"
RL="redolog_rep"

REPLICA_ERROR="0"

INTERCONNECT=30003
DB="db:db_rep"
APPSR12W="appsr12w:appsr12w_rep"
ORASW="orasw:orasw_rep"
REDOLOG="redolog:redolog_rep"
SRV="server_4"

case "$1" in
       FRZ) APPHOST1="tlvda2"
            ENV="VERFRZ"
            DBHOST1="tlveddb3"
            APPUSER="appfrz"
            DBUSER="orafrz"
            ENV_DIR="/verfrz"
            VOLLIST="data orahome logout redolog"
 	        PROCLIST_RED=" ora_smon_VERFRZ "
            PROCLIST_YELLOW=" tnslsnr VERFRZ"
	        RETAINDSTSNAP=1
            #NFS IP, when multiple IP separate by colon (:). ex: 1.1.1.1:2.2.2.2:3.3.3.3
			IPAPPHOST="10.61.228.109"
            IPDBHOST="10.61.228.103"
			#BACKUPMOD should be Y if we need to put the DB in HOT backup mode. If not a crash consistent snapshot will be taken
			BACKUP_MODE="Y"
			SC_PROD_PROFILE="PROD"
			SC_PROD_CONFIG="prod"
			SC_POLICY="Daily"
			#SC_PROD_CREATE_SNAPSHOT should by Y to create snapshot. if not Y clone will be based on the latest exists snapshot
			SC_PROD_CREATE_SNAPSHOT="Y"
			#SC_PROD_UPDATE_MIRROR should by Y to update mirror from prod to CLONE 
			SC_PROD_UPDATE_MIRROR="Y"
			SC_CLONE_PROFILE="TEST"
			SC_CLONE_CONFIG="prod_rep"
			#if SC_CLONE_UNMOUNT is Y previous clone will be destroyed prior clone creation 
			SC_CLONE_UNMOUNT="Y"
			SC_CLONE_NAME="FRZ_"
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
   Subject="auto_clone for $ENVNAME failed"
   for address in `cat /IT_DBA/dba/NETAPPBACKUP/mailaddress.conf` ; do
       cat $LOGFILE $LOGDIR/$LOGFILE | mail -s "$Subject" $address
   done
   for phone in `cat /IT_DBA/dba/NETAPPBACKUP/phonenumber.conf`; do
      send_sms $Subject $phone
   done

   exit
}
OK_exit ()
{
  Subject="auto_clone for $ENVNAME success"
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

ARGS=1

APPLIST="app logout";
SNAPS="orasw db appsr12w"

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
	echo "`date` : Please make sure SSH PKI authentication is allowed to ${SSH_USER}@${SSH_HOST} and storage side tools are installed in ${NETAPPTOOLDIR}." >> ${LOGFILE}
	echo "`date` : Exiting." >> ${LOGFILE}
	rm -f ${TMPFILE}
	exit 2
fi

##################################################################################
#Usage
print_usage () {
/bin/echo "Run auto_clone_test.sh ENV_name DAILY/LAST"
/bin/echo "Notes:"
/bin/echo "ENV_name is a destination name of ENVNAMEonment"
/bin/echo "DAILY for create clone from daily snapshot."
/bin/echo "LAST for make clone from last made snapshot."
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
 	    	error_exit "`date` : ERROR : $HOST is down, terminating script administartor will be informed by mail or $HOST can't be reachable by SSH, clone script will be terminated"
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
###################################################################################

#### Function to make clone  #####################################################
clone ()
{

	#start hot backup mode if SC_PROD_CREATE_SNAPSHOT="Y"
	if [ "${SC_PROD_CREATE_SNAPSHOT}" = "Y" ]; then
	
		#if backup mode is Y (HOT BACKUP mode) 
		if [ "${BACKUP_MODE}" = "Y" ]; then
			echo "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${SSH_USER}@${SSH_HOST} $BASEDIR/backup_mode.sh START"  >> $LOGFILE 2>&1
			ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${SSH_USER}@${SSH_HOST} $BASEDIR/backup_mode.sh START

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
		echo "`date` : Creating snapshot using SnapCreator Profile:${SC_PROD_PROFILE} Config:${SC_PROD_CONFIG} Policy:${SC_POLICY}" >> $LOGFILE
		echo "${scBackup} ${SC_PROD_PROFILE} ${SC_PROD_CONFIG} ${SC_POLICY}"  >> $LOGFILE 2>&1	
		${scBackup} ${SC_PROD_PROFILE} ${SC_PROD_CONFIG} ${SC_POLICY} >> $LOGFILE 2>&1
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
			ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${SSH_USER}@${SSH_HOST} $BASEDIR/backup_mode.sh END

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

	#update mirrror if SC_PROD_UPDATE_MIRROR="Y"
	if [ "${SC_PROD_UPDATE_MIRROR}" = "Y" ]; then
		#update mirror
		echo "`date` : Updating mirror using SnapCreator Profile:${SC_PROD_PROFILE} Config:${SC_PROD_CONFIG}" >> $LOGFILE
		echo "${scSnapmirror} ${SC_PROD_PROFILE} ${SC_PROD_CONFIG}"  >> $LOGFILE 2>&1	
		${scSnapmirror} ${SC_PROD_PROFILE} ${SC_PROD_CONFIG} >> $LOGFILE 2>&1
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
		#destroy (umount) clone 
		echo "`date` : Creating clone using SnapCreator Profile:${SC_CLONE_PROFILE} Config:${SC_CLONE_CONFIG} Clone Name:${SC_CLONE_NAME}" >> $LOGFILE
		echo "${scUnmountClone} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} ${SC_CLONE_NAME}"  >> $LOGFILE 2>&1	
		${scUnmountClone} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} ${SC_CLONE_NAME} >> $LOGFILE 2>&1
		if [ $? -ne 0 ]; then
			echo "`date` : ERROR :  Clone doesn't exists !"
		fi
		
	fi

	
	#create clone if SC_PROD_UPDATE_MIRROR="Y"
	if [ "${REPLICA_ERROR}" = "0" ]; then
		#create clone 
		echo "`date` : Creating clone using SnapCreator Profile:${SC_CLONE_PROFILE} Config:${SC_CLONE_SNAPSHOT} Clone Name:${SC_CLONE_NAME} Split:${SC_CLONE_CLONE_SPLIT}" >> $LOGFILE
		echo "${scClone} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} ${SC_CLONE_SNAPSHOT} ${SC_CLONE_NAME} ${IPDBHOST}:${IPAPPHOST} ${SC_CLONE_CLONE_SPLIT}"  >> $LOGFILE 2>&1	
		${scClone} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} ${SC_CLONE_SNAPSHOT}  ${SC_CLONE_NAME} ${IPDBHOST}:${IPAPPHOST} ${SC_CLONE_CLONE_SPLIT} >> $LOGFILE 2>&1
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
	fi	
}


############### M A I N #######################
# Test number of arguments to script (always a good idea).
if [ $# -ne $ARGS ]; then
   print_usage
   exit
fi

########## Check if host can be reachable by SSH #########################################################
#--check_host

########## Create clone : ##############################################################################
/bin/echo "Running clone " >>$LOGFILE 
#--stop_inst
clone

##########  Mount new volumes #########################################################################
#--mount_all
######### Check if all mounted after create ENVNAMEOMENT ########################################################################
#--check_if_mounted

#######################################################################################################
# Get clone profile snapshot times
#######################################################################################################
SNAPS="*${SC_POLICY}*"
echo "`date` : Listing snapshot using SnapCreator Profile:${SC_CLONE_PROFILE} Config:${SC_CLONE_CONFIG} Snapshot:${SNAPS}" >> $LOGFILE
echo "${scSnapshot} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} ${SNAPS}"  >> $LOGFILE 2>&1	
${scSnapshot} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} ${SNAPS} >> $LOGFILE 2>&1
#######################################################################################################################################################


#######################################################################################################
# Listing all clones on the system
#######################################################################################################
echo "`date` : Listing clones using SnapCreator Profile:${SC_CLONE_PROFILE} Config:${SC_CLONE_CONFIG}" >> $LOGFILE
echo "${scListClones} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG}"  >> $LOGFILE 2>&1	
res=`${scListClones} ${SC_CLONE_PROFILE} ${SC_CLONE_CONFIG} >> $LOGFILE 2>&1`
#######################################################################################################################################################

/bin/echo "Clone finished." >> $LOGFILE

OK_exit "`date` - Process finished successfully "

