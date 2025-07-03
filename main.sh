#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# --- Configuration ---
REPO_OWNER="felicksLindgren"
REPO_NAME="cupra-tibber"
HOME_ID="3d7d05f5-d547-4db2-9499-0188825a7cfc"
VEHICLE_ID="3901c6b5-76de-4e1c-90b3-1cfcbcbf5fef"

# --- Helper Functions ---
error_exit() {
  echo "Error: $1"
  exit 1
}

# --- Validate Environment Variables ---
required_vars=(CLIENT_ID CLIENT_SECRET REFRESH_TOKEN TIBBER_EMAIL TIBBER_PASSWORD GH_PAT VIN)
for var in "${required_vars[@]}"; do
  [ -z "${!var:-}" ] && error_exit "Environment variable $var is not set."
done

# --- VW Access Token Retrieval ---
get_vw_access_token() {
  local response
  response=$(curl -s -X POST https://identity.vwgroup.io/oidc/v1/token \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=refresh_token" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "refresh_token=$REFRESH_TOKEN")
  echo "$response"
}

# --- Main Script ---
main() {
  # 1. Get VW access token
  token_response=$(get_vw_access_token)
  vw_access_token=$(echo "$token_response" | jq -r '.access_token')
  new_refresh_token=$(echo "$token_response" | jq -r '.refresh_token')
  [ -z "$vw_access_token" ] || [ "$vw_access_token" == "null" ] && error_exit "Failed to retrieve VW access token."
  [ -z "$new_refresh_token" ] || [ "$new_refresh_token" == "null" ] && error_exit "Failed to retrieve new refresh token."

  # 2. Retrieve GitHub public key
  github_pubkey_response=$(curl -s -L \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GH_PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/public-key")
  key_id=$(echo "$github_pubkey_response" | jq -r '.key_id')
  public_key=$(echo "$github_pubkey_response" | jq -r '.key')
  [ -z "$key_id" ] || [ "$key_id" == "null" ] && error_exit "Failed to retrieve GitHub public key."

  # 3. Encrypt and update GitHub secret
  encrypted_value=$(python3 scripts/encrypt.py "$public_key" "$new_refresh_token" 2>/dev/null)
  [ -z "$encrypted_value" ] || [ "$encrypted_value" == "null" ] && error_exit "Failed to encrypt the refresh token."
  curl -s -L -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GH_PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/REFRESH_TOKEN" \
    -d "{ \"encrypted_value\": \"$encrypted_value\", \"key_id\": \"$key_id\" }" >/dev/null

  # 4. Fetch state of charge from Cupra API
  state_of_charge=$(curl -s "https://ola.prod.code.seat.cloud.vwgroup.com/v1/vehicles/$VIN/charging/status" \
    -H "authorization: Bearer $vw_access_token" | jq -r '.battery.currentSocPercentage')
  [ "$state_of_charge" == "null" ] && error_exit "Failed to retrieve state of charge."
  echo "State of charge: $state_of_charge%"

  # 5. Authenticate with Tibber
  tibber_access_token=$(curl -s -X POST https://app.tibber.com/login.credentials \
    --header 'content-type: application/json' \
    --data "{\"email\": \"$TIBBER_EMAIL\", \"password\": \"$TIBBER_PASSWORD\"}" | jq -r '.token')
  [ "$tibber_access_token" == "null" ] && error_exit "Failed to retrieve Tibber access token."

  # 6. Update Tibber with state of charge
  curl -s -X POST https://app.tibber.com/v4/gql \
    -H "authorization: Bearer $tibber_access_token" \
    -H "content-type: application/json" \
    --data @- <<EOF
{
  "query": "mutation setVehicleSettings { me { setVehicleSettings(id: \"$VEHICLE_ID\", homeId: \"$HOME_ID\", settings: [{ key: \"offline.vehicle.batteryLevel\", value: $state_of_charge }] ) { id } } }"
}
EOF

  echo "Script completed successfully. State of charge updated in Tibber."
}

main
