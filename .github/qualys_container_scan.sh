#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "Qualys Container Security - Policy Scan"
echo "=========================================="

QUALYS_POD="${QUALYS_POD:-US3}"
IMAGE_NAME="${IMAGE_NAME:-poc-api-matias}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${FULL_IMAGE:-${IMAGE_NAME}:${IMAGE_TAG}}"
POLICY_TAGS="${POLICY_TAGS:-GITHUB_REPO}"
OUTPUT_DIR="${OUTPUT_DIR:-qualys-results}"

QSCANNER_DOWNLOAD_URL="https://www.qualys.com/qscanner/download/latest/download_qscanner.sh"

echo "Validando variáveis obrigatórias..."
: "${QUALYS_ACCESS_TOKEN:?Erro: configure QUALYS_ACCESS_TOKEN}"

GITHUB_AUTH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

mkdir -p "$OUTPUT_DIR"

echo "Estrutura atual do repositório:"
find . -maxdepth 4 -type f | sort

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

echo "Localizando Dockerfile..."
DOCKERFILE_PATH="$(find . -type f -name Dockerfile | head -n 1)"

if [ -z "$DOCKERFILE_PATH" ]; then
  echo "ERRO: Dockerfile não encontrado."
  exit 1
fi

echo "Dockerfile encontrado em: $DOCKERFILE_PATH"

echo "Preparando build context temporário..."
BUILD_DIR="qualys-build-context"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cp "$DOCKERFILE_PATH" "$BUILD_DIR/Dockerfile"

if [ -f "requirements.txt" ]; then
  cp requirements.txt "$BUILD_DIR/requirements.txt"
elif [ -f ".github/requirements.txt" ]; then
  cp .github/requirements.txt "$BUILD_DIR/requirements.txt"
else
  echo "requests" > "$BUILD_DIR/requirements.txt"
fi

if [ -d "app" ]; then
  cp -r app "$BUILD_DIR/app"
elif [ -d "App" ]; then
  cp -r App "$BUILD_DIR/App"
elif [ -d ".github/app" ]; then
  cp -r .github/app "$BUILD_DIR/app"
elif [ -d ".github/App" ]; then
  cp -r .github/App "$BUILD_DIR/App"
else
  echo "ERRO: pasta da aplicação não encontrada."
  echo "Esperado: app, App, .github/app ou .github/App"
  exit 1
fi

echo "Estrutura do build context:"
find "$BUILD_DIR" -maxdepth 4 -type f | sort

echo "Build da imagem Docker: $FULL_IMAGE"
docker build \
  -f "$BUILD_DIR/Dockerfile" \
  -t "$FULL_IMAGE" \
  "$BUILD_DIR"

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

echo "Arquivos gerados:"
find "$OUTPUT_DIR" -type f | sort || true

if [ "$RESULT" -eq 0 ]; then
  echo "ALLOW: imagem aprovada pela policy Qualys."
  exit 0
fi

if [ "$RESULT" -eq 43 ]; then
  echo "AUDIT: policy não aplicada ou apenas auditoria."
  exit 43
fi

if [ "$RESULT" -eq 42 ]; then
  echo "DENY: imagem bloqueada pela policy Qualys."

  ISSUE_TITLE="Qualys Policy DENY - ${FULL_IMAGE}"

  ISSUE_BODY=$(cat <<EOF
## Qualys Container Security - Policy DENY

A imagem **${FULL_IMAGE}** foi bloqueada pela policy do Qualys.

### Detalhes

- POD Qualys: ${QUALYS_POD}
- Policy Tags: ${POLICY_TAGS}
- Resultado: DENY
- Exit Code: 42
- Diretório de evidência: ${OUTPUT_DIR}

### Relatórios gerados

- JSON: ${JSON_FILE:-não encontrado}
- SARIF: ${SARIF_FILE:-não encontrado}

O arquivo JSON completo está disponível como artifact do GitHub Actions.
EOF
)

  if [ -z "$GITHUB_AUTH_TOKEN" ]; then
    echo "GH_TOKEN/GITHUB_TOKEN não configurado."
    echo "Issue não será aberta no GitHub."
    echo "O JSON foi gerado em: $OUTPUT_DIR"
    exit 42
  fi

  export GH_TOKEN="$GITHUB_AUTH_TOKEN"

  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI não encontrado. Instalando gh..."
    sudo apt-get update
    sudo apt-get install -y gh
  fi

  EXISTING_ISSUE="$(gh issue list \
    --state open \
    --search "$ISSUE_TITLE in:title" \
    --json number \
    --jq '.[0].number' 2>/dev/null || true)"

  if [ -n "$EXISTING_ISSUE" ]; then
    echo "Issue já existe: #$EXISTING_ISSUE"
    echo "Adicionando comentário..."
    gh issue comment "$EXISTING_ISSUE" --body "$ISSUE_BODY"
  else
    echo "Criando nova issue no GitHub..."
    gh issue create \
      --title "$ISSUE_TITLE" \
      --body "$ISSUE_BODY" \
      --label "security,qualys,container" || \
    gh issue create \
      --title "$ISSUE_TITLE" \
      --body "$ISSUE_BODY"
  fi

  exit 42
fi

echo "ERRO: falha técnica no QScanner."
exit "$RESULT"
