#!/usr/bin/env bash
set -euo pipefail

# Configuração de variáveis
QUALYS_POD="${QUALYS_POD:-US3}"
IMAGE_NAME="${IMAGE_NAME:-poc-api-matias}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
POLICY_TAGS="${POLICY_TAGS:-POC_API_MATIAS}"
OUTPUT_DIR="${OUTPUT_DIR:-qualys-results}"

# Download e execução do Scanner
QSCANNER_DOWNLOAD_URL="https://www.qualys.com/qscanner/download/latest/download_qscanner.sh"
curl -fsSL "$QSCANNER_DOWNLOAD_URL" -o download_qscanner.sh
chmod +x download_qscanner.sh && ./download_qscanner.sh
QSCANNER_PATH="$(find . -type f -name qscanner | head -n 1)"
chmod +x "$QSCANNER_PATH"

# Scan da imagem (já deve estar no daemon do docker local)
set +e
"$QSCANNER_PATH" image "$FULL_IMAGE" --pod "$QUALYS_POD" --access-token "$QUALYS_ACCESS_TOKEN" \
  --mode evaluate-policy --policy-tags "$POLICY_TAGS" --output-dir "$OUTPUT_DIR"
RESULT=$?
set -e

# Tratamento de resultado DENY (42)
if [ "$RESULT" -eq 42 ]; then
  ISSUE_TITLE="Qualys Policy DENY - ${FULL_IMAGE}"
  ISSUE_BODY="A imagem ${FULL_IMAGE} falhou na política ${POLICY_TAGS}."

  # Verifica estado da issue (aberta ou fechada)
  ISSUE_DATA="$(gh issue list --state all --search "$ISSUE_TITLE in:title" --json number,state --jq '.[0]')"
  ISSUE_NUMBER="$(echo "$ISSUE_DATA" | jq -r '.number' 2>/dev/null)"
  ISSUE_STATE="$(echo "$ISSUE_DATA" | jq -r '.state' 2>/dev/null)"

  if [ -n "$ISSUE_NUMBER" ]; then
    [ "$ISSUE_STATE" == "closed" ] && gh issue reopen "$ISSUE_NUMBER"
    gh issue comment "$ISSUE_NUMBER" --body "$ISSUE_BODY"
  else
    gh issue create --title "$ISSUE_TITLE" --body "$ISSUE_BODY"
  fi
  exit 42
fi
exit "$RESULT"
