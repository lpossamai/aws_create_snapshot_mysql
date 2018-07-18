# aws_create_snapshot_mysql
Creating automated snapshots at AWS for a MySQL partition (Slave DB Server)

# Purpose:

1. Create a snapshot from the Mysql Slave server
    1. Only if the replication lag is 0; else wait until the slave gets up-to-date with the master

# Requisits:

1. You'll need a MySQL Standby DB Server running
2. You'll need a root access to that MYSQL Instance
3. The script is run locally on the slave server
4. Assuming the slave server is hosted in AWS, you'll need to create an [IAM role with full EC2 access](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html).
5. You'll need to [create a topic and a subscription in SNS](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/dashboardcreateSNStopic.html). So if the snapshot fails you'll get an email alert.
