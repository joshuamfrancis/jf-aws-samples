#!/bin/bash

# Number of keys to generate (first argument, default: 1)
NUM_KEYS=${1:-1}
EMAIL="your_email@example.com"

for ((i=1; i<=NUM_KEYS; i++))
do
  KEY_NAME="id_rsa_$i"
  ssh-keygen -t rsa -b 4096 -C "$EMAIL" -f "$KEY_NAME" -N ""
  echo "Generated $KEY_NAME and ${KEY_NAME}.pub"
done
