#!/bin/sh -x

RSTAT=0
SSH_HOST=`hostname`
SSH_USER=oraprod
echo "$SSH_HOST"
DATA_FS="db:orasw:appsw:applog:arc:redolog";
TMPDIR=`mktemp -d`
SRV="server_3"
DATE=`date +%d-%b-%Y`
NAS_HOST="10.61.241.152"
NAS_USER="nasadmin"
EMCTOOLDIR="/nas/var/elk4vnx"
EMCLOGDIR="/nas/var/elk4vnx/bin/log/prod_snap_$DATE"
BASEDIR="/IT_DBA/dba/EMCBACKUP/elk4vnx"
LOGDIR="${BASEDIR}/log/prod_snap_$DATE"

LOGFILE="${LOGDIR}/prod_snap.log"
VNXLOGFILE="prod_snap.log"
error_exit ()
{
   message=$1
   scp  ${NAS_USER}@${NAS_HOST}:${EMCLOGDIR}/$VNXLOGFILE ${LOGDIR}/vnx_${VNXLOGFILE}
   for address in `cat /IT_DBA/dba/EMCBACKUP/elk4vnx/mailaddress.conf` ; do
       #cat $LOGFILE $LOGDIR/vnx_$VNXLOGFILE | mail -s $message $address
       echo "cat $LOGFILE $LOGDIR/vnx_$VNXLOGFILE | mail -s $message $address"
   done
   for phone in `cat /IT_DBA/dba/EMCBACKUP/elk4vnx/phonenumber.conf`; do
      #send_sms $message $phone
      echo "send_sms $message $phone"
   done

   exit
}
send_sms ()
{
   echo "====$message $phone"
   /usr/bin/perl /IT_DBA/infraScripts/pager.pl $phone@smscenter.co.il "verint:985ac13e59b31501896654fb1a925cf7" mail.smscenter.co.il \
"${message}" 1>/tmp/send_sms$$ 2>/tmp/send_sms$$

}
# Check connectivity to Control Station
echo "`date` ==== Start script ==============" >>$LOGFILE
echo "`date` : COMMAND : ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${NAS_USER}@${NAS_HOST} ls -l /nas/var/elk4vnx/bin/create_prod_snap.pl" >>$LOGFILE
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${NAS_USER}@${NAS_HOST} "ls -l /nas/var/elk4vnx/bin/create_prod_snap.pl" >/dev/null 2>${TMPDIR}/ssh_conn_err

if [ $? -ne 0 ]; then
	echo "`date` : Failed to find storage side tools on ${NAS_HOST} . See error below:" >>$LOGFILE
	cat ${TMPDIR}/ssh_conn_err   >>$LOGFILE
	echo "`date` : Please make sure SSH PKI authentication is allowed to ${NAS_USER}@${NAS_HOST} and storage side tools are installed in /nas/var/elk4vnx." >>$LOGFILE
	echo "`date` : Exiting."  >>$LOGFILE
	rm -rf ${TMPDIR}
	error_exit "Connectivity to VNX failed `date`"
fi

# Make remote temporary directory
#TMPDIR=`ssh -o BatchMode=yes -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_HOST} mktemp -d`
echo "`date` Start Hot Backup mode"  >>$LOGFILE
echo "`date` : COMMAND  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${SSH_USER}@${SSH_HOST} $BASEDIR/backup_mode.sh START " >>$LOGFILE

#####TEST ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${SSH_USER}@${SSH_HOST} $BASEDIR/backup_mode.sh START

echo "`date` Check status Hot Backup mode"  >>$LOGFILE
#####TESTDBF_BACKUP_COUNT=`cat /tmp/backup_status | sed 's/\s//g'`
#####TESTif [ "${DBF_BACKUP_COUNT}" != "0" ]; then
#####TEST    echo "`date` : There are still files in backup mode. BEGIN HOT BACKUP failed! Continuing anyway."  >>$LOGFILE
#####TEST    echo "`date` : Please issue END BACKUP for database ASAP!!!"  >>$LOGFILE
#####TEST   #RSTAT=11
#####TEST    error_exit " BEGIN HOT BACKUP failed!"
#####TESTfi

echo "`date` Starting checkpoits for DATA file systems : ${DATA_FS}...">>$LOGFILE
echo "`date` : COMMAND  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${NAS_USER}@${NAS_HOST} /nas/var/elk4vnx/bin/create_prod_snap.pl ${DATA_FS} ${SRV} $LOGFILE1" >>$LOGFILE
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${NAS_USER}@${NAS_HOST} /nas/var/elk4vnx/bin/create_prod_snap_new.pl ${DATA_FS} ${SRV} $VNXLOGFILE
RSTAT=$?
error_kod=`ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${NAS_USER}@${NAS_HOST} cat ${EMCLOGDIR}/error.txt`;

echo "`date` Start Leaving backup mode..." >>$LOGFILE
echo "`date` : COMMAND backup_mode.sh END" >>$LOGFILE
#####TEST ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T ${SSH_USER}@${SSH_HOST} <<ENDL
#####TEST $BASEDIR/backup_mode.sh END
#####TEST ENDL

echo "`date` Check status END Backup mode"  >>$LOGFILE
#####TEST  DBF_BACKUP_COUNT=`cat /tmp/backup_status  | sed 's/\s//g'`
#####TEST  if [ "${DBF_BACKUP_COUNT}" != "0" ]; then
#####TEST     echo "`date` : There are still files in backup mode. END HOT BACKUP failed! Continuing anyway.">>$LOGFILE
#####TEST     echo "`date` : Please issue END BACKUP for database ASAP!!!">>$LOGFILE
#####TEST   #  RSTAT=11
#####TEST     error_exit "END HOT BACKUP failed!"
#####TEST  fi

echo "`date` End Hot backup mode" >>$LOGFILE

echo "`date` Cleaning up: temporary disabled.">>$LOGFILE
#rm -rf ${TMPDIR}
#ssh -o BatchMode=yes -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_HOST} rm -rf ${TMPDIR}

if [ ${error_kod} -eq 0 ]; then
   error_exit "script create_prod_snap.sh SUCCESS"
else
   error_exit "script create_prod_snap.sh FAILED because VNX problem."
fi
exit ${error_kod}


~
~
~
~
~
~
~
~
~
~
~
~
~
~
~
~
~

