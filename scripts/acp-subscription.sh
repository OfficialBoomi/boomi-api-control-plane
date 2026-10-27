#!/usr/bin/env bash
# Subscription operations: bind an application to an API product under a plan; read API keys.

# Whole-script trace off: keys, key, and regenerate-key responses carry API keys and secrets, echoed after acp_api's fence.
set +x

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-subscription.sh <subcommand> [args]

Subcommands:
  list [--owner <org-id>] [--apiProduct <id>] [--application <id>] [--api <id>] [--environment <id>] [--applicationDisplayName <n>] [--page <n>] [--size <n>] [--sort <f,dir>]
  get <sub-id>                          approvalStatus, deploymentStatus
  create <json-file|json-string>        required: application, apiProduct, plan (UUIDs); optional: environments (UUIDs, create only)
  change-plan <sub-id> <plan-id>
  delete <sub-id> [--async] [--no-wait]
  deploy <sub-id> [--async] [--no-wait]        push to every environment where the subscription is required
  deployments <sub-id> [--page <n>] [--size <n>]
  keys <sub-id>                         access permissions per environment (API key, secret, per-API URLs)
  key <sub-id> <permission-id>
  regenerate-key <sub-id> <permission-id> [--async] [--no-wait]
                                        fails with 500 on Cloud API Management environments (sync and --async)
  terms <sub-id>                        accepted terms of use; 404 when none were accepted

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
    acp_api "$(with_query "$(acp_url subscriptions)")" ;;
  get)
    need "${1:-}" "Need <sub-id>"
    acp_api "$(acp_url "subscriptions/$1")" ;;
  create)
    need "${1:-}" "Need <json-file|json-string>"
    json_body "$1"
    acp_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url subscriptions)" ;;
  change-plan)
    need "${2:-}" "Need <sub-id> <plan-id>"
    acp_api -X PUT -H "Content-Type: application/json" -d "{\"plan\":\"$2\"}" "$(acp_url "subscriptions/$1")" ;;
  delete)
    need "${1:-}" "Need <sub-id>"; id="$1"; shift
    async=0; wait=1
    while [[ $# -gt 0 ]]; do
      case "$1" in --async) async=1; shift ;; --no-wait) wait=0; shift ;; *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;; esac
    done
    if (( async )); then
      acp_api -X DELETE "$(acp_url "subscriptions/$id/async")"
      acp_ok || finish
      job_id=$(json_str id); echo "Job: $job_id"
      (( wait )) && wait_for_job "$job_id"
      exit $?
    fi
    acp_api -X DELETE "$(acp_url "subscriptions/$id")" ;;
  deploy)
    need "${1:-}" "Need <sub-id>"; id="$1"; shift
    run_deploy "subscriptions/$id" "$@"; exit $? ;;
  deployments)
    need "${1:-}" "Need <sub-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "subscriptions/$id/deployments")")" ;;
  keys)
    need "${1:-}" "Need <sub-id>"
    acp_api "$(acp_url "subscriptions/$1/accessPermissions")" ;;
  key)
    need "${2:-}" "Need <sub-id> <permission-id>"
    acp_api "$(acp_url "subscriptions/$1/accessPermissions/$2")" ;;
  regenerate-key)
    need "${2:-}" "Need <sub-id> <permission-id>"; id="$1"; perm="$2"; shift 2
    async=0; wait=1
    while [[ $# -gt 0 ]]; do
      case "$1" in --async) async=1; shift ;; --no-wait) wait=0; shift ;; *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;; esac
    done
    if (( async )); then
      acp_api -X POST "$(acp_url "subscriptions/$id/accessPermissions/$perm/regenerate/async")"
      acp_ok || finish
      job_id=$(json_str id); echo "Job: $job_id"
      (( wait )) && wait_for_job "$job_id"
      exit $?
    fi
    acp_api -X POST "$(acp_url "subscriptions/$id/accessPermissions/$perm/regenerate")" ;;
  terms)
    need "${1:-}" "Need <sub-id>"
    acp_api "$(acp_url "subscriptions/$1/acceptedTermsOfUse")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
