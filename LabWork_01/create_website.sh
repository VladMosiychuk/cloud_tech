# Create bucket command:
aws s3 mb s3://itsu-lab-01-bucket --region eu-central-1

# Upload files
aws s3 sync website/ s3://itsu-lab-01-bucket/

# Enable website
aws s3api put-bucket-website --bucket itsu-lab-01-bucket --website-configuration file://website.json

# Setup bucket policy
aws s3api put-bucket-policy --bucket itsu-lab-01-bucket --policy file://policy.json