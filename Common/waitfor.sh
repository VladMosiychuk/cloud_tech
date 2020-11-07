#!/bin/bash

while getopts ":i:s:d:" opt; do
  case $opt in
    i) INSTANCE_ID="$OPTARG"
    ;;
    s) TARGET_STATE="$OPTARG"
    ;;
    d) DELAY="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

# Make sure all arguments is present
if [ -z "$TARGET_STATE" ] || [ -z "$INSTANCE_ID" ] || [ -z "$DELAY" ]
then
    echo "Lack of parameters!"
    echo "You should provide target state (-s), instance id (-i) and delay between checks (-d)"
    exit 0
fi


STATE=''
while [[ $STATE != $TARGET_STATE ]] 
do

    STATE=$(aws ec2 describe-instances \
    --instance-id $INSTANCE_ID  \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text \
    --region us-east-1)

    if [[ $STATE != $TARGET_STATE ]] 
    then
        echo -e "State: \e[1;31m${STATE}\e[0m"
        sleep $DELAY
    else
        echo -e "State: \e[1;32m${STATE}\e[0m"
    fi
done