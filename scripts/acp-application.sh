#!/usr/bin/env bash
# Application operations (consumer identities that hold subscriptions and API keys).

# Whole-script trace off: application responses carry aiAgentKey, echoed after acp_api's fence.
set +x

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-application.sh <subcommand> [args]

Subcommands:
  list [--text <t>] [--displayName <n>] [--owner <org-id>] [--status ACTIVE|INACTIVE] [--deploymentStatus <s>] [--environment <id>] [--apiGateway <id>] [--deployed true|false] [--includeDeployedOn true] [--page <n>] [--size <n>] [--sort <f,dir>]
  get <app-id>
  create <json-file|json-string>       required: displayName, status; optional: description, owner, oauthCallbackUrl, oauthScope
  update <app-id> <json-file|json-string>
  delete <app-id> [--async] [--no-wait]
  deploy <app-id> [--async] [--no-wait]       push to every gateway where the application is required
  deployments <app-id> [--page <n>] [--size <n>]
  subscriptions <app-id> [--includeDTOs true] [--page <n>] [--size <n>]

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
    acp_api "$(with_query "$(acp_url applications)")" ;;
  get)
    need "${1:-}" "Need <app-id>"
    acp_api "$(acp_url "applications/$1")" ;;
  create)
    need "${1:-}" "Need <json-file|json-string>"
    json_body "$1"
    acp_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url applications)" ;;
  update)
    need "${2:-}" "Need <app-id> <json-file|json-string>"
    json_body "$2"
    acp_api -X PUT -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url "applications/$1")" ;;
  delete)
    need "${1:-}" "Need <app-id>"; id="$1"; shift
    async=0; wait=1
    while [[ $# -gt 0 ]]; do
      case "$1" in --async) async=1; shift ;; --no-wait) wait=0; shift ;; *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;; esac
    done
    if (( async )); then
      acp_api -X DELETE "$(acp_url "applications/$id/async")"
      acp_ok || finish
      job_id=$(json_str id); echo "Job: $job_id"
      (( wait )) && wait_for_job "$job_id"
      exit $?
    fi
    acp_api -X DELETE "$(acp_url "applications/$id")" ;;
  deploy)
    need "${1:-}" "Need <app-id>"; id="$1"; shift
    run_deploy "applications/$id" "$@"; exit $? ;;
  deployments)
    need "${1:-}" "Need <app-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "applications/$id/deployments")")" ;;
  subscriptions)
    need "${1:-}" "Need <app-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "applications/$id/subscriptions")")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
