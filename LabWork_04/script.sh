#!/bin/bash

while getopts ":i:" opt; do
  case $opt in
    i) IMAGE_ID="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

# Stop script execution if IMAGE_ID is not specified
if [ -z "$IMAGE_ID" ]
then
    echo "Lack of parameters!"
    echo "You should provide IMAGE_ID (-i)"
    exit 0
fi

LAB_NAME="lab_04"
AWS_REGION="us-east-1"

SSH_KEY_NAME="${LAB_NAME}_key"
SSH_KEY_FILE="${LAB_NAME}_key.pem"

SG_NAME="lab_04_sg"
SG_DESC="Security group to enable incoming TCP/22, TCP/80"

INSTANCE_TYPE="t2.micro"

ELB_NAME="lab-04-elb"

LT_NAME="lab_04-lt"
LT_DESC="Launch template for lab-04"
USER_DATA=$(cat update_html.sh | base64 -w 0)

ASG_NAME="lab-04-asg"
TG_NAME="lab-04-tg"


# Get default VPC Id
VPC_ID=$(aws ec2 describe-vpcs \
    --query "Vpcs[0].VpcId" \
    --output text \
    --region $AWS_REGION)


# Get two subnets from default VPC in current region
SUBNET_IDS=$(aws ec2 describe-subnets \
    --query 'Subnets[0:2].SubnetId' \
    --output text \
    --region $AWS_REGION)

# Save subnet ids into separate variables
read SUBNET_01_ID SUBNET_02_ID <<< $SUBNET_IDS

echo "-------> Create Application Load Balancer"

# Create ELB
LB_ARN=$(aws elbv2 create-load-balancer \
    --name $ELB_NAME \
    --type application \
    --scheme internet-facing \
    --subnets $SUBNET_IDS \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text \
    --region $AWS_REGION)


echo "-------> Create Security Group"

SG_ID=$(aws ec2 create-security-group \
    --group-name $SG_NAME \
    --description "$SG_DESC" \
    --query 'GroupId' \
    --output text \
    --region $AWS_REGION)

echo "-------> Enable incoming TCP/22"
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION

echo "-------> Enable incoming TCP/80"
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION


echo "-------> Associate Security Group with Load Balancer"
aws elbv2 set-security-groups \
    --load-balancer-arn $LB_ARN \
    --security-groups $SG_ID \
    --region $AWS_REGION \
    > /dev/null

echo "-------> Create SSH Key"

# Create SSH Key to connect to ec2 
aws ec2 create-key-pair \
    --key-name $SSH_KEY_NAME \
    --query 'KeyMaterial' \
    --output text \
    --region $AWS_REGION \
    > $SSH_KEY_FILE

# Change access to key file to protect it from other users
chmod 400 $SSH_KEY_FILE


echo "-------> Launch EC2 Instances"
INSTANCE_IDS=()

for SUBNET_ID in $SUBNET_IDS;
do

    INSTANCE_IDS+=($(aws ec2 run-instances \
        --image-id $IMAGE_ID \
        --count 1 \
        --instance-type $INSTANCE_TYPE \
        --key-name $SSH_KEY_NAME \
        --associate-public-ip-address \
        --security-group-ids $SG_ID \
        --user-data "$USER_DATA" \
        --subnet-id $SUBNET_ID \
        --query 'Instances[*].InstanceId' \
        --output text \
        --region $AWS_REGION))
    
done


# Save instance ids into separate variables
read INSTANCE_01_ID INSTANCE_02_ID <<< ${INSTANCE_IDS[@]}

# Wait for instance statustates to be `running`
for INSTANCE_ID in ${INSTANCE_IDS[@]};
do

    echo "-------> Wait for instance $INSTANCE_ID setup"

    bash ../Common/waitfor.sh -i $INSTANCE_ID -s running -d 5s
done


echo "-------> Create Target Group"
TG_ARN=$(aws elbv2 create-target-group \
    --name $TG_NAME \
    --target-type instance \
    --protocol HTTP \
    --port 80 \
    --vpc-id $VPC_ID \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text \
    --region $AWS_REGION)


echo "-------> Add instances to LB Target Group"
aws elbv2 register-targets \
    --target-group-arn $TG_ARN \
    --targets Id=$INSTANCE_01_ID Id=$INSTANCE_02_ID \
    --region $AWS_REGION


echo "-------> Add listener"
aws elbv2 create-listener \
    --load-balancer-arn $LB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN \
    --region $AWS_REGION \
    > /dev/null


echo "-------> Create Launch Template"

LT_ID=$(aws ec2 create-launch-template \
    --launch-template-name $LT_NAME \
    --version-description "$LT_DESC" \
    --launch-template-data "{\"NetworkInterfaces\":[{\"DeviceIndex\":0,\"AssociatePublicIpAddress\":true,\"Groups\":[\"$SG_ID\"],\"DeleteOnTermination\":true}],\"ImageId\":\"$IMAGE_ID\",\"InstanceType\":\"$INSTANCE_TYPE\",\"KeyName\":\"$SSH_KEY_NAME\",\"UserData\":\"$USER_DATA\"}" \
    --query 'LaunchTemplate.LaunchTemplateId' \
    --output text \
    --region $AWS_REGION)


echo "-------> Create Auto Scaling Group"

aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name $ASG_NAME \
    --launch-template LaunchTemplateId=$LT_ID \
    --min-size 2 \
    --max-size 2 \
    --desired-capacity 2 \
    --vpc-zone-identifier "$SUBNET_01_ID,$SUBNET_02_ID" \
    --target-group-arns $TG_ARN \
    --region $AWS_REGION


# Fetch DNS Name of Load Balacer
LB_DNS_NAME=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $LB_ARN \
    --query 'LoadBalancers[0].DNSName' \
    --output text \
    --region $AWS_REGION)


# Tell user everithing is OK
echo -e "\e[32mTwo WEB Servers & Load Balancer that distributes traffic between them are created!"
echo -e "Refresh page few times to see instance id chages."
echo -e "Use following link for verification:\n\e[0m"

echo -e "\t\e[34mhttp://$LB_DNS_NAME/\e[0m"


# Create destructor script to be able easily clean up everything
echo "#!/bin/bash

# Terminate instances
aws ec2 terminate-instances --instance-ids ${INSTANCE_IDS[@]} --region $AWS_REGION > /dev/null

# Wait for instance statustates to be terminated
for INSTANCE_ID in ${INSTANCE_IDS[@]};
do
    bash ../Common/waitfor.sh -i $INSTANCE_ID -s terminated -d 5s
done

# Delete SSH Key
aws ec2 delete-key-pair --key-name $SSH_KEY_NAME --region $AWS_REGION

# Remove file with SSH Key
rm -f $SSH_KEY_FILE

# Delete Auto Scaling group
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name $ASG_NAME --force-delete --region $AWS_REGION

# Delete Launch Template
aws ec2 delete-launch-template --launch-template-id $LT_ID --region $AWS_REGION > /dev/null

# Delete Load Balancer
aws elbv2 delete-load-balancer --load-balancer-arn $LB_ARN --region $AWS_REGION

# Delete Target Group
aws elbv2 delete-target-group --target-group-arn $TG_ARN --region $AWS_REGION

# Wait for all Security Group dependencies to be destroyed
N_SG_DEPENDENCIES=1
while [[ \$N_SG_DEPENDENCIES != 0 ]] 
do

    N_SG_DEPENDENCIES=\$(aws ec2 describe-network-interfaces --filters Name=group-id,Values=$SG_ID --query 'NetworkInterfaces[] | length(@)' --region $AWS_REGION)    

    sleep 5s
done

# Delete Security Group
aws ec2 delete-security-group --group-id $SG_ID --region $AWS_REGION

" > "destructor.sh"