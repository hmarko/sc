set colsep ,
set pagesize 0
set trimspool on
set headsep off
set linesize 100

select count(*) from v$backup where status='ACTIVE';
exit;
