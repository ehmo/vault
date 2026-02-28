#!/bin/bash
# Nuke all CloudKit records in the Vault container using Server-to-Server auth.
#
# Usage: ./scripts/nuke-cloudkit.sh [environment]
#   environment: "development" or "production" (default)

set -euo pipefail

KEY_ID="9910e44fd11569c0a69b5b28b3f2ad1c566b7b8c91a9e284b10ee2850996a6b8"
KEY_FILE="$(cd "$(dirname "$0")/.." && pwd)/.secrets/cloudkit-s2s.pem"
ENV="${1:-production}"
CONTAINER="iCloud.app.vaultaire.shared"
BASE="https://api.apple-cloudkit.com/database/1/${CONTAINER}/${ENV}/public"

DELETED=0
ERRORS=0

if [ ! -f "$KEY_FILE" ]; then
    echo "Error: Key file not found at $KEY_FILE"
    exit 1
fi

# Sign a CloudKit Server-to-Server request
# See: https://developer.apple.com/documentation/cloudkit/ckcontainer
ck_request() {
    local method="$1"
    local url="$2"
    local body="${3:-}"

    # Extract subpath: everything after /database/1/
    local subpath
    subpath=$(echo "$url" | sed 's|https://api.apple-cloudkit.com||')

    # ISO 8601 date
    local date
    date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Body hash (SHA256, base64)
    local body_hash
    if [ -n "$body" ]; then
        body_hash=$(echo -n "$body" | openssl dgst -sha256 -binary | base64)
    else
        body_hash=$(echo -n "" | openssl dgst -sha256 -binary | base64)
    fi

    # Message to sign: date:body_hash:subpath
    local message="${date}:${body_hash}:${subpath}"

    # Sign with ECDSA using the private key
    local signature
    signature=$(echo -n "$message" | openssl dgst -sha256 -sign "$KEY_FILE" | base64)

    # Make the request
    curl -s -X "$method" "$url" \
        -H "Content-Type: application/json" \
        -H "X-Apple-CloudKit-Request-KeyID: ${KEY_ID}" \
        -H "X-Apple-CloudKit-Request-ISO8601Date: ${date}" \
        -H "X-Apple-CloudKit-Request-SignatureV1: ${signature}" \
        ${body:+-d "$body"}
}

delete_all_records() {
    local record_type="$1"
    local filter_field="$2"

    echo ""
    echo "==> Querying ${record_type} records..."

    local page=0
    while true; do
        page=$((page + 1))

        local body
        body=$(cat <<EOF
{"query":{"recordType":"${record_type}","filterBy":[{"fieldName":"${filter_field}","comparator":"BEGINS_WITH","fieldValue":{"value":"","type":"STRING"}}]},"resultsLimit":200}
EOF
)

        local response
        response=$(ck_request POST "${BASE}/records/query" "$body")

        # Check for errors
        local server_error
        server_error=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'serverErrorCode' in data:
    print(f\"{data['serverErrorCode']}: {data.get('reason', 'unknown')}\")
else:
    print('')
" 2>/dev/null || echo "parse_error")

        if [ -n "$server_error" ]; then
            echo "   Query error: $server_error"
            ERRORS=$((ERRORS + 1))
            return
        fi

        # Extract record names + changeTags
        local records_json
        records_json=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
out = []
for r in data.get('records', []):
    out.append({'name': r['recordName'], 'tag': r.get('recordChangeTag', '')})
print(json.dumps(out))
" 2>/dev/null)

        local count
        count=$(echo "$records_json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)

        if [ "$count" -eq 0 ]; then
            echo "   No more ${record_type} records found."
            return
        fi

        echo "   Page ${page}: found ${count} records, deleting..."

        # Build batch delete operations with recordChangeTag
        local ops
        ops=$(echo "$records_json" | python3 -c "
import json, sys
records = json.load(sys.stdin)
ops = []
for r in records:
    op = {'operationType': 'delete', 'record': {'recordName': r['name'], 'recordType': '${record_type}', 'recordChangeTag': r['tag']}}
    ops.append(op)
print(json.dumps({'operations': ops}))
")

        local del_response
        del_response=$(ck_request POST "${BASE}/records/modify" "$ops")

        # Count results
        local counts
        counts=$(echo "$del_response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
records = data.get('records', [])
ok = sum(1 for r in records if r.get('deleted', False))
errs = [r for r in records if 'serverErrorCode' in r]
print(f'{ok} {len(errs)}')
" 2>/dev/null || echo "0 0")

        local del_ok="${counts%% *}"
        local del_err="${counts##* }"

        DELETED=$((DELETED + del_ok))
        ERRORS=$((ERRORS + del_err))

        echo "   Batch: ${del_ok} deleted, ${del_err} denied"
    done
}

echo "========================================"
echo "CloudKit Nuke Script (S2S Auth)"
echo "Container: ${CONTAINER}"
echo "Environment: ${ENV}"
echo "========================================"

# Public DB record types
delete_all_records "SharedVault" "shareVaultId"
delete_all_records "SharedVaultChunk" "vaultId"

echo ""
echo "========================================"
echo "Done! Deleted: ${DELETED}, Errors: ${ERRORS}"
echo ""
echo "Note: Private DB (VaultBackup/VaultBackupChunk) requires"
echo "user auth, not S2S. Use the in-app nuke button for those"
echo "(they should work since you own those records)."
echo "========================================"
