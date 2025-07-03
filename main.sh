#!/bin/bash
# 
# This script retrieves a VW access token, updates a GitHub Actions secret,
# fetches the vehicle state of charge, and updates Tibber accordingly.
#
# Required environment variables:
#   CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN,
#   TIBBER_EMAIL, TIBBER_PASSWORD, GH_PAT, VIN
#

set -euo pipefail
IFS=$'\n\t'

# --- Configuration ---

# GitHub Repository
REPO_OWNER="felicksLindgren"
REPO_NAME="cupra-tibber"

# Tibber
HOME_ID="3d7d05f5-d547-4db2-9499-0188825a7cfc"

# Vehicle
VEHICLE_ID="3901c6b5-76de-4e1c-90b3-1cfcbcbf5fef"

# Encryption script
ENCRYPT_SCRIPT="./scripts/encrypt.py"

# --- Helper Functions ---

log() {
  echo "[INFO] $1"
}

error_exit() {
  echo "[ERROR] $1"
  exit 1
}

github_api() {
  local method="$1"
  local url="$2"
  local data="${3:-}"
  curl -s -L -X "$method" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GH_PAT" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    ${data:+-d "$data"} \
    "$url"
}

# --- Validate Environment Variables ---

required_vars=(
  CLIENT_ID
  CLIENT_SECRET
  REFRESH_TOKEN
  TIBBER_EMAIL
  TIBBER_PASSWORD
  GH_PAT
  VIN
)

for var in "${required_vars[@]}"; do
  [ -z "${!var:-}" ] && error_exit "Environment variable $var is not set."
done

# --- VW Access Token Retrieval ---

get_vw_access_token() {
  curl -s -X POST "https://identity.vwgroup.io/oidc/v1/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=refresh_token" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "refresh_token=$REFRESH_TOKEN"
}

# --- Main Script ---

main() {
  log "Retrieving VW access token..."
  token_response=$(get_vw_access_token)
  vw_access_token=$(echo "$token_response" | jq -r '.access_token')
  new_refresh_token=$(echo "$token_response" | jq -r '.refresh_token')

  if [ -z "$vw_access_token" ] || [ "$vw_access_token" == "null" ]; then
    error_exit "Failed to retrieve VW access token."
  fi

  if [ -z "$new_refresh_token" ] || [ "$new_refresh_token" == "null" ]; then
    error_exit "Failed to retrieve new refresh token."
  fi

  log "Fetching GitHub repository public key..."
  github_pubkey_response=$(github_api GET \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/public-key")
  key_id=$(echo "$github_pubkey_response" | jq -r '.key_id')
  public_key=$(echo "$github_pubkey_response" | jq -r '.key')

  if [ -z "$key_id" ] || [ "$key_id" == "null" ]; then
    error_exit "Failed to retrieve GitHub public key."
  fi

  log "Encrypting the new refresh token..."
  encrypted_value=$(python3 "$ENCRYPT_SCRIPT" "$public_key" "$new_refresh_token" 2>/dev/null)

  if [ -z "$encrypted_value" ] || [ "$encrypted_value" == "null" ]; then
    error_exit "Failed to encrypt the refresh token."
  fi

  log "Updating GitHub Actions secret..."
  github_api PUT \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/REFRESH_TOKEN" \
    "{ \"encrypted_value\": \"$encrypted_value\", \"key_id\": \"$key_id\" }" >/dev/null

  log "Fetching vehicle state of charge..."
  state_of_charge=$(curl -s \
    "https://ola.prod.code.seat.cloud.vwgroup.com/v1/vehicles/$VIN/charging/status" \
    -H "authorization: Bearer $vw_access_token" \
    | jq -r '.battery.currentSocPercentage')

  if ! [[ "$state_of_charge" =~ ^[0-9]+$ ]]; then
    error_exit "Invalid state of charge: $state_of_charge"
  fi

  log "State of charge: $state_of_charge%"

  log "Authenticating with Tibber..."
  tibber_access_token=$(curl -s -X POST "https://app.tibber.com/login.credentials" \
    -H "Content-Type: application/json" \
    -d @- <<EOF | jq -r '.token'
{
  "email": "$TIBBER_EMAIL",
  "password": "$TIBBER_PASSWORD"
}
EOF
)

  if [ -z "$tibber_access_token" ] || [ "$tibber_access_token" == "null" ]; then
    error_exit "Failed to retrieve Tibber access token."
  fi

  log "Updating Tibber with the state of charge..."
  curl -s -X POST "https://app.tibber.com/v4/gql" \
    -H "Authorization: Bearer $tibber_access_token" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "query": "mutation setVehicleSettings { me { setVehicleSettings(id: \\"$VEHICLE_ID\\", homeId: \\"$HOME_ID\\", settings: [{ key: \\"offline.vehicle.batteryLevel\\", value: $state_of_charge }] ) { id } } }"
}
EOF

  log "Script completed successfully. State of charge updated in Tibber."
  exit 0
}

main
