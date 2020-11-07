#!/bin/bash

# Bucket name
BUCKET_NAME="itsu-lab-01-bucket"

# Region to use
AWS_REGION="us-east-1" 

# Create bucket command:
aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION

# Upload files
aws s3 sync website/ s3://$BUCKET_NAME/

# Enable website
aws s3api put-bucket-website --bucket $BUCKET_NAME --website-configuration file://website.json

# Setup bucket policy
aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://policy.json

# Crete destructor
echo "#!/bin/bash
aws s3 rb s3://$BUCKET_NAME --region $AWS_REGION --force
" > "destructor.sh"