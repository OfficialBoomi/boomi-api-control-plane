#!/usr/bin/env bash
# Environment operations, including the agent attached to a single-environment gateway.

# Whole-script trace off: agent-token responses carry the agent token, echoed after acp_api's fence.
set +x

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-environment.sh <subcommand> [args]

Subcommands:
  list [--text <t>] [--name <n>] [--status ACTIVE|INACTIVE] [--stage DEVELOPMENT|PRODUCTION] [--platformType <t>] [--apiGateway <id>] [--pinned true|false] [--page <n>] [--size <n>] [--sort <f,dir>]
  get <env-id>
  create <json-file|json-string>       required: name, displayName, url, symbol (<=4 chars), color, status, pinned, stage, platformType
                                       optional: apiGatewayName (defaults to name), subscribeAccessMode, publishAccessMode, apiUrlStrategy
                                       response embeds the new gateway's agentToken; a rejected create can still leave the gateway behind
  update <env-id> <json-file|json-string>
  delete <env-id>                      also removes the environment's SINGLE gateway
  agent <env-id>                       agent status, gateway status, capabilities
  agent-token <env-id>                 register or reset the agent; returns the token to run the agent with
  agent-delete <env-id>
  refresh <env-id> [--async] [--no-wait]      re-probe gateway status through the agent
  refresh-all [--async] [--no-wait]
  deployments <env-id> apis|applications|plans|subscriptions [--page <n>] [--size <n>]
  publish-orgs <env-id>                organizations allowed to publish here (RESTRICTED mode)
  subscribe-orgs <env-id>              organizations allowed to subscribe here (RESTRICTED mode)
  grant-publish <env-id> <org-id>      / revoke-publish <env-id> <org-id>
  grant-subscribe <env-id> <org-id>    / revoke-subscribe <env-id> <org-id>

Credentials from .env: BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID (or ACP_TOKEN); ACP_BASE_URL optional.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift
acp_init

run_refresh() {
  local path="$1"; shift
  local async=0 wait=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --async) async=1; shift ;;
      --no-wait) wait=0; shift ;;
      *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
    esac
  done
  if (( async )); then
    acp_api -X POST "$(acp_url "$path/async")"
    acp_ok || finish
    job_id=$(json_str id); echo "Job: $job_id"
    (( wait )) && wait_for_job "$job_id"
    exit $?
  fi
  acp_api -X POST "$(acp_url "$path")"
}

case "$sub" in
  list)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url environments)")" ;;
  get)
    need "${1:-}" "Need <env-id>"
    acp_api "$(acp_url "environments/$1")" ;;
  create)
    need "${1:-}" "Need <json-file|json-string>"
    json_body "$1"
    acp_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url environments)" ;;
  update)
    need "${2:-}" "Need <env-id> <json-file|json-string>"
    json_body "$2"
    acp_api -X PUT -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url "environments/$1")" ;;
  delete)
    need "${1:-}" "Need <env-id>"
    acp_api -X DELETE "$(acp_url "environments/$1")" ;;
  agent)
    need "${1:-}" "Need <env-id>"
    acp_api "$(acp_url "environments/$1/agent")" ;;
  agent-token)
    need "${1:-}" "Need <env-id>"
    acp_api -X PUT "$(acp_url "environments/$1/agent")" ;;
  agent-delete)
    need "${1:-}" "Need <env-id>"
    acp_api -X DELETE "$(acp_url "environments/$1/agent")" ;;
  refresh)
    need "${1:-}" "Need <env-id>"; id="$1"; shift
    run_refresh "environments/$id/agent/refreshGatewayInfo" "$@" ;;
  refresh-all)
    run_refresh "environments/refreshAllGatewayInfo" "$@" ;;
  deployments)
    need "${2:-}" "Need <env-id> apis|applications|plans|subscriptions"
    id="$1"; kind="$2"; shift 2
    case "$kind" in apis|applications|plans|subscriptions) ;; *) echo "ERROR: kind must be apis|applications|plans|subscriptions" >&2; exit 1 ;; esac
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "environments/$id/deployments/$kind")")" ;;
  publish-orgs)
    need "${1:-}" "Need <env-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "environments/$id/publishOrganizations")")" ;;
  subscribe-orgs)
    need "${1:-}" "Need <env-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "environments/$id/subscribeOrganizations")")" ;;
  grant-publish)
    need "${2:-}" "Need <env-id> <org-id>"
    acp_api -X PUT "$(acp_url "environments/$1/publishOrganizations/$2")" ;;
  revoke-publish)
    need "${2:-}" "Need <env-id> <org-id>"
    acp_api -X DELETE "$(acp_url "environments/$1/publishOrganizations/$2")" ;;
  grant-subscribe)
    need "${2:-}" "Need <env-id> <org-id>"
    acp_api -X PUT "$(acp_url "environments/$1/subscribeOrganizations/$2")" ;;
  revoke-subscribe)
    need "${2:-}" "Need <env-id> <org-id>"
    acp_api -X DELETE "$(acp_url "environments/$1/subscribeOrganizations/$2")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
