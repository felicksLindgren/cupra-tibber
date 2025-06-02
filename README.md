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

## Security

- Secrets are never exposed in logs or code.
- GitHub Actions does **not** expose secrets to workflows triggered by pull requests from forks.
