#!/usr/bin/env bash
# API, API version, and specification operations.

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-api.sh <subcommand> [args]

APIs:
  list [--text <t>] [--name <n>] [--owner <org-id>] [--status ACTIVE|INACTIVE] [--type REST|GRAPHQL] [--environment <id>] [--tags <t>] [--deployed true|false] [--product <id>] [--candidatesForProduct <id>] [--includeDeployedOn true] [--page <n>] [--size <n>] [--sort <f,dir>]
  get <api-id> [--include-running-jobs]    include active background jobs for the API
  create <json-file|json-string>          required: name, displayName, status, tags (may be []), type; optional: description, owner, url, platformType
  update <api-id> <json-file|json-string>
  delete <api-id> [--undeploy] [--async] [--no-wait]      --undeploy removes the API from its gateways first
  deployments <api-id> [--page <n>] [--size <n>]
  assign-policy-template <api-id> <deployment-id> <json-file|json-string> [--async] [--no-wait]
  replace-policy-templates <api-id> <deployment-id> <json-file|json-string> [--async] [--no-wait]

Versions:
  versions <api-id> [--page <n>] [--size <n>]
  version <api-id> <version-name>
  create-version <api-id> <json-file|json-string>   required: name, displayName, aiGenerated, deployedOn
  update-version <api-id> <version-name> <json-file|json-string>
  delete-version <api-id> <version-name>

Specifications:
  upload-spec <api-id> <spec-file>                   version is read from the spec; creates or overwrites that version's spec
  upload-version-spec <api-id> <version-name> <spec-file>
  pull-spec <api-id> <version-name> [--target-path <p>] [--environment <env-id>]
                                                     default active-development/apis/<api-id>/<version-name>.spec; --environment rewrites server URLs for that environment
  spec-info <api-id> <version-name>                  file name, type, lint scores
  lint <api-id> <version-name> [--severity ERROR|WARNING|INFO|HINT] [--category SECURITY|QUALITY]
  relint <api-id> <version-name>                     re-run rule sets against the stored spec; 409 while a lint is already running
  delete-spec <api-id> <version-name>

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
    acp_api "$(with_query "$(acp_url apis)")" ;;
  get)
    need "${1:-}" "Need <api-id>"; id="$1"; shift
    while [[ $# -gt 0 ]]; do
      case "$1" in --include-running-jobs) qs_add includeRunningJobs true; shift ;; *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;; esac
    done
    acp_api "$(with_query "$(acp_url "apis/$id")")" ;;
  create)
    need "${1:-}" "Need <json-file|json-string>"
    json_body "$1"
    acp_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url apis)" ;;
  update)
    need "${2:-}" "Need <api-id> <json-file|json-string>"
    json_body "$2"
    acp_api -X PUT -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url "apis/$1")" ;;
  delete)
    need "${1:-}" "Need <api-id>"; id="$1"; shift
    async=0; wait=1
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --undeploy) qs_add undeploy true; shift ;;
        --async) async=1; shift ;;
        --no-wait) wait=0; shift ;;
        *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
      esac
    done
    if (( async )); then
      acp_api -X DELETE "$(with_query "$(acp_url "apis/$id/async")")"
      acp_ok || finish
      job_id=$(json_str id); echo "Job: $job_id"
      (( wait )) && wait_for_job "$job_id"
      exit $?
    fi
    acp_api -X DELETE "$(with_query "$(acp_url "apis/$id")")" ;;
  deployments)
    need "${1:-}" "Need <api-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "apis/$id/deployments")")" ;;
  assign-policy-template|replace-policy-templates)
    need "${3:-}" "Need <api-id> <deployment-id> <json-file|json-string>"
    api_id="$1"; deployment_id="$2"; json_body "$3"; shift 3
    async=0; wait=1
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --async) async=1; shift ;;
        --no-wait) wait=0; shift ;;
        *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
      esac
    done
    if [[ "$sub" == "assign-policy-template" ]]; then
      path="apis/$api_id/deployments/$deployment_id/assignApiPolicyTemplate"
    else
      path="apis/$api_id/deployments/$deployment_id/replaceApiPolicyTemplates"
    fi
    (( async )) && path+="/async"
    acp_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url "$path")"
    if (( async )); then
      acp_ok || finish
      job_id=$(json_str id); echo "Job: $job_id"
      if (( wait )); then wait_for_job "$job_id"; fi
      exit 0
    fi
    finish ;;
  versions)
    need "${1:-}" "Need <api-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "apis/$id/versions")")" ;;
  version)
    need "${2:-}" "Need <api-id> <version-name>"
    acp_api "$(acp_url "apis/$1/versions/$2")" ;;
  create-version)
    need "${2:-}" "Need <api-id> <json-file|json-string>"
    json_body "$2"
    acp_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url "apis/$1/versions")" ;;
  update-version)
    need "${3:-}" "Need <api-id> <version-name> <json-file|json-string>"
    json_body "$3"
    acp_api -X PUT -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url "apis/$1/versions/$2")" ;;
  delete-version)
    need "${2:-}" "Need <api-id> <version-name>"
    acp_api -X DELETE "$(acp_url "apis/$1/versions/$2")" ;;
  upload-spec)
    need "${2:-}" "Need <api-id> <spec-file>"
    [[ -f "$2" ]] || { echo "ERROR: file not found: $2" >&2; exit 1; }
    acp_api -X PUT -F "file=@$2" "$(acp_url "apis/$1/file")" ;;
  upload-version-spec)
    need "${3:-}" "Need <api-id> <version-name> <spec-file>"
    [[ -f "$3" ]] || { echo "ERROR: file not found: $3" >&2; exit 1; }
    acp_api -X PUT -F "file=@$3" "$(acp_url "apis/$1/versions/$2/spec")" ;;
  pull-spec)
    need "${2:-}" "Need <api-id> <version-name>"
    id="$1"; ver="$2"; shift 2
    target=""; env=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --target-path) target="$2"; shift 2 ;;
        --environment) env="$2"; shift 2 ;;
        *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
      esac
    done
    [[ -z "$target" ]] && target="active-development/apis/${id}/${ver}.spec"
    [[ -n "$env" ]] && { qs_add replaceUrls true; qs_add environmentId "$env"; }
    acp_api --raw "$(with_query "$(acp_url "apis/$id/versions/$ver/spec")")"
    acp_ok || finish
    mkdir -p "$(dirname "$target")"
    printf '%s\n' "$RESPONSE_BODY" > "$target"
    echo "Saved to: $target"
    exit 0 ;;
  spec-info)
    need "${2:-}" "Need <api-id> <version-name>"
    acp_api "$(acp_url "apis/$1/versions/$2/spec/info")" ;;
  lint)
    need "${2:-}" "Need <api-id> <version-name>"
    id="$1"; ver="$2"; shift 2
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --severity|--category) qs_add "${1#--}" "$2"; shift 2 ;;
        *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
      esac
    done
    acp_api "$(with_query "$(acp_url "apis/$id/versions/$ver/spec/lint")")" ;;
  relint)
    need "${2:-}" "Need <api-id> <version-name>"
    acp_api -X POST "$(acp_url "apis/$1/versions/$2/spec/lintUpdate")" ;;
  delete-spec)
    need "${2:-}" "Need <api-id> <version-name>"
    acp_api -X DELETE "$(acp_url "apis/$1/versions/$2/spec")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
