#!/bin/bash
# Sync VW vehicle battery level with Tibber
# Required env vars: CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN, TIBBER_EMAIL, TIBBER_PASSWORD, GH_PAT, VIN

set -e

# Configuration
REPO_OWNER="felicksLindgren"
REPO_NAME="cupra-tibber"
HOME_ID="3d7d05f5-d547-4db2-9499-0188825a7cfc"
VEHICLE_ID="3901c6b5-76de-4e1c-90b3-1cfcbcbf5fef"

# Check required environment variables
for var in CLIENT_ID CLIENT_SECRET REFRESH_TOKEN TIBBER_EMAIL TIBBER_PASSWORD GH_PAT VIN; do
  [ -z "${!var:-}" ] && { echo "Error: $var not set"; exit 1; }
done

echo "Getting VW access token..."
token_response=$(curl -s -X POST "https://identity.vwgroup.io/oidc/v1/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN")

vw_access_token=$(echo "$token_response" | jq -r '.access_token')
new_refresh_token=$(echo "$token_response" | jq -r '.refresh_token')

[ "$vw_access_token" = "null" ] && { echo "Failed to get VW token"; exit 1; }
[ "$new_refresh_token" = "null" ] && { echo "Failed to get new refresh token"; exit 1; }

echo "Updating GitHub secret with new refresh token..."
github_key=$(curl -s -H "Authorization: Bearer $GH_PAT" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/public-key")

key_id=$(echo "$github_key" | jq -r '.key_id')
public_key=$(echo "$github_key" | jq -r '.key')

encrypted_value=$(python3 ./scripts/encrypt.py "$public_key" "$new_refresh_token" 2>/dev/null)
[ "$encrypted_value" = "null" ] && { echo "Failed to encrypt token"; exit 1; }

curl -s -X PUT -H "Authorization: Bearer $GH_PAT" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/REFRESH_TOKEN" \
  -d "{\"encrypted_value\":\"$encrypted_value\",\"key_id\":\"$key_id\"}" > /dev/null

echo "Getting vehicle battery level..."
state_of_charge=$(curl -s -H "authorization: Bearer $vw_access_token" \
  "https://ola.prod.code.seat.cloud.vwgroup.com/v1/vehicles/$VIN/charging/status" \
  | jq -r '.battery.currentSocPercentage')

[[ ! "$state_of_charge" =~ ^[0-9]+$ ]] && { echo "Invalid battery level: $state_of_charge"; exit 1; }
echo "Battery level: $state_of_charge%"

echo "Logging into Tibber..."
tibber_token=$(curl -s -X POST "https://app.tibber.com/login.credentials" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$TIBBER_EMAIL\",\"password\":\"$TIBBER_PASSWORD\"}" \
  | jq -r '.token')

[ "$tibber_token" = "null" ] && { echo "Failed to login to Tibber"; exit 1; }

echo "Updating Tibber with battery level..."
curl -s -X POST "https://app.tibber.com/v4/gql" \
  -H "Authorization: Bearer $tibber_token" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"mutation{me{setVehicleSettings(id:\\\"$VEHICLE_ID\\\",homeId:\\\"$HOME_ID\\\",settings:[{key:\\\"offline.vehicle.batteryLevel\\\",value:$state_of_charge}]){id}}}\"}" > /dev/null

echo "Done! Battery level synced successfully."
