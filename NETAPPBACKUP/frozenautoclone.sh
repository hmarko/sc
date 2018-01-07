#!/bin/bash 
#  Created by Tariel


#------------------------------------------------------------------------------------------------
# parametsr/env
export DATE=`date '+%d%m%y_%H%M%S'`
export LOGFILE=/tmp/frzfile$DATE.log
export SYSLOGFILE=/tmp/sysfrzfile$DATE.log
/bin/touch $LOGFILE
/bin/touch $SYSLOGFILE

export MAIL_LIST="TLV_All_IT_ERP_DBA_SUPPORT@verint.com"
export ECHO="/bin/echo"




#------------------------------------------------------------------------------------------------
#clean app processes 
ssh appfrz@tlvda2 "/IT_DBA/dba/scripts/kill_user.sh" 
ssh appfrz@tlvda2 date


#------------------------------------------------------------------------------------------------
# NETAPP
##/IT_DBA/dba/NETAPPBACKUP/auto_clone.sh "FRZ" "DEVEL" ###1>$LOGFILE >>2$LOGFILE

/IT_DBA/dba/NETAPPBACKUP/auto_clone_new.sh "FRZ"  >>$LOGFILE

grep "Session finished SUCCESSFULY" $LOGFILE
exit_code=$?
  if [ $exit_code -eq 0 ];
      then 
           echo "auto_clone.sh success" >>$LOGFILE
      else echo "auto_clone_new.sh error"
           echo "auto_clone_new.sh exit 1"
	  # echo "ORA-"
           exit 1;
  fi


${ECHO}  "-------------------------------------------------------------------------------------------------------">>$LOGFILE
${ECHO}  "-                                                                                                     -">>$LOGFILE
${ECHO}  "-                                                                                                     -">>$LOGFILE
${ECHO}  "-                                                                                                     -">>$LOGFILE
${ECHO}  "-                                                                                                     -">>$LOGFILE
${ECHO}  "-  Start FRZ script                                                                                   -">>$LOGFILE

/bin/sleep 60
##Oracle side

ssh orafrz@tlveddb3 "sudo /IT_DBA/dba/scripts/block_incoming_access.sh"
ssh orafrz@tlveddb3 "sudo /IT_DBA/dba/scripts/kill_outside_connections_tlveddb3.sh"


ssh appfrz@tlvda2 cat /verfrz/app/PROD/.PASSAPP
exit_code=$?
  if [ $exit_code -eq 0 ];
      then echo "App FS mounted "
      else echo "App FS not mounted"
           echo "Clone canceled"
           echo "ORA-"
           exit 1;
  fi


#create Archive symbolic link for all nodes
/IT_DBA/dba/scripts/cloneprod2dev_t6/bin/delete_archives_files_ln.sh
/IT_DBA/dba/scripts/cloneprod2dev_t6/bin/create_archives_files_ln.sh

ssh orafrz@tlveddb3 /IT_DBA/dba/scripts/cloneprod2dev_t6/start_Clone_env_General_VERFRZ.pl "VERFRZ"  `ssh appfrz@tlvda2 cat /verfrz/app/PROD/.PASSAPP`  >>$LOGFILE
exit_code=$?
  if [ $exit_code -eq 0 ];
      then
           echo "start_Clone_env_General_VERFRZ.pl success"
      else echo "Can't cp xml files to targed DB"
           echo "Clone Faild exit 1"
           echo "ORA-"
           exit 1;
  fi

ssh orafrz@tlveddb3 "sudo /IT_DBA/dba/scripts/open_incoming_access.sh"

#delete Archive symbolic link for all nodes
/IT_DBA/dba/scripts/cloneprod2dev_t6/bin/delete_archives_files_ln.sh

/usr/bin/mutt -s "auto_clone.sh FRZ" -a $LOGFILE  $MAIL_LIST<.
exit_code=$?
  if [ $exit_code -eq 0 ];
      then 
           echo "start_Clone_env_General_VERFRZ.pl success"
      else echo "Can't cp xml files to targed DB"
           echo "Clone Faild exit 1"
           echo "ORA-"
           exit 1;
  fi

# added on 01/11/17 by Galit
# create PATCH fs
sleep 840
ssh appfrz@tlvda2 /IT_DBA/dba/scripts/CreatePatchFS_VERFRZ.sh
