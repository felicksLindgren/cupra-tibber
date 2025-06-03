#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

REPO_OWNER="felicksLindgren"
REPO_NAME="cupra-tibber"
HOME_ID="3d7d05f5-d547-4db2-9499-0188825a7cfc"
VEHICLE_ID="3901c6b5-76de-4e1c-90b3-1cfcbcbf5fef"

# --- Check required environment variables ---
if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] || [ -z "$REFRESH_TOKEN" ] || [ -z "$TIBBER_EMAIL" ] || [ -z "$TIBBER_PASSWORD" ]; then
  echo "One or more required environment variables are not set."
  exit 1
fi

# --- Request a new access token using the refresh token ---
token_response=$(curl -s -X POST https://identity.vwgroup.io/oidc/v1/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "refresh_token=$REFRESH_TOKEN")

vw_access_token=$(echo "$token_response" | jq -r '.access_token')
new_refresh_token=$(echo "$token_response" | jq -r '.refresh_token')

if [ -z "$vw_access_token" ] || [ "$vw_access_token" == "null" ]; then
  echo "Failed to retrieve VW access token."
  exit 1
fi
if [ -z "$new_refresh_token" ] || [ "$new_refresh_token" == "null" ]; then
  echo "Failed to retrieve new refresh token."
  exit 1
fi

# --- Retrieve GitHub public key for secrets ---
github_pubkey_response=$(curl -s -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GH_PAT" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/public-key")

key_id=$(echo "$github_pubkey_response" | jq -r '.key_id')
public_key=$(echo "$github_pubkey_response" | jq -r '.key')

if [ -z "$key_id" ] || [ "$key_id" == "null" ] || [ -z "$public_key" ] || [ "$public_key" == "null" ]; then
  echo "Failed to retrieve GitHub public key."
  exit 1
fi

# --- Encrypt the new refresh token ---
encrypted_value=$(python3 scripts/encrypt.py "$public_key" "$new_refresh_token" 2>/dev/null)
if [ -z "$encrypted_value" ] || [ "$encrypted_value" == "null" ]; then
  echo "Failed to encrypt the refresh token."
  exit 1
fi

# --- Update the secret in the GitHub repository ---
echo "Updating GitHub secret REFRESH_TOKEN..."
update_secret_response=$(curl -s -L -X PUT \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GH_PAT" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/REFRESH_TOKEN" \
  -d "{ \"encrypted_value\": \"$encrypted_value\", \"key_id\": \"$key_id\" }")

if [ -z "$update_secret_response" ]; then
  echo "Refresh token updated successfully in GitHub repository."
else
  echo "Failed to update refresh token in GitHub repository. Response: $update_secret_response"
  exit 1
fi

# --- Fetch state of charge from Cupra API ---
state_of_charge=$(curl -s https://ola.prod.code.seat.cloud.vwgroup.com/v1/vehicles/$VIN/charging/status \
  -H "authorization: Bearer $vw_access_token" | jq -r '.battery.currentSocPercentage')

if [ "$state_of_charge" == "null" ]; then
  echo "Failed to retrieve state of charge."
  exit 1
fi
echo "State of charge: $state_of_charge%"

# --- Authenticate with Tibber ---
tibber_access_token=$(curl -s -X POST https://app.tibber.com/login.credentials \
  --header 'content-type: application/json' \
  --data '{
    "email": "'"$TIBBER_EMAIL"'",
    "password": "'"$TIBBER_PASSWORD"'"
  }' | jq -r '.token')

if [ "$tibber_access_token" == "null" ]; then
  echo "Failed to retrieve Tibber access token."
  exit 1
fi
echo "Tibber access token retrieved successfully."

# --- Update Tibber with state of charge ---
curl -s -X POST https://app.tibber.com/v4/gql \
  -H "authorization: Bearer $tibber_access_token" \
  -H "content-type: application/json" \
  --data "{
    \"query\": \"mutation setVehicleSettings { me { setVehicleSettings(id: \\\"$VEHICLE_ID\\\", homeId: \\\"$HOME_ID\\\", settings: [{ key: \\\"offline.vehicle.batteryLevel\\\", value: $state_of_charge }] ) { id } } }\"
  }"
  
echo "Script completed successfully. State of charge updated in Tibber."
