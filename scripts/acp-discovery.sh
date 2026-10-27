#!/usr/bin/env bash
# Discover APIs and components from connected gateways.

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-discovery.sh run [options]

Options:
  --environment <env-id>     scan only this environment (repeatable); default all environments
  --stage DEVELOPMENT|PRODUCTION
  --no-apis                  skip APIs and specifications (default: discover)
  --no-components            skip applications and subscriptions (default: discover)
  --custom-fields            also discover custom field definitions
  --policy-templates         also discover API policy templates (needs APIs)
  --ignore-exclusions        ignore configured discovery exclusions
  --async [--no-wait]        run as a job and poll it (default: synchronous call)

Discovery needs the DISCOVERY scope (global administrators).
Credentials from .env: BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID (or ACP_TOKEN); ACP_BASE_URL optional.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift
[[ "$sub" == "run" ]] || { usage >&2; exit 1; }
acp_init

apis=true; components=true; custom=false; policies=false; ignore=false
stage=""; envs=""; async=0; wait=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment) envs+="${envs:+,}\"$2\""; shift 2 ;;
    --stage) stage="$2"; shift 2 ;;
    --no-apis) apis=false; shift ;;
    --no-components) components=false; shift ;;
    --custom-fields) custom=true; shift ;;
    --policy-templates) policies=true; shift ;;
    --ignore-exclusions) ignore=true; shift ;;
    --async) async=1; shift ;;
    --no-wait) wait=0; shift ;;
    *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
  esac
done

body="{\"discoverApis\":$apis,\"discoverComponents\":$components,\"discoverCustomFields\":$custom,\"discoverApiPolicyTemplates\":$policies,\"ignoreExclusions\":$ignore"
[[ -n "$envs" ]] && body+=",\"environments\":[$envs]"
[[ -n "$stage" ]] && body+=",\"stage\":\"$stage\""
body+="}"

path="discovery"; (( async )) && path+="/async"
acp_api -X POST -H "Content-Type: application/json" -d "$body" "$(acp_url "$path")"

if (( async )); then
  acp_ok || finish
  job_id=$(json_str id); echo "Job: $job_id"
  (( wait )) && wait_for_job "$job_id"
  exit $?
fi
finish
