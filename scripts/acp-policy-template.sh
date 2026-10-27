#!/usr/bin/env bash
# API policy-template reads.

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-policy-template.sh <subcommand> [args]

Policy templates:
  list [--platformType <type>] [--text <t>] [--apiDeploymentId <id>] [--page <n>] [--size <n>] [--sort <f,dir>]
  get <template-id>
  usage <template-id> [--text <t>] [--page <n>] [--size <n>] [--sort <f,dir>]
  gateway-deployments <template-id> [--page <n>] [--size <n>] [--sort <f,dir>]

Credentials from .env: BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID (or ACP_TOKEN); ACP_BASE_URL optional.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift
acp_init

case "$sub" in
  list)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url apiPolicyTemplates)")" ;;
  get)
    need "${1:-}" "Need <template-id>"
    id="$1"; shift
    [[ $# -eq 0 ]] || { echo "ERROR: unexpected argument '$1'" >&2; exit 1; }
    acp_api "$(acp_url "apiPolicyTemplates/$id")" ;;
  usage)
    need "${1:-}" "Need <template-id>"
    id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "apiPolicyTemplates/$id/usage")")" ;;
  gateway-deployments)
    need "${1:-}" "Need <template-id>"
    id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "apiPolicyTemplates/$id/gatewayApiDeployments")")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
