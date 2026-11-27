#!/usr/bin/env bash
# Ativa o envio de alertas do Wazuh para um webhook do Shuffle. Pode ser repetido.
# Uso: bash integrar-shuffle.sh [webhook_ID]
set -euo pipefail
cd "$(dirname "$0")"

CONF="wazuh/config/wazuh_cluster/wazuh_manager.conf"
BEGIN="<!-- BEGIN integracao-shuffle -->"
END="<!-- END integracao-shuffle -->"

fail() { echo "ERRO: $*" >&2; exit 1; }
read_env() { { grep -E "^$1=" .env || true; } | tail -n1 | cut -d= -f2- | tr -d "\"'\r"; }

[ -f .env ] && [ -f "$CONF" ] || fail "execute antes: bash setup.sh"

HOOK="${1:-$(read_env SHUFFLE_WEBHOOK_ID)}"
RULES="$(read_env SHUFFLE_RULE_IDS)"
RULES="${RULES:-5712,5551,60204}"

[[ "$HOOK" =~ ^webhook_[A-Za-z0-9-]+$ ]] || fail "informe o ID no formato webhook_xxxx (não a URL completa)"
[[ "$RULES" =~ ^[0-9]+(,[0-9]+)*$ ]] || fail "SHUFFLE_RULE_IDS deve ser uma lista como 5712,5551"

# Grava o ID no .env para as próximas execuções
if grep -q '^SHUFFLE_WEBHOOK_ID=' .env; then
  sed -i "s|^SHUFFLE_WEBHOOK_ID=.*|SHUFFLE_WEBHOOK_ID=$HOOK|" .env
else
  printf '\nSHUFFLE_WEBHOOK_ID=%s\n' "$HOOK" >> .env
fi

cp -p "$CONF" "$CONF.bak"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Remove o bloco anterior e insere o novo antes do primeiro </ossec_config>
awk -v b="$BEGIN" -v e="$END" -v hook="$HOOK" -v rules="$RULES" '
  index($0, b) { skip=1; next }
  index($0, e) { skip=0; next }
  skip { next }
  !done && /<\/ossec_config>/ {
    print "  " b
    print "  <integration>"
    print "    <name>shuffle</name>"
    print "    <hook_url>http://shuffle-backend:5001/api/v1/hooks/" hook "</hook_url>"
    print "    <rule_id>" rules "</rule_id>"
    print "    <alert_format>json</alert_format>"
    print "  </integration>"
    print "  " e
    done=1
  }
  { print }
  END { if (!done || skip) exit 1 }
' "$CONF" > "$tmp" || fail "não foi possível editar $CONF"

# "cat >" mantém o mesmo arquivo montado no container
cat "$tmp" > "$CONF"

docker compose restart wazuh.manager
echo "Integração aplicada (regras: $RULES)."
echo "Gere um alerta de teste e confira as execuções do workflow no Shuffle."
echo "Log: docker compose exec wazuh.manager tail -n 50 /var/ossec/logs/integrations.log"
