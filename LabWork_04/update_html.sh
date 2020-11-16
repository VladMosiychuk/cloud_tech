#!/bin/bash

INDEX_FN="/var/www/html/index.html"

# Remove index file
rm -f $INDEX_FN

# Create new index file
INSTANCE_ID=$(cat /var/lib/cloud/data/instance-id)
echo "<h1>It is instance $INSTANCE_ID</h1>" > $INDEX_FN