#!/bin/sh 
. ~/.bashrc
. ~/.bash_profile

TMPDIR=/tmp
cat > ${TMPDIR}/check_db_open.sql <<SQL
set colsep ,
set pagesize 0
set trimspool on
set headsep off
set linesize 100
select status from v\$instance;
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


   echo "Checking database state..."
   sqlplus -S / as sysdba @${TMPDIR}/check_db_open.sql >${TMPDIR}/db_status_out

   DB_STATUS=`cat ${TMPDIR}/db_status_out`
   echo "DB status is : ${DB_STATUS}"
   if [ "${DB_STATUS}" != "OPEN" ]; then
      echo "`date` : DB is not in OPEN state. Exiting."
      echo "4" >/tmp/backup_status
      rm ${TMPDIR}/db_status_out
      exit 4
   fi

   echo "Checking backup state..."
   sqlplus -S / as sysdba @${TMPDIR}/check_backup_mode.sql  >${TMPDIR}/dbf_backup_1_out

   DBF_BACKUP_COUNT=`cat ${TMPDIR}/dbf_backup_1_out | sed 's/\s//g'`
   echo "There are ${DBF_BACKUP_COUNT} database files in backup mode."
   if [ "${DBF_BACKUP_COUNT}" != "0" ]; then
      echo "`date` : There are files allready in backup mode. Exiting."
      echo "4" >/tmp/backup_status
      rm ${TMPDIR}/dbf_backup_1_out
      exit 4

   fi
#rm ${TMPDIR}/dbf_backup_1_out
rm ${TMPDIR}/db_status_out


