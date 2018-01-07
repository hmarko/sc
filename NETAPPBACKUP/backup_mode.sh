#!/bin/sh 


RSTAT=0
STEP=$1
DATA_FS="db:orasw:appsw:applog";
TMPDIR=`mktemp -d`
rm /tmp/backup_status
. ~/.bashrc
. ~/.bash_profile
# Make remote temporary directory

# Preparing SQL files
cat > ${TMPDIR}/check_db_open.sql <<SQL
set colsep ,
set pagesize 0
set trimspool on
set headsep off
set linesize 100
select status from v\$instance;
exit;
SQL

cat > ${TMPDIR}/check_archivelog.sql <<SQL
set colsep ,
set pagesize 0
set trimspool on
set headsep off
set linesize 100

select log_mode from v\$database;
exit;
SQL

cat > ${TMPDIR}/check_backup_mode.sql <<SQL
set colsep ,
set pagesize 0
set trimspool on
set headsep off
set linesize 100

select count(*) from v\$backup where status='ACTIVE';
exit;
SQL

cat > ${TMPDIR}/begin_backup.sql <<SQL
set colsep ,
set pagesize 0
set trimspool on
set headsep off
set linesize 100

alter database begin backup;
exit;
SQL

cat > ${TMPDIR}/end_backup.sql <<SQL
set colsep ,
set pagesize 0
set trimspool on
set headsep off
set linesize 100

alter database end backup;
exit;
SQL

cat > ${TMPDIR}/switch_logfile.sql <<SQL
set colsep ,
set pagesize 0
set trimspool on
set headsep off
set linesize 100

alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
alter system switch logfile;
exit;
SQL

if [ "${STEP}" = "START" ] ; then
   echo "Checking database state..."
   sqlplus -S / as sysdba @${TMPDIR}/check_db_open.sql >${TMPDIR}/db_status_out

   DB_STATUS=`cat ${TMPDIR}/db_status_out`
   echo "DB status is : ${DB_STATUS}"
   if [ "${DB_STATUS}" != "OPEN" ]; then
      echo "`date` : DB is not in OPEN state. Exiting."
      rm -rf ${TMPDIR}
      echo "4" >/tmp/backup_status
      exit 4
   fi

   echo "Checking log mode..."
   sqlplus -S / as sysdba @${TMPDIR}/check_archivelog.sql >${TMPDIR}/db_log_mode_out

   DB_LOG_MODE=`cat ${TMPDIR}/db_log_mode_out`
   echo "DB log mode is : ${DB_LOG_MODE}"
   if [ "${DB_LOG_MODE}" != "ARCHIVELOG" ]; then
       echo "`date` : Can not perform online checkpoing in ${DB_LOG_MODE}. Exiting."
       rm -rf ${TMPDIR}
      echo "4" >/tmp/backup_status
       exit 4
   fi

   echo "Checking backup state..."
   sqlplus -S / as sysdba @${TMPDIR}/check_backup_mode.sql  >${TMPDIR}/dbf_backup_1_out

   DBF_BACKUP_COUNT=`cat ${TMPDIR}/dbf_backup_1_out | sed 's/\s//g'`
   echo "There are ${DBF_BACKUP_COUNT} database files in backup mode."
   if [ "${DBF_BACKUP_COUNT}" != "0" ]; then
      echo "`date` : There are files allready in backup mode. Exiting."
      rm -rf ${TMPDIR}
      echo "4" >/tmp/backup_status
      exit 4
   fi
#Added by Tariel 22Feb1013
 sqlplus -S / as sysdba @${TMPDIR}/switch_logfile.sql >${TMPDIR}/switch_logfile_out
   cat ${TMPDIR}/switch_logfile_out


   echo "Entering backup mode..."
   sqlplus -S / as sysdba @${TMPDIR}/begin_backup.sql  >${TMPDIR}/begin_backup_out
   cat ${TMPDIR}/begin_backup_out
 #  cat ${TMPDIR}/begin_backup_err >&2


   echo "Checking backup state..."
   sqlplus -S / as sysdba @${TMPDIR}/check_backup_mode.sql > ${TMPDIR}/dbf_backup_2_out

   DBF_BACKUP_COUNT=`cat ${TMPDIR}/dbf_backup_2_out | sed 's/\s//g'`
   echo "There are ${DBF_BACKUP_COUNT} database files in backup mode."
   if [ "${DBF_BACKUP_COUNT}" = "0" ]; then
       echo "`date` : There are no files in backup mode. BEGIN BACKUP failed! Exiting."
       rm -rf ${TMPDIR}
      echo "4" >/tmp/backup_status
       exit 4
   fi
   echo "0" >/tmp/backup_status
   exit 0
fi

if [ "${STEP}" = "END" ] ; then
   echo "Leaving backup mode..."
   sqlplus -S / as sysdba @${TMPDIR}/end_backup.sql > ${TMPDIR}/end_backup_out
   cat ${TMPDIR}/end_backup_out
#   cat ${TMPDIR}/end_backup_err >&2

   echo "Checking backup state..."
   sqlplus -S / as sysdba @${TMPDIR}/check_backup_mode.sql   >${TMPDIR}/dbf_backup_3_out


   DBF_BACKUP_COUNT=`cat ${TMPDIR}/dbf_backup_3_out | sed 's/\s//g'`
   echo "There are ${DBF_BACKUP_COUNT} database files in backup mode."
   if [ "${DBF_BACKUP_COUNT}" != "0" ]; then
      echo "`date` : There are still files in backup mode. BEGIN BACKUP failed! Continuing anyway."
	    echo "`date` : Please issue END BACKUP for database ASAP!!!"
	    RSTAT=10
   fi

   echo "Archiving current REDO LOG files..."

   sqlplus -S / as sysdba @${TMPDIR}/switch_logfile.sql >${TMPDIR}/switch_logfile_out
   cat ${TMPDIR}/switch_logfile_out
#   cat ${TMPDIR}/switch_logfile_err >&2


   echo "Cleaning up: temporary disabled."
   #rm -rf ${TMPDIR}
   #ssh -o BatchMode=yes -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_HOST} rm -rf ${TMPDIR}

   if [ ${RSTAT} -eq 0 ]; then
	echo "SUCCESS"
   else
	echo "FAILED"
   fi

   echo "$RSTAT" >/tmp/backup_status
   exit $RSTAT
fi
