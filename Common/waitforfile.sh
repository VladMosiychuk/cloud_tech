#!/bin/bash

while getopts ":i:h:f:" opt; do
  case $opt in
    i) KEY_FN="$OPTARG"
    ;;
    h) HOST="$OPTARG"
    ;;
    f) FILE="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

# Make sure all arguments is present
if [ -z "$KEY_FN" ] || [ -z "$HOST" ] || [ -z "$FILE" ]
then
    echo "Lack of parameters!"
    echo "You should provide ssh key file name (-i), host name (-h) and file name to wait for (-f)"
    exit 0
fi

# Add host to known host to prevent script interruption
ssh -o StrictHostKeyChecking=no ec2-user@$HOST

STATE=""
while [[ $STATE != "EXISTS" ]] 
do

    if ssh -i $KEY_FN ec2-user@$HOST "test -e $FILE"; then
        STATE="EXISTS"
        echo -e "State: \e[1;32mExists!\e[0m"
    else
        echo -e "State: \e[1;31mNot exists.\e[0m"
        sleep 5s
    fi
    
done
