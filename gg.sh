#!/bin/bash

gURL=$1
newFilename=$2  # Tham số thứ hai cho tên file mới

# Match more than 26 word characters
ggID=$(echo "$gURL" | egrep -o '(\w|-){26,}')

# Check if ID was extracted
if [ -z "$ggID" ]; then
  echo "Error: Unable to extract Google Drive ID from the URL."
  exit 1
fi

ggURL='https://drive.google.com/uc?export=download'

# Download file
tempFilename=$(mktemp)
wget --load-cookies /tmp/gcokie \
     --no-check-certificate \
     "${ggURL}&id=${ggID}" \
     -O "${tempFilename}" \
     || { echo "Error: Download failed."; exit 1; }

# Check if the download was successful
if [ $? -eq 0 ]; then
  echo "Download completed successfully."

  # Rename the file
  if [ -z "$newFilename" ]; then
    echo "Error: No new filename specified."
    exit 1
  fi

  mv "$tempFilename" "$newFilename"
  echo "File renamed to $newFilename."
else
  echo "Error: Download failed."
  exit 1
fi
