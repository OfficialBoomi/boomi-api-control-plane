#!/usr/bin/env bash
# Plan operations (tenant-global quota and rate-limit definitions).

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-plan.sh <subcommand> [args]

Subcommands:
  list [--text <t>] [--displayName <n>] [--deploymentStatus <s>] [--product <id>] [--candidatesForProduct <id>] [--page <n>] [--size <n>] [--sort <f,dir>]
  get <plan-id>
  create <json-file|json-string>       required: displayName, quotaHits (0 = unlimited), quotaInterval, rateLimit (0 = off), rateInterval; optional: description
  update <plan-id> <json-file|json-string>
  delete <plan-id> [--async] [--no-wait]
  deploy <plan-id> [--async] [--no-wait]      push to every environment where the plan is required
  deployments <plan-id> [--page <n>] [--size <n>]
  products <plan-id> [--page <n>] [--size <n>]   API products using this plan

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
    acp_api "$(with_query "$(acp_url plans)")" ;;
  get)
    need "${1:-}" "Need <plan-id>"
    acp_api "$(acp_url "plans/$1")" ;;
  create)
    need "${1:-}" "Need <json-file|json-string>"
    json_body "$1"
    acp_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url plans)" ;;
  update)
    need "${2:-}" "Need <plan-id> <json-file|json-string>"
    json_body "$2"
    acp_api -X PUT -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url "plans/$1")" ;;
  delete)
    need "${1:-}" "Need <plan-id>"; id="$1"; shift
    async=0; wait=1
    while [[ $# -gt 0 ]]; do
      case "$1" in --async) async=1; shift ;; --no-wait) wait=0; shift ;; *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;; esac
    done
    if (( async )); then
      acp_api -X DELETE "$(acp_url "plans/$id/async")"
      acp_ok || finish
      job_id=$(json_str id); echo "Job: $job_id"
      (( wait )) && wait_for_job "$job_id"
      exit $?
    fi
    acp_api -X DELETE "$(acp_url "plans/$id")" ;;
  deploy)
    need "${1:-}" "Need <plan-id>"; id="$1"; shift
    run_deploy "plans/$id" "$@"; exit $? ;;
  deployments)
    need "${1:-}" "Need <plan-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "plans/$id/deployments")")" ;;
  products)
    need "${1:-}" "Need <plan-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "plans/$id/apiProducts")")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
