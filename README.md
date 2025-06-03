# Cupra Tibber Sync

This repository contains a Bash script and a GitHub Actions workflow to automate fetching the state of charge (SoC) from a Cupra vehicle (via VW Group API) and sending it to Tibber.

## Table of Contents

- [Contents](#contents)
  - [main.sh](#mainsh)
  - [.github/workflows/scheduled.yml](#githubworkflowsscheduledyml)
- [Setup](#setup)
- [Curl Requests Explained](#curl-requests-explained)
  - [1. Obtain a New VW Group Access Token](#1-obtain-a-new-vw-group-access-token)
  - [2. Fetch State of Charge from Cupra API](#2-fetch-state-of-charge-from-cupra-api)
  - [3. Authenticate with Tibber](#3-authenticate-with-tibber)
  - [4. Update Battery Level in Tibber](#4-update-battery-level-in-tibber)
  - [5. (Planned) Update the GitHub Secret `REFRESH_TOKEN`](#5-update-the-github-secret-refresh_token)
- [Obtaining a Refresh Token](#obtaining-a-refresh-token)
- [Security](#security)

## Contents

### `main.sh`

- **Purpose:**  
  Authenticates with the VW Group API using OAuth2 refresh tokens, fetches the current state of charge for a specific Cupra vehicle, then logs in to Tibber and updates the battery level via Tibber's API.
- **Secrets:**  
  All credentials and tokens are securely loaded from environment variables, which should be set as [GitHub Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets).
- **Steps:**
  1. Refreshes the VW Group access token using a refresh token.
  2. Fetches the vehicle's current state of charge.
  3. Logs in to Tibber using provided credentials.
  4. Sends the state of charge to Tibber via a GraphQL mutation.

### `.github/workflows/scheduled.yml`

- **Purpose:**  
  Schedules the execution of `main.sh` using GitHub Actions.
- **Triggers:**
  - **Scheduled:** Runs automatically every hour (`cron: '0 * * * *'`).
  - **Push:** Runs when `main.sh` or the workflow file itself is changed.
- **Secrets:**  
  All required secrets are injected as environment variables from the repository's GitHub Secrets.
- **How it works:**  
  The workflow checks out the repository and runs `main.sh` in a secure environment.

## Setup

1. **Add required secrets** to your repository:
   - `CLIENT_ID`
   - `CLIENT_SECRET`
   - `REFRESH_TOKEN`
   - `TOKEN_ENDPOINT`
   - `TIBBER_EMAIL`
   - `TIBBER_PASSWORD`

2. **Modify vehicle and home IDs** in `main.sh` if needed.

3. **Workflow runs automatically** every hour and on relevant file changes.

## Curl Requests Explained

The `main.sh` script uses several `curl` commands to interact with external APIs. Here’s a detailed explanation of each:

### 1. Obtain a New VW Group Access Token

```bash
response=$(curl -s -X POST "$TOKEN_ENDPOINT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "refresh_token=$REFRESH_TOKEN")
```

**Purpose:**  
This request exchanges your long-lived `refresh_token` for a new, short-lived access token from the VW Group OAuth2 server.

- **Endpoint:** The VW Group OAuth2 token endpoint.
- **Headers:** Sets the content type for form data.
- **Data:** Supplies the client credentials and refresh token.
- **Response:** Contains a new access token (and possibly a new refresh token).

---

### 2. Fetch State of Charge from Cupra API

```bash
state_of_charge=$(curl -s https://ola.prod.code.seat.cloud.vwgroup.com/v1/vehicles/$VIN/charging/status \
  -H "authorization: Bearer $vw_access_token" | jq -r '.battery.currentSocPercentage')
```

**Purpose:**  
Retrieves the current battery state of charge (SoC) for your Cupra vehicle.

- **Endpoint:** The Cupra vehicle status API.
- **Headers:** Uses the access token from the previous step for authorization.
- **Response:** Returns the current SoC as a percentage.

---

### 3. Authenticate with Tibber

```bash
tibber_access_token=$(curl -s -X POST https://app.tibber.com/login.credentials \
  --header 'content-type: application/json' \
  --data '{
    "email": "'"$TIBBER_EMAIL"'",
    "password": "'"$TIBBER_PASSWORD"'"
  }' | jq -r '.token')
```

**Purpose:**  
Logs in to Tibber using your credentials to obtain an access token for further API requests.

- **Endpoint:** Tibber login endpoint.
- **Headers:** Sets content type to JSON.
- **Data:** Supplies your Tibber email and password.
- **Response:** Returns a Tibber access token.

---

### 4. Update Battery Level in Tibber

```bash
curl -s -X POST https://app.tibber.com/v4/gql \
  -H "authorization: Bearer $tibber_access_token" \
  -H "content-type: application/json" \
  --data "{
    \"query\": \"mutation setVehicleSettings { me { setVehicleSettings(id: \\\"$VEHICLE_ID\\\", homeId: \\\"$HOME_ID\\\", settings: [{ key: \\\"offline.vehicle.batteryLevel\\\", value: $state_of_charge }] ) { id } } }\"
  }"
```

**Purpose:**  
Sends the latest state of charge to Tibber using a GraphQL mutation.

- **Endpoint:** Tibber GraphQL API.
- **Headers:** Uses the Tibber access token for authorization and sets content type to JSON.
- **Data:** Sends a mutation to update the vehicle’s battery level.
- **Response:** Confirms the update.

---

### 5. Update the GitHub Secret `REFRESH_TOKEN`

```bash
# Get public key for secrets
pubkey_response=$(curl -s -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GH_PAT" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/public-key")

key_id=$(echo "$pubkey_response" | jq -r '.key_id')
public_key=$(echo "$pubkey_response" | jq -r '.key')

# Encrypt the new refresh token using the public key
encrypted_value=$(python3 scripts/encrypt.py "$public_key" "$new_refresh_token")

# Update the secret in the repository
curl -s -L -X PUT \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GH_PAT" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/REFRESH_TOKEN" \
  -d "{ \"encrypted_value\": \"$encrypted_value\", \"key_id\": \"$key_id\" }"
```

**Purpose:**  
Fetches the repository’s public key, encrypts the new `REFRESH_TOKEN` using [libsodium sealed box encryption](https://doc.libsodium.org/public-key_cryptography/sealed_boxes) (via the Python script `scripts/encrypt.py`), and updates the secret in the GitHub repository using the REST API.

- **Encryption:**  
  The Python script uses [PyNaCl](https://pynacl.readthedocs.io/en/stable/) to perform the required encryption.  
  Make sure `pynacl` is installed (`pip install pynacl`).

- **Endpoint:** GitHub REST API for repository secrets.
- **Headers:** Uses a Personal Access Token for authentication.
- **Response:** Updates the secret value in the repository.

---

Each `curl` command is essential for securely automating the data flow between your Cupra vehicle, Tibber, and GitHub Actions.

## Obtaining a Refresh Token

- The easiest way to obtain a `refresh_token` is by using an API client like **Postman** or **Bruno**.  
  These applications allow you to perform the OAuth2 authorization code flow using your browser, making it straightforward to retrieve the refresh token.
- This is a one-time setup:  
  Once you have a `refresh_token`, it is valid for approximately 4000 hours (~5.5 months).
- The script will automatically use the refresh token to obtain new access tokens on each run.

## Security

- Secrets are never exposed in logs or code.
- GitHub Actions does **not** expose secrets to workflows triggered by pull requests from forks.
