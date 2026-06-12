#!/bin/sh
set -e

echo "[1/6] Requesting Azure access token..."
TOKEN=$(curl -sf -X POST \
  "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \
  -d "grant_type=client_credentials&client_id=${AZURE_CLIENT_ID}&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$(cat $AZURE_FEDERATED_TOKEN_FILE)&scope=https://storage.azure.com/.default" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
echo "[1/6] Token acquired"

BLOB_URL="https://stformationecombackup.blob.core.windows.net/postgres-backups/dev/${BACKUP_FILENAME}"
echo "[2/6] Downloading ${BACKUP_FILENAME} from ${BLOB_URL}..."
HTTP_CODE=$(curl -s -o /tmp/${BACKUP_FILENAME} -w "%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "x-ms-version: 2020-04-08" \
  "${BLOB_URL}")
if [ "$HTTP_CODE" != "200" ]; then
  echo "[2/6] ERROR: download failed with HTTP $HTTP_CODE"
  cat /tmp/${BACKUP_FILENAME}
  exit 1
fi
echo "[2/6] Download complete ($(wc -c < /tmp/${BACKUP_FILENAME}) bytes)"

echo "[3/6] Extracting archive..."
tar xf /tmp/${BACKUP_FILENAME} -C /tmp
DUMP=$(tar tf /tmp/${BACKUP_FILENAME} | grep "\.sql\.gz$")
SHA_FILE=$(tar tf /tmp/${BACKUP_FILENAME} | grep "\.sha256$")
echo "[3/6] Extracted: $DUMP, $SHA_FILE"

echo "[4/6] Verifying checksum..."
EXPECTED=$(cat /tmp/${SHA_FILE} | tr -d "[:space:]")
ACTUAL=$(sha256sum /tmp/${DUMP} | cut -d " " -f 1)
if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "[4/6] ERROR: checksum mismatch — file is corrupted"
  echo "  Expected: $EXPECTED"
  echo "  Actual:   $ACTUAL"
  exit 1
fi
echo "[4/6] Checksum verified"

echo "[5/6] Decompressing dump..."
gzip -d /tmp/${DUMP}
SQL_FILE=/tmp/$(echo ${DUMP} | sed "s/.gz$//")
echo "[5/6] Decompressed ($(wc -c < ${SQL_FILE}) bytes)"

echo "[6/6] Restoring all databases to ${PG_HOST}..."
psql -h "$PG_HOST" -U "$PG_USER" -d postgres -f "${SQL_FILE}"
echo "[6/6] Restore complete"
