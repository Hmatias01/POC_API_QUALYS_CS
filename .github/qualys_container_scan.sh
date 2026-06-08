#!/usr/bin/env bash
set -euo pipefail

# Variáveis
IMAGE_NAME="poc-api-matias"
IMAGE_TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
POLICY_TAGS="POC_API_MATIAS"
OUTPUT_DIR="qualys-results"

# Download do Scanner
curl -fsSL "https://www.qualys.com/qscanner/download/latest/download_qscanner.sh" -o download_qscanner.sh
chmod +x download_qscanner.sh && ./download_qscanner.sh
QSCANNER_PATH="$(find . -type f -name qscanner | head -n 1)"
chmod +x "$QSCANNER_PATH"

# Execução do Scan
set +e
"$QSCANNER_PATH" image "$FULL_IMAGE" \
  --pod US3 \
  --access-token "$QUALYS_ACCESS_TOKEN" \
  --mode evaluate-policy \
  --policy-tags "$POLICY_TAGS" \
  --output-dir "$OUTPUT_DIR"
RESULT=$?
set -e

# Lógica de Issues
if [ "$RESULT" -eq 42 ]; then
  ISSUE_TITLE="Qualys Policy DENY - ${FULL_IMAGE}"
  ISSUE_BODY="A imagem ${FULL_IMAGE} falhou na política ${POLICY_TAGS}. Favor revisar vulnerabilidades."

  export GH_TOKEN="$GH_TOKEN"
  EXISTING_ISSUE="$(gh issue list --state all --search "$ISSUE_TITLE in:title" --json number,state --jq '.[0]')"
  NUMBER="$(echo "$EXISTING_ISSUE" | jq -r '.number' 2>/dev/null)"
  STATE="$(echo "$EXISTING_ISSUE" | jq -r '.state' 2>/dev/null)"

  if [ -n "$NUMBER" ] && [ "$NUMBER" != "null" ]; then
    [ "$STATE" == "closed" ] && gh issue reopen "$NUMBER"
    gh issue comment "$NUMBER" --body "$ISSUE_BODY"
  else
    gh issue create --title "$ISSUE_TITLE" --body "$ISSUE_BODY"
  fi
  exit 42
fi
