#/bin/bash
#
# We create daily snapshots for MySQL Zabbix main DB.
#
# Purpose:
#
#1. Create a snapshot from the Mysql Slave server
#  1.1 Only if the replication lag is 0; else wait until the slave gets up-to-date with the master
############################################

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/root/aws-stack

. ./mysql-create-snapshot.inc.sh

##set -x

# Functions and parameters
TIMESTAMP=$(date +'%Y-%m-%dT%H:%M:%S-NZST')
REGION=ap-southeast-2
THIS_HOST=$(hostname | cut -f1 -d.)
SNAP_NAME_NEW="${THIS_HOST}-${TIMESTAMP}"
AWS_SNS_TOPIC="CHANGEME: Change this to your own ARN - arn:aws:sns:ap-southeast-2:15667:bauDevSNS"
MYSQL_VOLUME="/mysql"
LOG=/root/scripts/logs
MYSQL_SLAVE_INSTANCE_ID=$(/usr/bin/ec2metadata --instance-id)
MYSQL_SNAP_PREFIX="/mysql"
LOG_SNAP=/root/scripts/logs/mysql_snap.log
CHECK_MYSQL_RUNNING=$(ps -ef|grep -e 'mysqld' |grep -v 'grep' | wc -l)

# Getting the volume-id
GET_VOLUME_ID=$(aws ec2 describe-volumes --region $REGION --filters Name=attachment.instance-id,Values=$MYSQL_SLAVE_INSTANCE_ID Name=tag:volume-type,Values=mysql-prod --query "Volumes[*].VolumeId" | grep 'vol-' | sed -e 's/^ *//' -e 's/^"//'  -e 's/"$//')

# Creating the snapshot from the mysql-slave-server
# We only create the snapshot if the replication is = 0. Otherwise we exit and send an email.
#
echo "Creating a new snapshot at ${TIMESTAMP}..."
if [ ${REPLICATION} -eq 0 ]; then
  stop_mysql
  create_snapshot
  NEW_SNAP=$(echo ${CREATE_SNAP} | jq '.SnapshotId' | sed 's/"//g')
else
  #send sns notice
  MESSAGE="The MYSQL replication lag is too high on ${hostname}"
  SUBJECT="ERROR: Could not create a new snapshot on ${hostname}."
  dp_send_sns
  exit 1
fi

echo "MESSAGE: Add tags to snapshot" | tee -a ${LOG_SNAP}
add_snapshot_tag Name ${SNAP_NAME_NEW}
add_snapshot_tag prefix ${MYSQL_SNAP_PREFIX}
add_snapshot_tag partition ${MYSQL_VOLUME}
add_snapshot_tag hostname $(hostname)
echo "MESSAGE: Waiting for snapshot ${SNAP_NAME_NEW} named ${NEW_SNAP}" | tee -a ${LOG_SNAP}
wait_snapshot

# Restart MYSQL if the snapshot has been successfully created.
echo "MESSAGE: Starting up the MYSQL process" | tee -a ${LOG_SNAP}
service mysql stop
service mysql start

# We checked if the MYSQL process has been started. If not, send an email.
if [ $CHECK_MYSQL_RUNNING -gt 0 ]; then
	echo "MySQL successfully started"
else
	MESSAGE="MySQL process couldn't be started on ${hostname}."
	SUBJECT="ERROR: Error when starting up MySQL on ${hostname}."
	db_send_sns
	exit 1
fi

echo "MESSAGE: Check snapshot ID" | tee -a ${LOG_SNAP}
check_snapshot
