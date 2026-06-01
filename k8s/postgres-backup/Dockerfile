FROM alpine:3.20
RUN apk add --no-cache postgresql16-client curl
RUN printf '#!/bin/sh\n\
set -e\n\
FILENAME=$(date +%%Y%%m%%d-%%H%%M%%S).sql.gz\n\
echo "[1/3] Dumping database..."\n\
pg_dump -h "$PG_HOST" -U "$PG_USER" -d "$PG_DATABASE" | gzip > /tmp/$FILENAME\n\
echo "[1/3] Dump complete ($(wc -c < /tmp/$FILENAME) bytes)"\n\
echo "[2/3] Requesting Azure access token..."\n\
TOKEN=$(curl -sf -X POST \\\n\
  "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \\\n\
  -d "grant_type=client_credentials&client_id=${AZURE_CLIENT_ID}&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$(cat $AZURE_FEDERATED_TOKEN_FILE)&scope=https://storage.azure.com/.default" \\\n\
  | sed -n '"'"'s/.*"access_token":"\\([^"]*\\)".*/\\1/p'"'"')\n\
echo "[2/3] Token acquired"\n\
echo "[3/3] Uploading $FILENAME to Azure Blob Storage..."\n\
curl -sf -X PUT \\\n\
  -H "Authorization: Bearer ${TOKEN}" \\\n\
  -H "x-ms-blob-type: BlockBlob" \\\n\
  -H "x-ms-version: 2020-04-08" \\\n\
  -H "Content-Type: application/gzip" \\\n\
  --data-binary @/tmp/$FILENAME \\\n\
  "https://stformationecombackup.blob.core.windows.net/postgres-backups/dev/${FILENAME}"\n\
echo "[3/3] Upload complete"\n' > /backup.sh && chmod +x /backup.sh
ENTRYPOINT ["/backup.sh"]
