#!/bin/bash

LAB_NAME="lab_05"
AWS_REGION="us-east-1"
TOPIC_NAME="${LAB_NAME}_topic"
ALARM_NAME="${LAB_NAME}_alarm"
ALARM_DESC="Alarm for ${LAB_NAME}"
NOTIFICATION_EMAIL="mosyka007@gmail.com"

# Import variables from LabWork_04
source ../LabWork_04/xporter.sh

# Extract dimmansion values using regular expression
LB_DIM_VAL=`echo $LAB_4_LB_ARN | grep -oP ".*:loadbalancer\/\K(.*)"`
TG_DIM_VAL=`echo $LAB_4_TG_ARN | grep -oP ".*:\K(.*)"`

# Create dimmension variables
LB_DIM="Name=LoadBalancer,Value=$LB_DIM_VAL"
TG_DIM="Name=TargetGroup,Value=$TG_DIM_VAL"


# Create topic

TOPIC_ARN=$(aws sns create-topic \
        --name $TOPIC_NAME \
        --query 'TopicArn' \
        --output text \
        --region $AWS_REGION)


# Create sns topic subscription

aws sns subscribe \
    --topic-arn $TOPIC_ARN \
    --protocol email \
    --notification-endpoint $NOTIFICATION_EMAIL \
    --query 'SubscriptionArn' \
    --output text \
    --region $AWS_REGION

# Create alarm metric

aws cloudwatch put-metric-alarm \
    --alarm-name $ALARM_NAME \
    --alarm-description "${ALARM_DESC}" \
    --namespace AWS/ApplicationELB \
    --dimensions $LB_DIM $TG_DIM \
    --period 300 \
    --evaluation-periods 1 \
    --threshold 2 \
    --comparison-operator LessThanThreshold \
    --metric-name HealthyHostCount \
    --alarm-actions $TOPIC_ARN \
    --statistic Minimum \
    --region $AWS_REGION


# Create destructor
echo "#!/bin/bash

# Delete alarm
aws cloudwatch delete-alarms --alarm-names $ALARM_NAME --region $AWS_REGION

# Delete sns topic
aws sns delete-topic --topic-arn "${TOPIC_ARN}" --region $AWS_REGION

" > "destructor.sh"