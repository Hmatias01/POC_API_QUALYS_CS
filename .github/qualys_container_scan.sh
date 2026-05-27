#!/usr/bin/env bash
set -euo pipefail

# =====================================================
# Qualys Container Security - QScanner + Policy Eval
# Policy no Qualys: POC_API_MATIAS
# Tag da policy: REPOSITÓRIO DO GITHUB
# Qualys API Gateway: https://qualysapi.qg3.apps.qualys.com
# =====================================================

QUALYS_POD="${QUALYS_POD:-US3}"
QUALYS_API_SERVER="${QUALYS_API_SERVER:-https://qualysapi.qg3.apps.qualys.com}"

IMAGE_NAME="${IMAGE_NAME:-poc-api-matias}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${FULL_IMAGE:-${IMAGE_NAME}:${IMAGE_TAG}}"

ENVIRONMENT="${ENVIRONMENT:-github}"
APP_NAME="${APP_NAME:-poc-api-matias}"
POLICY_TAGS="${POLICY_TAGS:-REPOSITÓRIO DO GITHUB}"

OUTPUT_DIR="${OUTPUT_DIR:-qualys-results}"

QSCANNER_DOWNLOAD_URL="https://www.qualys.com/qscanner/download/latest/download_qscanner.sh"

echo "Validando token Qualys..."
: "${QUALYS_ACCESS_TOKEN:?Erro: configure QUALYS_ACCESS_TOKEN antes de executar}"

mkdir -p "$OUTPUT_DIR"

echo "Baixando QScanner..."
curl -fsSL "$QSCANNER_DOWNLOAD_URL" -o download_qscanner.sh
chmod +x download_qscanner.sh
./download_qscanner.sh
chmod +x ./qscanner

echo "Build da imagem Docker: $FULL_IMAGE"
docker build -t "$FULL_IMAGE" .

echo "Executando scan com Policy Evaluation..."
set +e

./qscanner image "$FULL_IMAGE" \
  --pod "$QUALYS_POD" \
  --mode evaluate-policy \
  --policy-tags "$POLICY_TAGS" \
  --output-dir "$OUTPUT_DIR" \
  --report-format json,sarif,table \
  --file-logging

RESULT=$?

set -e

echo "Resultado do Qualys QScanner: $RESULT"

if [ "$RESULT" -eq 0 ]; then
  echo "ALLOW: imagem aprovada pela policy do Qualys."
  exit 0
elif [ "$RESULT" -eq 42 ]; then
  echo "DENY: imagem bloqueada pela policy do Qualys."
  exit 42
elif [ "$RESULT" -eq 43 ]; then
  echo "AUDIT: nenhuma policy aplicável ou policy em modo auditoria."
  exit 43
else
  echo "ERRO: falha técnica no scan Qualys."
  exit "$RESULT"
fi
