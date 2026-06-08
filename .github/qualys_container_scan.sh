#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "Qualys Container Security - Policy Scan"
echo "=========================================="

QUALYS_POD="${QUALYS_POD:-US3}"
IMAGE_NAME="${IMAGE_NAME:-poc-api-matias}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${FULL_IMAGE:-${IMAGE_NAME}:${IMAGE_TAG}}"
POLICY_TAGS="${POLICY_TAGS:-REPOSITORIO_GITHUB}"
OUTPUT_DIR="${OUTPUT_DIR:-qualys-results}"

QSCANNER_DOWNLOAD_URL="https://www.qualys.com/qscanner/download/latest/download_qscanner.sh"

: "${QUALYS_ACCESS_TOKEN:?Erro: configure QUALYS_ACCESS_TOKEN}"
: "${GITHUB_TOKEN:?Erro: configure GITHUB_TOKEN}"

mkdir -p "$OUTPUT_DIR"

echo "Baixando QScanner..."
curl -fsSL "$QSCANNER_DOWNLOAD_URL" -o download_qscanner.sh
chmod +x download_qscanner.sh
./download_qscanner.sh

QSCANNER_PATH="$(find . -type f -name qscanner | head -n 1)"

if [ -z "$QSCANNER_PATH" ]; then
  echo "ERRO: qscanner não encontrado."
  exit 1
fi

chmod +x "$QSCANNER_PATH"

DOCKERFILE_PATH="$(find . -type f -name Dockerfile | head -n 1)"

if [ -z "$DOCKERFILE_PATH" ]; then
  echo "ERRO: Dockerfile não encontrado."
  exit 1
fi

BUILD_DIR="qualys-build-context"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cp "$DOCKERFILE_PATH" "$BUILD_DIR/Dockerfile"

if [ -f "requirements.txt" ]; then
  cp requirements.txt "$BUILD_DIR/requirements.txt"
else
  echo "requests" > "$BUILD_DIR/requirements.txt"
fi

if [ -d "app" ]; then
  cp -r app "$BUILD_DIR/app"
elif [ -d "App" ]; then
  cp -r App "$BUILD_DIR/App"
else
  echo "ERRO: pasta da aplicação não encontrada."
  exit 1
fi

echo "Build da imagem Docker: $FULL_IMAGE"
docker build -f "$BUILD_DIR/Dockerfile" -t "$FULL_IMAGE" "$BUILD_DIR"

echo "Executando Qualys Policy Evaluation..."
set +e

"$QSCANNER_PATH" image "$FULL_IMAGE" \
  --pod "$QUALYS_POD" \
  --access-token "$QUALYS_ACCESS_TOKEN" \
  --mode evaluate-policy \
  --policy-tags "$POLICY_TAGS" \
  --output-dir "$OUTPUT_DIR" \
  --report-format json,sarif,table \
  --file-logging

RESULT=$?
set -e

echo "Resultado do QScanner: $RESULT"

JSON_FILE="$(find "$OUTPUT_DIR" -type f -name "*.json" | head -n 1 || true)"
SARIF_FILE="$(find "$OUTPUT_DIR" -type f -name "*.sarif" | head -n 1 || true)"

if [ "$RESULT" -eq 42 ]; then
  echo "DENY: imagem bloqueada pela policy Qualys."

  ISSUE_TITLE="Qualys Policy DENY - ${FULL_IMAGE}"

  ISSUE_BODY=$(cat <<EOF
## Qualys Container Security - Policy DENY

A imagem **${FULL_IMAGE}** foi bloqueada pela policy do Qualys.

**POD:** ${QUALYS_POD}  
**Policy Tags:** ${POLICY_TAGS}  
**Resultado:** DENY  
**Exit Code:** 42  

### Artefatos
O relatório JSON/SARIF foi gerado no workflow em:

\`${OUTPUT_DIR}\`

Verifique os artifacts do GitHub Actions para baixar o arquivo JSON completo.
EOF
)

  EXISTING_ISSUE="$(gh issue list --state open --search "$ISSUE_TITLE in:title" --json number --jq '.[0].number' || true)"

  if [ -n "$EXISTING_ISSUE" ]; then
    echo "Issue já existe: #$EXISTING_ISSUE. Atualizando comentário..."
    gh issue comment "$EXISTING_ISSUE" --body "$ISSUE_BODY"
  else
    echo "Criando nova issue no GitHub..."
    gh issue create \
      --title "$ISSUE_TITLE" \
      --body "$ISSUE_BODY" \
      --label "security,qualys,container"
  fi

  exit 42

elif [ "$RESULT" -eq 43 ]; then
  echo "AUDIT: policy não aplicada ou apenas auditoria."
  exit 43

elif [ "$RESULT" -eq 0 ]; then
  echo "ALLOW: imagem aprovada pela policy Qualys."
  exit 0

else
  echo "ERRO técnico no QScanner."
  exit "$RESULT"
fi
