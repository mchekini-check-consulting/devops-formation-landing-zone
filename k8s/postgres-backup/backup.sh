#!/bin/sh
set -e

FILENAME=$(date +%Y%m%d-%H%M%S).sql.gz

echo "[1/3] Dumping database..."
pg_dump -h "$PG_HOST" -U "$PG_USER" -d "$PG_DATABASE" | gzip > /tmp/$FILENAME
echo "[1/3] Dump complete ($(wc -c < /tmp/$FILENAME) bytes)"

echo "[2/3] Requesting Azure access token..."
TOKEN=$(curl -sf -X POST \
  "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \
  -d "grant_type=client_credentials&client_id=${AZURE_CLIENT_ID}&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$(cat $AZURE_FEDERATED_TOKEN_FILE)&scope=https://storage.azure.com/.default" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
echo "[2/3] Token acquired"

echo "[3/3] Uploading $FILENAME to Azure Blob Storage..."
curl -sf -X PUT \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "x-ms-blob-type: BlockBlob" \
  -H "x-ms-version: 2020-04-08" \
  -H "Content-Type: application/gzip" \
  --data-binary @/tmp/$FILENAME \
  "https://stformationecombackup.blob.core.windows.net/postgres-backups/dev/${FILENAME}"
echo "[3/3] Upload complete"
