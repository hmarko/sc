#!/bin/bash

export PHONE_NUMBER=$1
#echo "Phone number : $1"
export MESSAGE=$2
#echo "Message is $2"
###SCRIPT_TOP=$3
SCRIPT_TOP=`dirname $PWD/$0`


#check environment

usage="send_sms  phone_number message"
if [ $# -lt 2 ]; then
   printf "\n:please enter phone number and message \n"
   printf "usage: $usage\n\n"
   exit 1;
fi


unset PERL5LIB
unset ADPERLPRG

/usr/bin/perl /IT_DBA/infraScripts/pager.pl ${PHONE_NUMBER}@smscenter.co.il \
"verint:985ac13e59b31501896654fb1a925cf7" mail.smscenter.co.il \
"${MESSAGE}" 1>/tmp/send_sms$$ 2>/tmp/send_sms$$

