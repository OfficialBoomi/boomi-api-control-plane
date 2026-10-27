#!/usr/bin/env bash
# API Product operations: bundle APIs and plans, control visibility, deploy.

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-product.sh <subcommand> [args]

Subcommands:
  list [--text <t>] [--displayName <n>] [--owner <org-id>] [--environment <id>] [--tags <t>] [--deployed true|false] [--api <id>] [--plan <id>] [--visibility PUBLIC|RESTRICTED] [--published PUBLISHED|UNPUBLISHED] [--candidatesForApi <id>] [--includeDeployedOn true] [--page <n>] [--size <n>] [--sort <f,dir>]
  get <product-id>                        includes subscribableStatus (OK or the blocker)
  create <json-file|json-string>          required: name, displayName, visibility, allowSelfServiceSubscription, published, mcpStatus, tags; optional: description, owner
  update <product-id> <json-file|json-string>
  delete <product-id> [--async] [--no-wait]
  apis <product-id>                       / add-api <product-id> <api-id>       / remove-api <product-id> <api-id>
  plans <product-id>                      / add-plan <product-id> <plan-id>     / remove-plan <product-id> <plan-id>
  organizations <product-id>              / allow-org <product-id> <org-id>     / revoke-org <product-id> <org-id>   (RESTRICTED visibility)
  subscribable-environments <product-id>
  subscriptions <product-id> [--page <n>] [--size <n>]
  deploy <product-id> [--async] [--no-wait]      re-sync existing deployments
  deployments <product-id> [--page <n>] [--size <n>]

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
    acp_api "$(with_query "$(acp_url apiProducts)")" ;;
  get)
    need "${1:-}" "Need <product-id>"
    acp_api "$(acp_url "apiProducts/$1")" ;;
  create)
    need "${1:-}" "Need <json-file|json-string>"
    json_body "$1"
    acp_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url apiProducts)" ;;
  update)
    need "${2:-}" "Need <product-id> <json-file|json-string>"
    json_body "$2"
    acp_api -X PUT -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url "apiProducts/$1")" ;;
  delete)
    need "${1:-}" "Need <product-id>"; id="$1"; shift
    async=0; wait=1
    while [[ $# -gt 0 ]]; do
      case "$1" in --async) async=1; shift ;; --no-wait) wait=0; shift ;; *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;; esac
    done
    if (( async )); then
      acp_api -X DELETE "$(acp_url "apiProducts/$id/async")"
      acp_ok || finish
      job_id=$(json_str id); echo "Job: $job_id"
      (( wait )) && wait_for_job "$job_id"
      exit $?
    fi
    acp_api -X DELETE "$(acp_url "apiProducts/$id")" ;;
  apis)
    need "${1:-}" "Need <product-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "apiProducts/$id/apis")")" ;;
  add-api)
    need "${2:-}" "Need <product-id> <api-id>"
    acp_api -X PUT "$(acp_url "apiProducts/$1/apis/$2")" ;;
  remove-api)
    need "${2:-}" "Need <product-id> <api-id>"
    acp_api -X DELETE "$(acp_url "apiProducts/$1/apis/$2")" ;;
  plans)
    need "${1:-}" "Need <product-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "apiProducts/$id/plans")")" ;;
  add-plan)
    need "${2:-}" "Need <product-id> <plan-id>"
    acp_api -X PUT "$(acp_url "apiProducts/$1/plans/$2")" ;;
  remove-plan)
    need "${2:-}" "Need <product-id> <plan-id>"
    acp_api -X DELETE "$(acp_url "apiProducts/$1/plans/$2")" ;;
  organizations)
    need "${1:-}" "Need <product-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "apiProducts/$id/organizations")")" ;;
  allow-org)
    need "${2:-}" "Need <product-id> <org-id>"
    acp_api -X PUT "$(acp_url "apiProducts/$1/organizations/$2")" ;;
  revoke-org)
    need "${2:-}" "Need <product-id> <org-id>"
    acp_api -X DELETE "$(acp_url "apiProducts/$1/organizations/$2")" ;;
  subscribable-environments)
    need "${1:-}" "Need <product-id>"
    acp_api "$(acp_url "apiProducts/$1/subscribableEnvironments")" ;;
  subscriptions)
    need "${1:-}" "Need <product-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "apiProducts/$id/subscriptions")")" ;;
  deploy)
    need "${1:-}" "Need <product-id>"; id="$1"; shift
    run_deploy "apiProducts/$id" "$@"; exit $? ;;
  deployments)
    need "${1:-}" "Need <product-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "apiProducts/$id/deployments")")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
