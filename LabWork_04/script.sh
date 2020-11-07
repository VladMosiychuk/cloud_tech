#!/bin/bash

while getopts ":i:" opt; do
  case $opt in
    i) IMAGE_ID="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

# If IMAGE_ID is not specified, use default
if [ -z "$IMAGE_ID" ]
then
    IMAGE_ID="ami-0605906d8afc35690" # Image from Lab_03
fi

LAB_NAME="lab_04"
AWS_REGION="us-east-1"

SSH_KEY_NAME="${LAB_NAME}_key"
SSH_KEY_FILE="${LAB_NAME}_key.pem"

SG_NAME="lab_04_sg"
SG_DESC="Security group to enable incoming TCP/22, TCP/80"

INSTANCE_TYPE="t2.micro"

ELB_NAME="lab-04-elb"
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


echo "-------> Modify index.html to be different on each instance"
INDEX_FN="/var/www/html/index.html"

# Iterate over each instance id
for INSTANCE_ID in ${INSTANCE_IDS[@]};
do

    # Find out Public IP of current instance 
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-id $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].{PublicIpAddress:PublicIpAddress}' \
        --output text \
        --region $AWS_REGION)


    echo "-------> Change content of index.html in $INSTANCE_ID"

    # Add host to known host to prevent script interruption
    ssh -o StrictHostKeyChecking=no ec2-user@$PUBLIC_IP > /dev/null

    # New index.html content
    CONTENT="<h1>It is instance $INSTANCE_ID</h1>"

    # Connect to instance using ssh and change content of index.html
    ssh -i $SSH_KEY_FILE ec2-user@$PUBLIC_IP -T \
    "rm -f $INDEX_FN && echo '$CONTENT' > $INDEX_FN" \
    > /dev/null

done

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