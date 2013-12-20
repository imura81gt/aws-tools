
#!/bin/bash
#
# curl -L https://raw.github.com/imura81gt/aws-tools/master/securitygroup/secg.sh | VPC_ID=vpc-xxxxxxxx SECG_NAME=hogehoge SECG_DESC='secg for hogehoge' IP_PERM_JSON=[https://example.com/hogehoge.json|file:///home/hogehoge/ipermissions.json] bash
#

for i in VPC_ID SECG_NAME SECG_DESC IP_PERM_JSON
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

if [ $(aws ec2 describe-security-groups --filters Name=group-name,Values=$SECG_NAME | jq '.SecurityGroups | length') == 1 ]
then
  SECG_ID=`aws ec2 describe-security-groups --filters Name=group-name,Values=opp-batch | jq '.SecurityGroups[].GroupId' -r`
  echo "Error: Already created Security Group(${SECG_NAME})" 1>&2
  echo "# You can remove the Security Group by the following command." 1>&2
  echo "aws ec2 delete-security-group --group-id ${SECG_ID}" 1>&2
  exit 1
fi

echo "# Create a new Security Group ${SG_NAME} to VPC(${VPC_ID})"
seg_g_result_array=(`aws ec2 create-security-group --group-name ${SECG_NAME} --description "${SECG_DESC}" --vpc-id ${VPC_ID} | jq '.return,.GroupId' -r`)

SECG_RETURN=${seg_g_result_array[0]}
SECG_ID=${seg_g_result_array[1]}

if [ "${SECG_RETURN}" = "false" ]
then
 echo "Error: aws ec2 --group-name ${SECG_NAME} --description "${SECG_DESC}" --vpc-id ${VPC_ID}"
 exit 1
fi

echo "# Add rules"
aws ec2 authorize-security-group-ingress --group-id ${SECG_ID} --ip-permissions ${IP_PERM_JSON}

echo "# The Security Group"
aws ec2 describe-security-groups --filters Name=group-name,Values=${SECG_NAME} --query "SecurityGroups[0]"

echo "# You can remove the Security Group by the following command."
echo "aws ec2 delete-security-group --group-id ${SECG_ID}"

