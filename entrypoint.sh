#!/bin/bash
set -euo pipefail

log_info() {
  echo "::notice::$1"
}

log_error() {
  echo "::error::$1"
}

die() {
  log_error "$1"
  exit 1
}

[[ -z "${INPUT_DEFECTDOJO_URL:-}" ]] && die "input defectdojo_url is required."
[[ -z "${INPUT_API_KEY:-}" ]]       && die "input api_key is required."
[[ -z "${INPUT_FILE:-}" ]]          && die "input file is required."
[[ -z "${INPUT_SCAN_TYPE:-}" ]]     && die "input scan_type is required."

DD_URL="${INPUT_DEFECTDOJO_URL%/}"
API_KEY="$INPUT_API_KEY"

PRODUCTS_ENDPOINT="/api/v2/products/"
ENGAGEMENTS_ENDPOINT="/api/v2/engagements/"
IMPORT_SCAN_ENDPOINT="/api/v2/import-scan/"

FILE_PATH="$INPUT_FILE"
if [[ "$FILE_PATH" != /* && -n "${GITHUB_WORKSPACE:-}" ]]; then
  FILE_PATH="$GITHUB_WORKSPACE/$FILE_PATH"
fi

if [[ ! -f "$FILE_PATH" ]]; then
  die "scan file not found at: $INPUT_FILE (resolved to $FILE_PATH)"
fi

CURL_CMD=(curl -s -S -H "Authorization: Token $API_KEY")

log_info "starting defectdojo action..."
log_info "target url: $DD_URL"
log_info "scan file: $FILE_PATH"

PRODUCT_ID=""

if [[ -n "${INPUT_PRODUCT_ID:-}" ]]; then
  log_info "using provided product id: $INPUT_PRODUCT_ID"

  HTTP_CODE=$("${CURL_CMD[@]}" -o /dev/null -w "%{http_code}" "$DD_URL${PRODUCTS_ENDPOINT}${INPUT_PRODUCT_ID}/")
  if [[ "$HTTP_CODE" != "200" ]]; then
    die "product id $INPUT_PRODUCT_ID not found (http $HTTP_CODE)."
  fi

  PRODUCT_ID="$INPUT_PRODUCT_ID"
elif [[ -n "${INPUT_PRODUCT_NAME:-}" ]]; then
  log_info "looking up product by name: $INPUT_PRODUCT_NAME"

  RESPONSE=$("${CURL_CMD[@]}" -G "$DD_URL${PRODUCTS_ENDPOINT}" --data-urlencode "name=$INPUT_PRODUCT_NAME")    
  if ! echo "$RESPONSE" | jq empty > /dev/null 2>&1; then
    die "invalid json response from defectdojo: $RESPONSE"
  fi

  COUNT=$(echo "$RESPONSE" | jq '.count // (.results | length)')
  if [[ "$COUNT" -gt 0 ]]; then
    PRODUCT_ID=$(echo "$RESPONSE" | jq '.results[0].id')
    log_info "found existing product id: $PRODUCT_ID"
  else
    log_info "product not found. creating new product: $INPUT_PRODUCT_NAME"
        
    J_NAME=$(jq -n --arg v "$INPUT_PRODUCT_NAME" '$v')
    J_DESC=$(jq -n --arg v "${INPUT_PRODUCT_DESCRIPTION:-Created by DefectDojo Action}" '$v')
    PROD_TYPE="${INPUT_PRODUCT_TYPE:-1}"
    PROD_JSON="{\"name\": $J_NAME, \"description\": $J_DESC, \"prod_type\": $PROD_TYPE}"

    CREATE_RES=$("${CURL_CMD[@]}" -X POST -H "Content-Type: application/json" \
        -d "$PROD_JSON" \
        "$DD_URL${PRODUCTS_ENDPOINT}")
        
    if echo "$CREATE_RES" | grep -q '"id":'; then
      PRODUCT_ID=$(echo "$CREATE_RES" | jq '.id')
      log_info "created new product id: $PRODUCT_ID"
    else
      die "failed to create product. response: $CREATE_RES"
    fi
  fi
else
  die "ensure either product_id or product_name is provided."
fi

echo "product_id=$PRODUCT_ID" >> "$GITHUB_OUTPUT"

ENGAGEMENT_ID=""

if [[ -n "${INPUT_ENGAGEMENT_ID:-}" ]]; then
  log_info "using provided engagement id: $INPUT_ENGAGEMENT_ID"

  HTTP_CODE=$("${CURL_CMD[@]}" -o /dev/null -w "%{http_code}" "$DD_URL${ENGAGEMENTS_ENDPOINT}${INPUT_ENGAGEMENT_ID}/")
  if [[ "$HTTP_CODE" != "200" ]]; then
    die "engagement id $INPUT_ENGAGEMENT_ID not found (HTTP $HTTP_CODE)."
  fi

  ENGAGEMENT_ID="$INPUT_ENGAGEMENT_ID"
elif [[ -n "${INPUT_ENGAGEMENT_NAME:-}" ]]; then
  log_info "creating new engagement: $INPUT_ENGAGEMENT_NAME"
  
  START_DATE=$(date -u +%Y-%m-%d)
  END_DATE=$(date -u +%Y-%m-%d)
  
  J_NAME=$(jq -n --arg v "$INPUT_ENGAGEMENT_NAME" '$v')
  J_START=$(jq -n --arg v "$START_DATE" '$v')
  J_END=$(jq -n --arg v "$END_DATE" '$v')
  
  JSON_BODY="{\"name\": $J_NAME, \"product\": $PRODUCT_ID, \"target_start\": $J_START, \"target_end\": $J_END, \"status\": \"In Progress\"}"
  CREATE_RES=$("${CURL_CMD[@]}" -X POST -H "Content-Type: application/json" \
      -d "$JSON_BODY" \
      "$DD_URL${ENGAGEMENTS_ENDPOINT}")

  if echo "$CREATE_RES" | grep -q '"id":'; then
    ENGAGEMENT_ID=$(echo "$CREATE_RES" | jq '.id')
    log_info "created new engagement id: $ENGAGEMENT_ID"
  else
    die "failed to create engagement. response: $CREATE_RES"
  fi
else
  die "ensure either engagement_id or engagement_name is provided."
fi

echo "engagement_id=$ENGAGEMENT_ID" >> "$GITHUB_OUTPUT"


log_info "importing scan [$INPUT_SCAN_TYPE]..."

ARGS=(
  -F "file=@$FILE_PATH"
  -F "scan_type=$INPUT_SCAN_TYPE"
  -F "engagement=$ENGAGEMENT_ID"
  -F "verified=${INPUT_VERIFIED:-true}"
  -F "active=${INPUT_ACTIVE:-true}"
  -F "minimum_severity=${INPUT_MINIMUM_SEVERITY:-Info}"
  -F "close_old_findings=${INPUT_CLOSE_OLD_FINDINGS:-false}"
)

if [[ -n "${INPUT_COMMIT_HASH:-}" ]]; then
  ARGS+=(-F "commit_hash=$INPUT_COMMIT_HASH")
fi

if [[ -n "${INPUT_BRANCH_TAG:-}" ]]; then
  ARGS+=(-F "branch_tag=$INPUT_BRANCH_TAG")
fi

if [[ -n "${INPUT_VERSION:-}" ]]; then
  ARGS+=(-F "version=$INPUT_VERSION")
fi

IMPORT_RES=$("${CURL_CMD[@]}" "${ARGS[@]}" "$DD_URL${IMPORT_SCAN_ENDPOINT}")

TEST_ID=$(echo "$IMPORT_RES" | jq -r '.test // empty')

if [[ -n "$TEST_ID" && "$TEST_ID" != "null" ]]; then
  log_info "scan imported successfully. test id: $TEST_ID"
  echo "test_id=$TEST_ID" >> "$GITHUB_OUTPUT"
    
  {
    echo "response<<EOF"
    echo "$IMPORT_RES"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
else
  ERR_MSG=$(echo "$IMPORT_RES" | jq -r '.error // .detail // "Unknown error"')
  die "detailed error: $ERR_MSG | raw: $IMPORT_RES"
fi

log_info "action completed successfully."
