#!/bin/bash

NL=$'\n'
AWS_REGION="us-east-1"
VPC_NAME="lab_03_vpc"
VPC_CIDR="10.0.0.0/16"
SUBNET_PUBLIC_CIDR="10.0.0.0/24"
SUBNET_PRIVATE_CIDR="10.0.1.0/24"
SSH_KEY_NAME="${VPC_NAME}_key"
SSH_KEY_FILE="${VPC_NAME}_key.pem"
SG_NAME="SSH_Access"
SG_DESC="Security group for SSH access"
IMAGE_ID="ami-0947d2ba12ee1ff75" # Amazon Linux 2 in us-east-1
INSTANCE_TYPE="t2.micro"

# Create VPC
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_CIDR \
    --query 'Vpc.{VpcId:VpcId}' \
    --output text \
    --region $AWS_REGION)


# Add tag `Name` to VPC
aws ec2 create-tags \
    --resources $VPC_ID \
    --tags "Key=Name,Value=$VPC_NAME" \
    --region $AWS_REGION

# Create public subnet
SUBNET_PUBLIC_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $SUBNET_PUBLIC_CIDR \
    --query 'Subnet.{SubnetId:SubnetId}' \
    --output text \
    --region $AWS_REGION)

# Create private subnet
SUBNET_PRIVATE_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $SUBNET_PRIVATE_CIDR \
    --query 'Subnet.{SubnetId:SubnetId}' \
    --output text \
    --region $AWS_REGION)

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
    --query 'InternetGateway.{InternetGatewayId:InternetGatewayId}' \
    --output text \
    --region $AWS_REGION)

# Attach Internet Gateway to VPC
aws ec2 attach-internet-gateway \
    --vpc-id $VPC_ID \
    --internet-gateway-id $IGW_ID \
    --region $AWS_REGION

# Create custom route table
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --query 'RouteTable.{RouteTableId:RouteTableId}' \
    --output text \
    --region $AWS_REGION)

# Create route to Internet gateway
RESULT=$(aws ec2 create-route \
    --route-table-id $ROUTE_TABLE_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID \
    --region $AWS_REGION)


# Associate Public Subnet with Route Table
RESULT=$(aws ec2 associate-route-table  \
    --subnet-id $SUBNET_PUBLIC_ID \
    --route-table-id $ROUTE_TABLE_ID \
    --region $AWS_REGION)

# Enable Auto-assign Public IP on Public Subnet when new EC2 instance is launching
aws ec2 modify-subnet-attribute \
    --subnet-id $SUBNET_PUBLIC_ID \
    --map-public-ip-on-launch \
    --region $AWS_REGION

# Create SSH Key to connect to ec2 
aws ec2 create-key-pair \
    --key-name $SSH_KEY_NAME \
    --query 'KeyMaterial' \
    --output text \
    --region $AWS_REGION \
    > $SSH_KEY_FILE

# Change access to key file to protect it from other users
chmod 400 $SSH_KEY_FILE

# Create security group inside VPC
SG_ID=$(aws ec2 create-security-group \
    --group-name $SG_NAME \
    --description "$SG_DESC" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text \
    --region $AWS_REGION)

# Enable SSH Access from everywhere
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION

# Launch instance inside of public subnet
INSTANCE_ID=$(aws ec2 run-instances \
	--image-id $IMAGE_ID \
	--count 1 --instance-type $INSTANCE_TYPE \
	--key-name $SSH_KEY_NAME \
	--security-group-ids $SG_ID \
	--subnet-id $SUBNET_PUBLIC_ID \
    --query 'Instances[0].{InstanceId:InstanceId}' \
    --output text \
    --region $AWS_REGION)

#Find out Public IP of created instance 
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-id $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].{PublicIpAddress:PublicIpAddress}' \
    --output text \
    --region $AWS_REGION)

# Show how to connect to EC2 instance
echo "\e[32mVPC with two subnets is created!"

echo "Public subnet has working EC2 instace! \
Use following command to connect to this machine:\n\033[0m"

echo "\t\e[34msudo ssh -i "$SSH_KEY_FILE" ec2-user@$PUBLIC_IP\033[0m"

# Create destructor script to be able easily clean up everything
echo "# Terminate instance
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $AWS_REGION

# Delete SSH Key
aws ec2 delete-key-pair --key-name $SSH_KEY_NAME --region $AWS_REGION
rm -f $SSH_KEY_FILE

# Delete Security Group
aws ec2 delete-security-group --group-id $SG_ID --region $AWS_REGION

# Delete Public and Private Subnets
aws ec2 delete-subnet --subnet-id $SUBNET_PUBLIC_ID --region $AWS_REGION
aws ec2 delete-subnet --subnet-id $SUBNET_PRIVATE_ID --region $AWS_REGION

# Delete Route Table
aws ec2 delete-route-table --route-table-id $ROUTE_TABLE_ID --region $AWS_REGION

# Detach Internet Gateway from VPC
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $AWS_REGION

# Delete Internet Gateway
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $AWS_REGION

# Delete VPC
aws ec2 delete-vpc --vpc-id $VPC_ID --region $AWS_REGION
" > "destructor.sh"