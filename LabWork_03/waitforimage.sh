#!/bin/bash

while getopts ":i:s:d:" opt; do
  case $opt in
    i) IMAGE_ID="$OPTARG"
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
if [ -z "$TARGET_STATE" ] || [ -z "$IMAGE_ID" ] || [ -z "$DELAY" ]
then
    echo "Lack of parameters!"
    echo "You should provide target state (-s), image id (-i) and delay between checks (-d)"
    exit 0
fi

TATE=''
while [[ $STATE != $TARGET_STATE ]] 
do

    STATE=$(aws ec2 describe-images \
    --image-ids $IMAGE_ID  \
    --query 'Images[0].State' \
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
