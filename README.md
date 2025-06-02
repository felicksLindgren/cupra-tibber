# Cupra Tibber Sync

This repository contains a Bash script and a GitHub Actions workflow to automate fetching the state of charge (SoC) from a Cupra vehicle (via VW Group API) and sending it to Tibber.

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

## Obtaining a Refresh Token

- The easiest way to obtain a `refresh_token` is by using an API client like **Postman** or **Bruno**.  
  These applications allow you to perform the OAuth2 authorization code flow using your browser, making it straightforward to retrieve the refresh token.
- This is a one-time setup:  
  Once you have a `refresh_token`, it is valid for approximately 4000 hours (~5.5 months).
- The script will automatically use the refresh token to obtain new access tokens on each run.

## Security

- Secrets are never exposed in logs or code.
- GitHub Actions does **not** expose secrets to workflows triggered by pull requests from forks.

## Limitations

- The refresh token is valid for approximately 4000 hours (~5.5 months).  
  After this period, you will need to obtain a new refresh token.

This will be fixed in the future by implementing the following refresh token rotation mechanism.
The script will automatically update the GitHub secret `REFRESH_TOKEN` with the new refresh token obtained from the VW Group API, ensuring that the script continues to function without manual intervention.

```bash
# filepath: [main.sh](http://_vscodecontentref_/0)
# ...existing code...

# Extract new refresh_token if present in the response
new_refresh_token=$(echo "$response" | jq -r '.refresh_token')

if [ "$new_refresh_token" != "null" ] && [ -n "$GH_PAT" ]; then
  echo "Updating GitHub secret REFRESH_TOKEN..."

  # Get repo info (set these as env vars or hardcode)
  REPO_OWNER="felixlindgren"
  REPO_NAME="cupra-tibber"

  # Get public key for secrets
  pubkey_response=$(curl -s -H "Authorization: token $GH_PAT" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/public-key")

  key_id=$(echo "$pubkey_response" | jq -r '.key_id')
  public_key=$(echo "$pubkey_response" | jq -r '.key')

  # Encrypt the new refresh token
  encrypted_value=$(echo -n "$new_refresh_token" | \
    openssl rsautl -encrypt -pubin -inkey <(echo "$public_key" | base64 -d) | base64 | tr -d '\n')

  # Update the secret
  curl -s -X PUT -H "Authorization: token $GH_PAT" \
    -H "Content-Type: application/json" \
    -d "{\"encrypted_value\":\"$encrypted_value\",\"key_id\":\"$key_id\"}" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/secrets/REFRESH_TOKEN"
fi
# ...existing code...
```
