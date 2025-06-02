#!/bin/bash

# Load secrets from environment variables
CLIENT_ID="$CLIENT_ID"
CLIENT_SECRET="$CLIENT_SECRET"
TOKEN_ENDPOINT="$TOKEN_ENDPOINT"
REFRESH_TOKEN="$REFRESH_TOKEN"
TIBBER_EMAIL="$TIBBER_EMAIL"
TIBBER_PASSWORD="$TIBBER_PASSWORD"

# Request a new access token using the refresh token
response=$(curl -s -X POST "$TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "refresh_token=$REFRESH_TOKEN")

vw_access_token=$(echo "$response" | jq -r '.access_token')

if [ "$vw_access_token" == "null" ]; then
  echo "Failed to refresh access token. Response: $response"
  exit 1
else
  echo "Access token refreshed successfully."
fi

# Fetch state of charge from Cupra API
state_of_charge=$(curl -s https://ola.prod.code.seat.cloud.vwgroup.com/v1/vehicles/REDACTED/charging/status \
  -H "authorization: Bearer $vw_access_token" | jq -r '.battery.currentSocPercentage')

if [ "$state_of_charge" == "null" ]; then
  echo "Failed to retrieve state of charge."
  exit 1
else
  echo "State of charge: $state_of_charge%"
fi

tibber_access_token=$(curl -s -X POST https://app.tibber.com/login.credentials \
  --header 'content-type: application/json' \
  --data '{
    "email": "'"$TIBBER_EMAIL"'",
    "password": "'"$TIBBER_PASSWORD"'"
  }' | jq -r '.token')

if [ "$tibber_access_token" == "null" ]; then
  echo "Failed to retrieve Tibber access token."
  exit 1
else
  echo "Tibber access token retrieved successfully."
fi

curl -s -X POST https://app.tibber.com/v4/gql \
  -H "authorization: Bearer $tibber_access_token" \
  -H "content-type: application/json" \
  --data "{
    \"query\": \"mutation setVehicleSettings { me { setVehicleSettings(id: \\\"3901c6b5-76de-4e1c-90b3-1cfcbcbf5fef\\\", homeId: \\\"3d7d05f5-d547-4db2-9499-0188825a7cfc\\\", settings: [{ key: \\\"offline.vehicle.batteryLevel\\\", value: $state_of_charge }] ) { id } } }\"
  }"