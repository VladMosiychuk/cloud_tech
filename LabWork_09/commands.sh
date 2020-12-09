#!/bin/bash


# Region to use
AWS_REGION="us-east-1" 

# Networking settings
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.0.0/24"
SG_NAME="lab_09_sg"
SG_DESC="Security group for lab_09"

# Fargate cluster name
CLUSTER_NAME="lab_09_cluster"

# Fargate service name
SERVICE_NAME="lab_09_service"


### PREPARATION ### 

# Create VPC
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_CIDR \
    --query 'Vpc.{VpcId:VpcId}' \
    --output text \
    --region $AWS_REGION)

# Create subnet
SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block $SUBNET_CIDR \
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
aws ec2 create-route \
    --route-table-id $ROUTE_TABLE_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID \
    --region $AWS_REGION

# Associate Subnet with Route Table
aws ec2 associate-route-table  \
    --subnet-id $SUBNET_ID \
    --route-table-id $ROUTE_TABLE_ID \
    --region $AWS_REGION

# Create security group 
SG_ID=$(aws ec2 create-security-group \
    --group-name $SG_NAME \
    --description "$SG_DESC" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text \
    --region $AWS_REGION)

# Enable incoming TCP/80
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION


### ACTUAL LAB WORK ###

# Create a Cluster
aws ecs create-cluster \
    --cluster-name $CLUSTER_NAME \
    --region $AWS_REGION

# Register a Task Definition
aws ecs register-task-definition \
    --cli-input-json file://taskdef.json \
    --region $AWS_REGION

# List Task Definitions
aws ecs list-task-definitions \
    --region $AWS_REGION

# Create a Service
aws ecs create-service \
    --cluster $CLUSTER_NAME \
    --service-name $SERVICE_NAME \
    --task-definition sample-fargate:1 \
    --desired-count 1 \
    --launch-type "FARGATE" \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
    --region $AWS_REGION

# List Services
aws ecs list-services \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION

# Describe th Running Service
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $AWS_REGION


### CREATE DESTRUCTOR TO CLEAN EVERYTHING UP ###

echo "#!/bin/bash

# Delete service
aws ecs delete-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --region $AWS_REGION --force

# Delete cluster
aws ecs delete-cluster --cluster $CLUSTER_NAME --region $AWS_REGION

# Delete Security Group
aws ec2 delete-security-group --group-id $SG_ID --region $AWS_REGION

# Delete Subnet
aws ec2 delete-subnet --subnet-id $SUBNET_ID --region $AWS_REGION

# Delete Route Table
aws ec2 delete-route-table --route-table-id $ROUTE_TABLE_ID --region $AWS_REGION

# Detach Internet Gateway from VPC
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $AWS_REGION

# Delete Internet Gateway
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $AWS_REGION

# Delete VPC
aws ec2 delete-vpc --vpc-id $VPC_ID --region $AWS_REGION

" > "destructor.sh"
