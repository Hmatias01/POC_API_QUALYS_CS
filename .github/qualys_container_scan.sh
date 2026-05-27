#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "Qualys Container Security - Policy Scan"
echo "=========================================="

QUALYS_POD="${QUALYS_POD:-US3}"
IMAGE_NAME="${IMAGE_NAME:-poc-api-matias}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${FULL_IMAGE:-${IMAGE_NAME}:${IMAGE_TAG}}"
POLICY_TAGS="${POLICY_TAGS:-REPOSITÓRIO DO GITHUB}"
OUTPUT_DIR="${OUTPUT_DIR:-qualys-results}"

QSCANNER_DOWNLOAD_URL="https://www.qualys.com/qscanner/download/latest/download_qscanner.sh"

echo "Validando token Qualys..."
: "${QUALYS_ACCESS_TOKEN:?Erro: configure QUALYS_ACCESS_TOKEN}"

echo "Criando diretório de saída..."
mkdir -p "$OUTPUT_DIR"

echo "Baixando QScanner..."
curl -fsSL "$QSCANNER_DOWNLOAD_URL" -o download_qscanner.sh
chmod +x download_qscanner.sh
./download_qscanner.sh

echo "Localizando binário qscanner..."
QSCANNER_PATH="$(find . -type f -name qscanner | head -n 1)"

if [ -z "$QSCANNER_PATH" ]; then
  echo "ERRO: qscanner não encontrado."
  exit 1
fi

chmod +x "$QSCANNER_PATH"

echo "QScanner encontrado em: $QSCANNER_PATH"

echo "Build da imagem Docker: $FULL_IMAGE"
docker build -t "$FULL_IMAGE" .

echo "Executando Qualys Policy Evaluation..."
set +e

"$QSCANNER_PATH" image "$FULL_IMAGE" \
  --pod "$QUALYS_POD" \
  --mode evaluate-policy \
  --policy-tags "$POLICY_TAGS" \
  --output-dir "$OUTPUT_DIR" \
  --report-format json,sarif,table \
  --file-logging

RESULT=$?

set -e

echo "Resultado do QScanner: $RESULT"

if [ "$RESULT" -eq 0 ]; then
  echo "ALLOW: imagem aprovada pela policy Qualys."
  exit 0
elif [ "$RESULT" -eq 42 ]; then
  echo "DENY: imagem bloqueada pela policy Qualys."
  exit 42
elif [ "$RESULT" -eq 43 ]; then
  echo "AUDIT: policy não aplicada ou apenas auditoria."
  exit 43
else
  echo "ERRO: falha técnica no QScanner."
  exit "$RESULT"
fi
