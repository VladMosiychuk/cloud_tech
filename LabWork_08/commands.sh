#!/bin/bash

# Region to use
AWS_REGION="us-east-1" 

# Source bucket
SOURCE_BUCKET="lab-08-src"

# Resized bucket
RESIZED_BUCKET="${SOURCE_BUCKET}-resized"

# Create source bucket
aws s3 mb s3://$SOURCE_BUCKET --region $AWS_REGION

# Create resized bucket
aws s3 mb s3://$RESIZED_BUCKET --region $AWS_REGION

# Upload files from images folder to source bucket
aws s3 sync images/ s3://$SOURCE_BUCKET/


# Change directory to lambda
cd lambda

# Install sharp library for image resizing
npm install sharp

# Create a deployment package with the function code and dependencies.
zip -r function.zip .

# Create lambda function
aws lambda create-function --function-name CreateThumbnail \
    --zip-file fileb://function.zip --handler index.handler --runtime nodejs12.x \
    --timeout 10 --memory-size 1024 \
    --role $ROLE_ARN \
    --region $AWS_REGION \
    --cli-binary-format raw-in-base64-out


# Remove created files
rm -rf node_modules/
rm function.zip
rm package-lock.json

# Get out of lambda directory
cd ..

# Invoke CreateThumbnail function with data from input.json
aws lambda invoke --function-name CreateThumbnail --invocation-type RequestResponse \
    --payload file://input.json output.json \
    --cli-binary-format raw-in-base64-out \
    --region $AWS_REGION

# Remove output.json
rm -f output.json

# Configure Amazon S3 to publish events

# Add Amazon S3 permissions to trigger lambda function.
aws lambda add-permission --function-name CreateThumbnail --principal s3.amazonaws.com \
    --statement-id s3invoke --action "lambda:InvokeFunction" \
    --source-arn arn:aws:s3:::lab-08-src \
    --source-account $ACCOUNT_ID \
    --region $AWS_REGION

# Add notification configuration to source bucket.
# Here is tuturial: https://docs.aws.amazon.com/lambda/latest/dg/with-s3-example.html
# Do it by hand...


# Destructor
echo "#!/bin/bash
aws lambda delete-function --function-name CreateThumbnail --region $AWS_REGION
aws s3 rb s3://$SOURCE_BUCKET --region $AWS_REGION --force
aws s3 rb s3://$RESIZED_BUCKET --region $AWS_REGION --force
" > "destructor.sh"