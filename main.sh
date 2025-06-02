CLIENT_ID=$CLIENT_ID
CLIENT_SECRET=$CLIENT_SECRET
TOKEN_ENDPOINT=$TOKEN_ENDPOINT
REFRESH_TOKEN=$REFRESH_TOKEN

curl -s -X POST "$ACCESS_TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "refresh_token=$REFRESH_TOKEN" | jq



