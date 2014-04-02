#!/bin/bash
#
# RDS(master) と同じAZにRDSを作成
# Nameタグ以外に必要なタグはTAGS='Key="タグ名",Value="値"'で設定
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

delete_rds()
{
  # usage : create_backup_rds ${BACKUP_INST_ID} 

  _BACKUP_INST_ID=${1}

  echo "`${_DATE}` START:deleting ${_BACKUP_INST_ID}" >> ${_WORK}/${_STAT}

  aws rds \
    delete-db-instance \
    --db-instance-identifier ${_BACKUP_INST_ID} \
    --skip-final-snapshot &&\
  echo "`${_DATE}` SUCCESS:deleting ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT} ||\
  echo "`${_DATE}` FAILED:deleting  ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT}
 
  # deleting -> available
  wait_deleted ${_BACKUP_INST_ID} &&\
  echo "`${_DATE}` SUCCESS:deleted  ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT} ||\
  echo "`${_DATE}` FAILED:deleted   ${_BACKUP_INST_ID}/${_BACKUP_INST_CLASS}" >> ${_WORK}/${_STAT}

}

wait_deleted()
{
  # usage : wait_deleted ${BACKUP_INST_ID}
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
          ;;
        backing-up)
          ;;
        creating)
          ;;
        deleted)
          break;;
        deleting)
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
        '')
          break;;
        *)
          is_break=false
          is_exit=true
          ;;
      esac
      
      if ${is_break}; then
        echo -e "\033[0;35m`${_DATE}` break (${status})\033[0;39m" >> ${_WORK}/${_STAT}
        break
      fi
    
      if ${is_exit}; then
        echo -e "\033[0;31m`${_DATE}` exit 1 (${status})\033[0;39m" >> ${_WORK}/${_STAT}
        exit 1
      fi
    done
  done
}

for i in BACKUP_INST_ID
do
  I=$(eval echo '$'$i)
  if [ "${I}" == "" ]
  then
    echo "Error: ENV[${i}] is required." 1>&2
    echo 'USAGE: BACKUP_INST_ID="backup-db-instance-identifier" [PROFILE=fuga] bash' `basename $0`
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

delete_rds ${BACKUP_INST_ID}
exit $?
