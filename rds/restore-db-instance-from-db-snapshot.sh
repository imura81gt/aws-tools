#!/bin/bash
#
# RDS(master) と同じAZにRDSを作成
# Nameタグ以外に必要なタグはTAGS='Key="タグ名",Value="値"'で設定
# 本番かどうしているPGと別のPGを利用したい場合は DB_PARA_GROUPを設定
#   ex. メモリ関連のパラメータを設定変更しててt1.microで起動できない場合
# 
# Requirements
#   aws-cli/1.3.2  or higher
#

#log出力
#exec > tee -a `dirname $0`/`basename $0`.log."`${_DATE_FOR_FILENAME}`"  2>&1

_DATE="date +%Y/%m/%d-%H:%M:%S"
_DATE_FOR_FILENAME="date +%Y%m%d%H%M%S"
_STAT="status.log"
_WORK="/data/dump"

create_backup_rds()
{
  # usage : create_backup_rds ${BACKUP_INST_ID} ${BACKUP_INST_CLASS} ${BACKUP_INST_TAGS_NAME} ${TAGS}

  _BACKUP_INST_ID=${1}
  _BACKUP_INST_CLASS=${2}
  _BACKUP_INST_TAGS_NAME=${3}
  _TAGS=${4}
  _SNAPSHOT_ID=`aws rds \
    describe-db-snapshots \
    ${PROFILE} \
    --query 'DBSnapshots[?SnapshotType==\`automated\`][?DBInstanceIdentifier==\`'${MASTER_INST_ID}'\`]' |\
    jq -r 'max_by(.SnapshotCreateTime).DBSnapshotIdentifier'`
  echo _SNAPSHOT_ID=${_SNAPSHOT_ID}

  _MASTER_INST_JSON=`aws rds describe-db-instances  --query 'DBInstances[?DBInstanceIdentifier==\`'${MASTER_INST_ID}'\`]'`

  _DB_SUBNET_GROUP_NAME=`echo $_MASTER_INST_JSON | jq -r '.[].DBSubnetGroup.DBSubnetGroupName'`
  echo _DB_SUBNET_GROUP_NAME=${_DB_SUBNET_GROUP_NAME}

  _MASTER_AZ=`echo $_MASTER_INST_JSON | jq -r '.[].AvailabilityZone'`
  echo _MASTER_AZ=${_MASTER_AZ}

  if [ -z "${DB_PARA_GROUP}" ]; then
    _DB_PARA_GROUP=`echo $_MASTER_INST_JSON | jq -r '.[].DBParameterGroups[].DBParameterGroupName'`
  else
    _DB_PARA_GROUP=${DB_PARA_GROUP}
  fi

  echo _DB_PARA_GROUP=${_DB_PARA_GROUP}

  _DB_SEC_GROUP=`echo $_MASTER_INST_JSON | jq -r '.[].VpcSecurityGroups[].VpcSecurityGroupId'`
  echo _DB_SEC_GROUP=${_DB_SEC_GROUP}

  echo "`${_DATE}` START:restore ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT}

  aws rds \
    restore-db-instance-from-db-snapshot  \
    --db-instance-identifier ${_BACKUP_INST_ID} \
    --db-snapshot-identifier ${_SNAPSHOT_ID} \
    --db-instance-class ${_BACKUP_INST_CLASS} \
    --availability-zone ${_MASTER_AZ} \
    --db-subnet-group-name ${_DB_SUBNET_GROUP_NAME} \
    --no-multi-az \
    --no-auto-minor-version-upgrade \
    --tags Key="Name",Value="${_BACKUP_INST_TAGS_NAME}" ${_TAGS} &&\
  echo "`${_DATE}` SUCCESS:creating ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT} ||\
  echo "`${_DATE}` FAILED:creating  ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT}
 
  sleep 10 

  echo "`${_DATE}` START:wait_available ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT}

  # creating -> available
  wait_available ${_BACKUP_INST_ID} &&\
  echo "`${_DATE}` SUCCESS:available  ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT} ||\
  echo "`${_DATE}` FAILED:available   ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT}

  echo "`${_DATE}` START:modifying  ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT}

  # 自動バックアップはしない設定にする
  aws rds \
    modify-db-instance \
    --db-instance-identifier ${_BACKUP_INST_ID} \
    --vpc-security-group-ids ${_DB_SEC_GROUP} \
    --db-parameter-group-name ${_DB_PARA_GROUP} \
    --backup-retention-period 0 \
    --apply-immediately &&\
  echo "`${_DATE}` SUCCESS:modifying  ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT} ||\
  echo "`${_DATE}` FAILED:modifying   ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT}

  echo "`${_DATE}` START:available    ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT}

  # modifying -> available
  wait_available ${_BACKUP_INST_ID} &&\
  echo "`${_DATE}` SUCCESS:modified   ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT} ||\
  echo "`${_DATE}` FAILED:modified    ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT}
}

wait_available()
{
  # usage : wait_available ${BACKUP_INST_ID}
  _BACKUP_INST_ID=${1}
  _SLEEP_TIME=10
  for (( i = 0; i < 3; i++ )); do
    while :
    do
      sleep ${_SLEEP_TIME}
      status=`aws rds describe-db-instances --query 'DBInstances[?DBInstanceIdentifier==\`'${_BACKUP_INST_ID}'\`]'.DBInstanceStatus --output text`
      #echo ${_BACKUP_INST_ID} status: ${status}
      is_break=false
      is_exit=false
      case ${status} in
        available)
          is_break=true;;
        backing-up)
          ;;
        creating)
          ;;
        deleted)
          is_break=false
          is_exit=true
          ;;
        deleting)
          is_break=false
          is_exit=true
          ;;
        failed)
          is_break=false
          is_exit=true
          ;;
        incompatible-restore)
          is_break=false
          is_exit=true
          ;;
        incompatible-paraameters)
          is_break=false
          is_exit=true
          ;;
        modifying)
          ;;
        rebooting)
          ;;
        resetting-master-credentials)
          is_break=false
          is_exit=true
          ;;
        storage-full)
          is_break=false
          is_exit=true
          ;;
        *)
          is_break=false
          is_exit=true
          ;;
      esac
      
      if ${is_break}; then
        echo -e "\033[0;35m`${_DATE}` break (${status})\033[0;39m"  >> ${_WORK}/${_STAT}
        break
      fi
    
      if ${is_exit}; then
        echo -e "\033[0;31m`${_DATE}` exit 1 (${status})\033[0;39m" >> ${_WORK}/${_STAT}
        exit 1
      fi
    
      echo -e "\033[0;32m`${_DATE}` sleep ${_SLEEP_TIME} (${status})\033[0;39m" >> ${_WORK}/${_STAT}
    done
  done
}

for i in MASTER_INST_ID BACKUP_INST_CLASS
do
  I=$(eval echo '$'$i)
  if [ "${I}" == "" ]
  then
    echo "Error: ENV[${i}] is required." 1>&2
    echo 'USAGE: MASTER_INST_ID="master-db-instance-identifier" BACKUP_INST_CLASS="db.t1.micro" [TAGS='"'"'Key="Service",Value="hoge"[ Key="Env",Value="backup"]'"'"'] [PROFILE=fuga] bash' `basename $0`
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

PREFIX_FOR_BACKUP="backup-"
BACKUP_INST_ID="${PREFIX_FOR_BACKUP}${MASTER_INST_ID}"
echo BACKUP_INST_ID=${BACKUP_INST_ID}

BACKUP_INST_TAGS_NAME="${BACKUP_INST_ID}"
echo BACKUP_INST_TAGS_NAME=${BACKUP_INST_TAGS_NAME}

create_backup_rds ${BACKUP_INST_ID} ${BACKUP_INST_CLASS} ${BACKUP_INST_TAGS_NAME} ${TAGS}
exit $?

