#!/bin/bash

# Load secrets from environment variables
CLIENT_ID="$CLIENT_ID"
CLIENT_SECRET="$CLIENT_SECRET"
TOKEN_ENDPOINT="$TOKEN_ENDPOINT"
REFRESH_TOKEN="$REFRESH_TOKEN"

# Request a new access token using the refresh token
response=$(curl -s -X POST "$TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "refresh_token=$REFRESH_TOKEN")

access_token=$(echo "$response" | jq -r '.access_token')

if [ "$access_token" == "null" ]; then
  echo "Failed to refresh access token. Response: $response"
  exit 1
else
  echo "Access token refreshed successfully."
fi

# Fetch state of charge from Cupra API
state_of_charge=$(curl -s https://ola.prod.code.seat.cloud.vwgroup.com/v1/vehicles/REDACTED/charging/status \
  -H "authorization: Bearer $access_token" | jq -r '.battery.currentSocPercentage')

if [ "$state_of_charge" == "null" ]; then
  echo "Failed to retrieve state of charge."
  exit 1
else
  echo "State of charge: $state_of_charge%"
fi