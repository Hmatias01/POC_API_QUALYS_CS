#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "Qualys Container Security - DVWA Test"
echo "=========================================="

QUALYS_POD="${QUALYS_POD:-US3}"
IMAGE_NAME="${IMAGE_NAME:-vulnerables/web-dvwa}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${FULL_IMAGE:-${IMAGE_NAME}:${IMAGE_TAG}}"

POLICY_TAGS="${POLICY_TAGS:-GITHUB_REPO}"
OUTPUT_DIR="${OUTPUT_DIR:-qualys-results}"

QSCANNER_DOWNLOAD_URL="https://www.qualys.com/qscanner/download/latest/download_qscanner.sh"

echo "Validando variáveis..."
: "${QUALYS_ACCESS_TOKEN:?Erro: configure QUALYS_ACCESS_TOKEN}"

GITHUB_AUTH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

mkdir -p "$OUTPUT_DIR"

echo "Baixando QScanner..."
curl -fsSL "$QSCANNER_DOWNLOAD_URL" -o download_qscanner.sh
chmod +x download_qscanner.sh
./download_qscanner.sh

echo "Localizando qscanner..."
QSCANNER_PATH="$(find . -type f -name qscanner | head -n 1)"

if [ -z "$QSCANNER_PATH" ]; then
  echo "ERRO: qscanner não encontrado."
  exit 1
fi

chmod +x "$QSCANNER_PATH"

echo "Pull da imagem vulnerável..."
docker pull "$FULL_IMAGE"

echo "Executando Policy Evaluation..."
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

echo "Arquivos gerados:"
find "$OUTPUT_DIR" -type f | sort || true

JSON_FILE="$(find "$OUTPUT_DIR" -type f -name "*.json" | head -n 1 || true)"
SARIF_FILE="$(find "$OUTPUT_DIR" -type f -name "*.sarif" | head -n 1 || true)"

if [ "$RESULT" -eq 0 ]; then
  echo "ALLOW: imagem aprovada."
  exit 0
fi

if [ "$RESULT" -eq 43 ]; then
  echo "AUDIT: policy em auditoria."
  exit 43
fi

if [ "$RESULT" -eq 42 ]; then
  echo "DENY: imagem bloqueada pela policy."

  ISSUE_TITLE="Qualys Policy DENY - ${FULL_IMAGE}"

  ISSUE_BODY=$(cat <<EOF
## Qualys Container Security - Policy DENY

Imagem vulnerável detectada pelo Qualys.

### Imagem
${FULL_IMAGE}

### Resultado
- Status: DENY
- Exit Code: 42

### Policy
${POLICY_TAGS}

### Relatórios
- JSON: ${JSON_FILE:-não encontrado}
- SARIF: ${SARIF_FILE:-não encontrado}

Verifique os artifacts do GitHub Actions.
EOF
)

  if [ -n "$GITHUB_AUTH_TOKEN" ]; then

    export GH_TOKEN="$GITHUB_AUTH_TOKEN"

    if ! command -v gh >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y gh
    fi

    EXISTING_ISSUE="$(gh issue list \
      --state open \
      --search "$ISSUE_TITLE in:title" \
      --json number \
      --jq '.[0].number' 2>/dev/null || true)"

    if [ -n "$EXISTING_ISSUE" ]; then
      echo "Comentando issue existente..."
      gh issue comment "$EXISTING_ISSUE" --body "$ISSUE_BODY"
    else
      echo "Criando nova issue..."
      gh issue create \
        --title "$ISSUE_TITLE" \
        --body "$ISSUE_BODY"
    fi

  else
    echo "GH_TOKEN não configurado."
  fi

  exit 42
fi

echo "Erro técnico no QScanner."
exit "$RESULT"
