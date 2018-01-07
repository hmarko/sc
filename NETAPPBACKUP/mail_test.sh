Subject="junk pls ignore"
#address="TLV_All_IT_ERP_DBA_SUPPORT@verint.com Moshe.Karabelnik@verint.com gregory@elk-group.com"
#address=`cat /IT_DBA/dba/EMCBACKUP/elk4vnx/mailaddress.conf`
for address in `cat /IT_DBA/dba/EMCBACKUP/elk4vnx/mailaddresstest.conf` ; do
    mail -s "$Subject" $address <.
done
