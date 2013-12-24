#!/bin/bash
# curl -L https://raw.github.com/imura81gt/aws-tools/master/ec2/ec2.sh | VOLUME_SIZE=10 VOLUME_TYPE=standard VPC_ID=vpc-39b72651 INSTANCE_TYPE=t1.micro TAG_KEY_NAME_VALUE=test001 TAG_KEY_SERVICE_VALUE=test KEY_NAME=aws-realworld SECURITY_GROUP_IDS=sg-f1938493 SUBNET_ID=subnet-24a5344c PRIVATE_IP_ADDRESS=10.0.3.9 IMAGE_ID=ami-9ffa709e  PROFILE=imura bash

for i in VOLUME_SIZE VOLUME_TYPE VPC_ID INSTANCE_TYPE TAG_KEY_NAME_VALUE TAG_KEY_SERVICE_VALUE KEY_NAME SECURITY_GROUP_IDS SUBNET_ID PRIVATE_IP_ADDRESS IMAGE_ID
do
  I=$(eval echo '$'$i)
  if [ "${I}" == "" ]
  then
    echo "Error: ENV[${i}] is required." 1>&2
    exit 1
  else
    echo $i=$I
  fi
done

if [ -z "${PROFILE}" ]; then
  PROFILE=default
fi

if [ -n ${PRIVATE_IP_ADDRESS} ]; then
  if [ "$(aws ec2 describe-instances --filters Name=network-interface.addresses.private-ip-address,Values=${PRIVATE_IP_ADDRESS} --profile ${PROFILE} | jq '.Reservations[].Instances[].PrivateIpAddress|length')" \> 0 ] ; then
    echo "Error: Address ${PRIVATE_IP_ADDRESS} is in use is in use." 1>&2
    exit 1
  fi
fi
 
echo '#run instances'
run_instances_result_json=`aws ec2 \
  run-instances \
  --image-id ${IMAGE_ID} \
  --key-name ${KEY_NAME} \
  --security-group-ids ${SECURITY_GROUP_IDS} \
  --instance-type ${INSTANCE_TYPE} \
  --subnet-id ${SUBNET_ID} \
  ${PRIVATE_IP_ADDRESS:+--private-ip-address ${PRIVATE_IP_ADDRESS}} \
  --no-ebs-optimized \
  --count 1 \
  --associate-public-ip-address \
  --block-device-mappings \
'[
  {
    "DeviceName": "/dev/sda",
    "Ebs": {
      "SnapshotId": "snap-6b398149",
      "VolumeSize": '${VOLUME_SIZE}',
      "DeleteOnTermination": false,
      "VolumeType": "standard"
    }
  }
]'\
  --profile ${PROFILE} \
`

echo ${run_instances_result_json}
INSTANCE_ID=(`echo ${run_instances_result_json} | jq '.Instances[].InstanceId' -r`)

echo '#create tag'
echo '${INSTANCE_ID} :' ${INSTANCE_ID}
aws ec2 create-tags --resources ${INSTANCE_ID} --tags Key=Name,Value=${TAG_KEY_NAME_VALUE} --profile ${PROFILE}
aws ec2 create-tags --resources ${INSTANCE_ID} --tags Key=Service,Value=${TAG_KEY_SERVICE_VALUE} --profile ${PROFILE}

echo "# The Instance"
aws ec2 describe-instances --instance-ids ${INSTANCE_ID} --profile ${PROFILE}
VOLUME_ID=`aws ec2 describe-instances --instance-ids ${INSTANCE_ID} --profile ${PROFILE} | jq '.Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId' -r`
echo "# You can remove the Security Group by the following command."
echo 'VOLUME_ID=`aws ec2 describe-instances --instance-ids '${INSTANCE_ID}' --profile '${PROFILE}' | jq '.Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId' -r`'
echo "aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} --profile ${PROFILE}"
echo 'aws ec2 delete-volume --volume-id ${VOLUME_ID} --profile '${PROFILE}''


