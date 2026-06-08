#!/usr/bin/env bash
# O set -euo pipefail garante que o script pare em qualquer erro, 
# trate variáveis não definidas e falhas em pipes.
set -euo pipefail

echo "=========================================="
echo "Qualys Container Security - Executando..."
echo "=========================================="

# Variáveis configuráveis (Podem ser passadas via ambiente)
QUALYS_POD="${QUALYS_POD:-US3}"
IMAGE_NAME="${IMAGE_NAME:-poc-api-matias}" # Nome ajustado
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# Define a política solicitada
POLICY_TAGS="${POLICY_TAGS:-POC_API_MATIAS}" 
OUTPUT_DIR="${OUTPUT_DIR:-qualys-results}"

# Validação obrigatória do token do Qualys
: "${QUALYS_ACCESS_TOKEN:?Erro: QUALYS_ACCESS_TOKEN não definido}"

# Configuração de tokens e diretório de saída
GITHUB_AUTH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
mkdir -p "$OUTPUT_DIR"

# Instalação/Download do QScanner
QSCANNER_DOWNLOAD_URL="https://www.qualys.com/qscanner/download/latest/download_qscanner.sh"
curl -fsSL "$QSCANNER_DOWNLOAD_URL" -o download_qscanner.sh
chmod +x download_qscanner.sh && ./download_qscanner.sh

# Localiza o binário após o download
QSCANNER_PATH="$(find . -type f -name qscanner | head -n 1)"
[ -z "$QSCANNER_PATH" ] && { echo "ERRO: qscanner não encontrado."; exit 1; }
chmod +x "$QSCANNER_PATH"

echo "Executando Scan de Imagem: $FULL_IMAGE com política: $POLICY_TAGS"
set +e # Permite capturar o exit code do scanner sem parar o script
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

# Processamento de Resultados
if [ "$RESULT" -eq 0 ]; then
  echo "Sucesso: Imagem aprovada."
  exit 0
fi

if [ "$RESULT" -eq 42 ]; then
  echo "Alerta: Imagem reprovada pela política. Gerando/Atualizando Issue..."
  
  ISSUE_TITLE="Qualys Policy DENY - ${FULL_IMAGE}"
  ISSUE_BODY="## Relatório de Vulnerabilidade\n\nImagem: ${FULL_IMAGE}\nPolicy: ${POLICY_TAGS}\nStatus: **DENY**\n\nFavor revisar os artefatos do scan."

  if [ -n "$GITHUB_AUTH_TOKEN" ]; then
    export GH_TOKEN="$GITHUB_AUTH_TOKEN"
    
    # Procura issue existente (aberta ou fechada)
    ISSUE_DATA="$(gh issue list --state all --search "$ISSUE_TITLE in:title" --json number,state --jq '.[0]')"
    ISSUE_NUMBER="$(echo "$ISSUE_DATA" | jq -r '.number' 2>/dev/null)"
    ISSUE_STATE="$(echo "$ISSUE_DATA" | jq -r '.state' 2>/dev/null)"

    if [ -n "$ISSUE_NUMBER" ]; then
      # Se a issue estiver fechada, reabre
      if [ "$ISSUE_STATE" == "closed" ]; then
        gh issue reopen "$ISSUE_NUMBER"
        gh issue comment "$ISSUE_NUMBER" --body "Vulnerabilidade detectada novamente. Reabrindo ticket."
      fi
      # Adiciona comentário com os novos detalhes
      gh issue comment "$ISSUE_NUMBER" --body "$ISSUE_BODY"
    else
      # Cria nova se não existir
      gh issue create --title "$ISSUE_TITLE" --body "$ISSUE_BODY"
    fi
  fi
  exit 42
fi

echo "Erro técnico no scanner. Código: $RESULT"
exit "$RESULT"
