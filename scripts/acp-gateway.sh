#!/usr/bin/env bash
# API Gateway and platform type operations.

# Whole-script trace off: create and agent-token responses carry the agent token, echoed after acp_api's fence.
set +x

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-gateway.sh <subcommand> [args]

Subcommands:
  list [--text <t>] [--name <n>] [--platformType <t>] [--agentType STANDALONE|MANAGED] [--environmentType SINGLE|MULTI] [--page <n>] [--size <n>] [--sort <f,dir>]
  get <gateway-id>
  create <json-file|json-string>       required: platformType, name. Response includes the one-time agentToken.
  update <gateway-id> <json-file|json-string>
  delete <gateway-id>
  agent-token <gateway-id>             issue a new agent token (invalidates the previous one)
  refresh <gateway-id> [--async] [--no-wait]      re-probe gateway status through the agent
  refresh-all [--async] [--no-wait]
  discover-environments <gateway-id> [--ignore-exclusions] [--async] [--no-wait]
                                       populate environments of a multi-environment gateway; 500 "not supported by agent" until an agent is connected
  application-deployments <gateway-id>
  platform-types [--custom true|false] [--page <n>] [--size <n>]
  platform-type <type>                 look up one platform type by its type key

Credentials from .env: BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID (or ACP_TOKEN); ACP_BASE_URL optional.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift
acp_init

run_refresh() {
  # run_refresh <path> [--async] [--no-wait]
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
    acp_api "$(with_query "$(acp_url apiGateways)")" ;;
  get)
    need "${1:-}" "Need <gateway-id>"
    acp_api "$(acp_url "apiGateways/$1")" ;;
  create)
    need "${1:-}" "Need <json-file|json-string>"
    json_body "$1"
    acp_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url apiGateways)" ;;
  update)
    need "${2:-}" "Need <gateway-id> <json-file|json-string>"
    json_body "$2"
    acp_api -X PUT -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url "apiGateways/$1")" ;;
  delete)
    need "${1:-}" "Need <gateway-id>"
    acp_api -X DELETE "$(acp_url "apiGateways/$1")" ;;
  agent-token)
    need "${1:-}" "Need <gateway-id>"
    acp_api -X PUT "$(acp_url "apiGateways/$1/agent")" ;;
  refresh)
    need "${1:-}" "Need <gateway-id>"; id="$1"; shift
    run_refresh "apiGateways/$id/agent/refreshGatewayInfo" "$@" ;;
  refresh-all)
    run_refresh "apiGateways/refreshAllGatewayInfo" "$@" ;;
  discover-environments)
    need "${1:-}" "Need <gateway-id>"; id="$1"; shift
    ignore=false; async=0; wait=1
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --ignore-exclusions) ignore=true; shift ;;
        --async) async=1; shift ;;
        --no-wait) wait=0; shift ;;
        *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
      esac
    done
    body="{\"apiGateway\":\"$id\",\"ignoreExclusions\":$ignore}"
    path="discovery/environments"; (( async )) && path+="/async"
    acp_api -X POST -H "Content-Type: application/json" -d "$body" "$(acp_url "$path")"
    if (( async )); then
      acp_ok || finish
      job_id=$(json_str id); echo "Job: $job_id"
      (( wait )) && wait_for_job "$job_id"
      exit $?
    fi ;;
  application-deployments)
    need "${1:-}" "Need <gateway-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "apiGateways/$id/deployments/applications")")" ;;
  platform-types)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url platformType)")" ;;
  platform-type)
    need "${1:-}" "Need <type>"
    acp_api "$(acp_url "platformType/byType/$1")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
