#!/usr/bin/env bash
# Approval request operations for subscriptions awaiting review.

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-approval.sh <subcommand> [args]

Subcommands:
  list [--status PENDING|APPROVED|DECLINED] [--createdByOrganization <org-id>] [--resolvingOrganization <org-id>] [--page <n>] [--size <n>] [--sort <f,dir>]
  pending                               summary of requests the current user can resolve (no subscription id; use list --status PENDING for that)
  get <request-id>
  approve <request-id>
  decline <request-id> --comment <text>

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
    acp_api "$(with_query "$(acp_url approvalRequests)")" ;;
  pending)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url approvalRequests/pending)")" ;;
  get)
    need "${1:-}" "Need <request-id>"
    acp_api "$(acp_url "approvalRequests/$1")" ;;
  approve)
    need "${1:-}" "Need <request-id>"
    acp_api -X POST "$(acp_url "approvalRequests/$1/approve")" ;;
  decline)
    need "${1:-}" "Need <request-id> --comment <text>"; id="$1"; shift
    comment=""
    [[ "${1:-}" == "--comment" ]] && comment="${2:-}"
    need "$comment" "decline requires --comment <text>"
    comment="${comment//\\/\\\\}"; comment="${comment//\"/\\\"}"
    acp_api -X POST -H "Content-Type: application/json" -d "{\"comment\":\"$comment\"}" "$(acp_url "approvalRequests/$id/decline")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
