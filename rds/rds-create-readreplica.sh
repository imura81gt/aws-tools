#!/bin/bash
#
# RDS(master) と同じAZにRead Replicaを作成
# Nameタグ以外に必要なタグはTAGS='Key="タグ名",Value="値"'で設定
# 
# Requirements
#   aws-cli/1.3.2  or higher
#

for i in MASTER_INST_ID READ_INST_CLASS
do
  I=$(eval echo '$'$i)
  if [ "${I}" == "" ]
  then
    echo "Error: ENV[${i}] is required." 1>&2
    echo 'USAGE: MASTER_INST_ID="master-db-instance-identifier" READ_INST_CLASS="db.t1.micro" [TAGS='"'"'Key="Service",Value="hoge"[ Key="Env",Value="prod"]'"'"'] [PROFILE=fuga] bash' `basename $0`
    exit 1
  else
    echo $i=$I
  fi
done

if [ -z "${PROFILE}" ]; then
  PROFILE=""
else
  PROFILE="--profile ${PROFILE}"
fi
echo PROFILE=${PROFILE}

MASTER_AZ=`aws rds describe-db-instances --query 'DBInstances[?DBInstanceIdentifier==\`'${MASTER_INST_ID}'\`].AvailabilityZone' ${PROFILE} --output text`
READ_INST_ID="${MASTER_INST_ID}-bk"
READ_INST_TAGS_NAME="${READ_INST_ID}"
#DB_SUBNET_GROUP_NAME=`aws rds describe-db-instances --query 'DBInstances[?DBInstanceIdentifier==\`'${MASTER_INST_ID}'\`].DBSubnetGroup.DBSubnetGroupName' --output text`

aws rds \
  create-db-instance-read-replica \
  --db-instance-identifier "${READ_INST_ID}" \
  --source-db-instance-identifier "${MASTER_INST_ID}" \
  --db-instance-class "${READ_INST_CLASS}" \
  --availability-zone "${MASTER_AZ}" \
  --no-auto-minor-version-upgrade \
  --no-publicly-accessible \
  --tags Key="Name",Value="${READ_INST_TAGS_NAME}" ${TAGS} \
  ${PROFILE}




