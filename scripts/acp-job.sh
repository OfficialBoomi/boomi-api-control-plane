#!/usr/bin/env bash
# Background job status and polling.

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-job.sh <subcommand> [args]

Subcommands:
  get <job-id>              one read; tries /jobs/{id}, then /boomi-jobs/{id}. Completed jobs are reachable by id only; list shows in-flight jobs.
  wait <job-id>             poll until terminal (every 3 s, up to 300 s)
  list                      running jobs
  boomi-jobs [--limit <n>]  recent jobs in the newer job store
  running --jobType BUILD_IN_INTEGRATION|API_SPEC_LINT|MCP_REGISTRY_SYNC --entityId <id> --entityType API|API_SPEC|API_PRODUCT
                            entity-scoped task lookup, all three required; lint jobs are keyed by the specification id
                            (entityType API_SPEC), not the API id; the entry is consumed on read
  running-job <id>

Credentials from .env: BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID (or ACP_TOKEN); ACP_BASE_URL optional.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift
acp_init

case "$sub" in
  get)
    need "${1:-}" "Need <job-id>"
    acp_api "$(acp_url "jobs/$1")"
    (( RESPONSE_CODE == 404 )) && acp_api "$(acp_url "boomi-jobs/$1")" ;;
  wait)
    need "${1:-}" "Need <job-id>"
    wait_for_job "$1"; exit $? ;;
  list)
    acp_api "$(acp_url jobs)" ;;
  boomi-jobs)
    while [[ $# -gt 0 ]]; do
      case "$1" in --limit) qs_add limit "$2"; shift 2 ;; *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;; esac
    done
    acp_api "$(with_query "$(acp_url boomi-jobs)")" ;;
  running)
    while [[ $# -gt 0 ]]; do
      case "$1" in --entityId|--entityType|--jobType) need "${2:-}" "$1 needs a value"; qs_add "${1#--}" "$2"; shift 2 ;; *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;; esac
    done
    for p in jobType entityId entityType; do
      [[ "$QUERY" == *"$p="* ]] || { echo "ERROR: --jobType, --entityId, and --entityType are all required" >&2; exit 1; }
    done
    acp_api "$(with_query "$(acp_url runningJobs)")" ;;
  running-job)
    need "${1:-}" "Need <id>"
    acp_api "$(acp_url "runningJobs/$1")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
