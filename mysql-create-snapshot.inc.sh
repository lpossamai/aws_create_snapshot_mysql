#!/bin/bash
#
# mysql-create-snapshot-inc.sh
#
#

set -x

# Function to send emails
dp_send_sns() {
 THIS_SUBJECT=$(echo ${SUBJECT} | tr -d '"' | tr -d "'" | cut -c1-100)
 THIS_MESSAGE=$(echo ${MESSAGE} | tr -d '"' | tr -d "'")
 cat /dev/null > ${LOG}/mysql.sns.log
 echo aws sns publish ${PROFILE} >> ${LOG}/mysql.sns.log
 echo --region ${REGION} >> ${LOG}/mysql.sns.log
 echo --topic-arn "${AWS_SNS_TOPIC}" >> ${LOG}/mysql.sns.log
 echo --subject="${THIS_SUBJECT}" >> ${LOG}/mysql.sns.log
 echo --message "${THIS_MESSAGE}" >> ${LOG}/mysql.sns.log
 echo "-------------------------" >> ${LOG}/mysql.sns.log
 aws sns publish --region ${REGION} --topic-arn "${AWS_SNS_TOPIC}" --subject="${THIS_SUBJECT}" --message "${THIS_MESSAGE}" >> ${LOG}/mysql.sns.log 2>&1
}

# Stop MYSQL Before running the create-snapshot
stop_mysql() {
  MYSQL_RUNNING=$(ps -ef|grep -e '/usr/sbin/mysqld' |grep -v 'grep' |wc -l)
  if [ ${MYSQL_RUNNING} -gt 0 ]; then
    echo "MESSAGE: MySQL is running... Stopping it for data consistency"
    service mysql stop
    sleep 5
      MYSQL_RUNNING_2=$(ps -ef|grep -e '/usr/sbin/mysqld' |grep -v 'grep' |wc -l)
      if [ ${MYSQL_RUNNING_2} -gt 0 ]; then
        echo "MESSAGE: MySQL is still running... exiting"
        #send sns notice
        MESSAGE="Was not able to stop MYSQL on ${THIS_HOST}. ERROR: Could not stop Mysql process"
        SUBJECT="ERROR: Could not create a new snapshot on ${THIS_HOST}."
        dp_send_sns
        exit 1
      fi
  fi
}

# Check the replication lag
REPLICATION=$(mysql -u root --password="CHANGEME: ROOT_PASSWORD_HERE" -Bse "show slave status\G" | grep Seconds_Behind_Master | awk ' {print $2}')

create_snapshot() {
   # create snapshot
   CREATE_SNAP=$(aws ec2 create-snapshot --region ${REGION} \
       --volume-id ${GET_VOLUME_ID} --output json --description "${SNAP_NAME_NEW}")
}

check_snapshot() {
   COUNT=$(echo ${NEW_SNAP} | grep 'snap-' | wc -l)
   if [ ${COUNT} -eq 0 ]; then
      echo "ERROR: Could not get snapshot id" | tee -a ${LOG_SNAP}
      #send sns notice
      MESSAGE="Create ${MYSQL_VOLUME} snapshot ERROR on ${THIS_HOST} ERROR: Could not get snapshot id"
      SUBJECT=${MESSAGE}
      dp_send_sns
      exit 1
   fi
}

wait_snapshot() {
   # wait for snapshot to complete
   exit_status=''
   while [ "${exit_status}" != "0" ]
   do
      SNAPSHOT_STATE=$(aws ec2 describe-snapshots --region ${REGION} --filters Name=snapshot-id,Values=${NEW_SNAP} --query 'Snapshots[0].State')
      SNAPSHOT_PROGRESS=$(aws ec2 describe-snapshots --region ${REGION} --filters Name=snapshot-id,Values=${NEW_SNAP} --query 'Snapshots[0].Progress')
      echo "MESSAGE: Snapshot id ${NEW_SNAP} creation: state is ${SNAPSHOT_STATE}, ${SNAPSHOT_PROGRESS}"
      # aws ec2 wait snapshot-completed will poll every 15 seconds until a successful state has been reached.
      # This will exit with a return code of 255 after 40 failed checks. Therefore we need it in this while loop.
      aws ec2 wait snapshot-completed --region ${REGION} --snapshot-ids ${NEW_SNAP} > ${LOG}/mysql.wait.log 2>&1
      exit_status="$?"
   done
}

add_snapshot_tag() {
   local KEY=$1
   local VALUE=$2
   # add a tag Name=Name Value=the new name
   SNAPSHOT_NAME=$(aws ec2 create-tags --output text --region ${REGION} \
       --resources ${NEW_SNAP} --tags Key=${KEY},Value=${VALUE})
}
