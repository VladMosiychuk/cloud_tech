#!/bin/bash


LAB_NAME="lab_03"
AWS_REGION="us-east-1"
SSH_KEY_NAME="${LAB_NAME}_key"
SSH_KEY_FILE="${LAB_NAME}_key.pem"
SG_NAME="Lab_03_SG"
SG_DESC="Security group to enable incoming TCP/22, TCP/80, TCP/443"
IMAGE_ID="ami-0947d2ba12ee1ff75" # Amazon Linux 2 in us-east-1
INSTANCE_TYPE="t2.micro"
AMI_NAME="${LAB_NAME}_ami"
AMI_DESC="An AMI with Apache web server installed"


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


echo "-------> Create Security Group"

# Create security group 
SG_ID=$(aws ec2 create-security-group \
    --group-name $SG_NAME \
    --description "$SG_DESC" \
    --query 'GroupId' \
    --output text \
    --region $AWS_REGION)

# Enable incoming TCP/22
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION

# Enable incoming TCP/80
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION

# Enable incoming TCP/443
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION


echo "-------> Launch EC2 Instance"

# Launch EC2 Instance
INSTANCE_ID=$(aws ec2 run-instances \
	--image-id $IMAGE_ID \
	--count 1 --instance-type $INSTANCE_TYPE \
	--key-name $SSH_KEY_NAME \
	--security-group-ids $SG_ID \
    --user-data file://webconf.sh \
    --query 'Instances[0].{InstanceId:InstanceId}' \
    --output text \
    --region $AWS_REGION)


echo "-------> Tag Instance"

# Tag EC2 Instance with `Role` -> `WebServer`
aws ec2 create-tags \
    --resources $INSTANCE_ID \
    --tags "Key=Role,Value=WebServer" \
    --region $AWS_REGION


echo "-------> Wait for instance setup"

# Wait for instance statustates to be `running`
bash waitfor.sh -i $INSTANCE_ID -s running -d 5s

echo "-------> Create Image out of instance"

# Create image using EC2 Instance
AMI_ID=$(aws ec2 create-image \
    --instance-id $INSTANCE_ID \
    --name $AMI_NAME \
    --description "$AMI_DESC" \
    --no-reboot \
    --query 'ImageId' \
    --output text \
    --region $AWS_REGION)

# Wait for image state to be `available`
echo "-------> Wait for image ready"
bash waitforimage.sh -i $AMI_ID -s available -d 5s


# Remember API Snapshot ID for destructor
SNAP_ID=$(aws ec2 describe-images \
    --image-ids $AMI_ID \
    --query "Images[0].BlockDeviceMappings[0].Ebs.{SnapshotId:SnapshotId}" \
    --output text \
    --region $AWS_REGION)

echo "-------> Terminate Instance"

# Terminate EC2 Instance
aws ec2 terminate-instances \
    --instance-ids $INSTANCE_ID \
    --region $AWS_REGION \
    > /dev/null

echo "-------> Run new instance using custom ami"

# Run new instance using ami image created two steps before
INSTANCE_ID=$(aws ec2 run-instances \
	--image-id $AMI_ID \
	--count 1 --instance-type $INSTANCE_TYPE \
	--key-name $SSH_KEY_NAME \
	--security-group-ids $SG_ID \
    --user-data file://webconf.sh \
    --query 'Instances[0].{InstanceId:InstanceId}' \
    --output text \
    --region $AWS_REGION)


# Find out Public IP of created instance 
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-id $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].{PublicIpAddress:PublicIpAddress}' \
    --output text \
    --region $AWS_REGION)

# Tell user everithing is OK
echo -e "\e[32mApache web server is created!"
echo -e "NOTE: Web server may be unvailible for up to 5min from now."
echo -e "Use following link to see it works:\n\e[0m"

echo -e "\t\e[34mhttp://$PUBLIC_IP/\e[0m"


# Create destructor script to be able easily clean up everything
echo "#!/bin/bash
# Terminate instance
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $AWS_REGION > /dev/null

# Wait for instance statustates to be terminated
bash waitfor.sh -i $INSTANCE_ID -s terminated -d 5s

# Deregister image
aws ec2 deregister-image --image-id $AMI_ID --region $AWS_REGION

# Delete snapshot
aws ec2 delete-snapshot --snapshot-id $SNAP_ID --region $AWS_REGION

# Delete SSH Key
aws ec2 delete-key-pair --key-name $SSH_KEY_NAME --region $AWS_REGION
rm -f $SSH_KEY_FILE

# Delete Security Group
aws ec2 delete-security-group --group-id $SG_ID --region $AWS_REGION
" > "destructor.sh"