#!/usr/bin/env bash
# Shared utilities for boomi-api-control-plane CLI tools; sourced, not executed directly.

set -euo pipefail

# --- Environment ---

load_env() {
  local env_file=".env"
  if [[ ! -f "$env_file" ]]; then
    echo "ERROR: .env file not found in $(pwd)" >&2
    exit 1
  fi
  # No set -a: .env values stay in-shell. Trace off: xtrace would echo every assignment.
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  set +x
  source "$env_file"
  if (( _xtrace_enabled )); then set -x; fi
}

# The one by-name expansion in the skill; ${!name} lands the value in a traced command.
var_is_set() {
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  set +x
  local rc=0
  [[ -n "${!1:-}" ]] || rc=1
  if (( _xtrace_enabled )); then set -x; fi
  return $rc
}

require_env() {
  local missing=()
  for var in "$@"; do
    var_is_set "$var" || missing+=("$var")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required environment variables: ${missing[*]}" >&2
    echo "Check your .env file." >&2
    exit 1
  fi
}

require_tools() {
  local missing=()
  for tool in "$@"; do
    command -v "$tool" &>/dev/null || missing+=("$tool")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools: ${missing[*]}" >&2
    exit 1
  fi
}

# Standard preamble for every script: .env, curl, base URL, bearer token.
acp_init() {
  load_env
  require_tools curl
  acp_resolve_base_url
  acp_resolve_token
}

# ACP_BASE_URL when set, else derived from the account ID (lowercase, _ to -) on the na region.
acp_resolve_base_url() {
  var_is_set ACP_BASE_URL && return 0
  require_env BOOMI_ACCOUNT_ID
  local sub
  sub=$(printf '%s' "$BOOMI_ACCOUNT_ID" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  ACP_BASE_URL="https://${sub}.backend.na.controlplane.boomi.com"
}

# ACP_TOKEN when set, else a Boomi platform JWT from BOOMI_* (five-minute lifetime; acp_api refreshes it).
ACP_TOKEN_SOURCE="pat"
ACP_TOKEN_ISSUED=0
ACP_JWT_REFRESH_SECONDS=240  # JWT lifetime is 300 s
acp_resolve_token() {
  var_is_set ACP_TOKEN && return 0
  require_env BOOMI_USERNAME BOOMI_API_TOKEN BOOMI_ACCOUNT_ID
  ACP_TOKEN_SOURCE="jwt"
  acp_fetch_jwt
}

acp_fetch_jwt() {
  # Fence xtrace: the platform credentials are expanded below.
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  set +x

  local ssl_flag=""
  [[ "${BOOMI_VERIFY_SSL:-true}" == "false" ]] && ssl_flag="-k"
  # Body and status stay in memory: the body is the credential, so it never touches disk or stderr.
  local out code rc
  set +e
  out=$(curl_cfg user "BOOMI_TOKEN.${BOOMI_USERNAME}:${BOOMI_API_TOKEN}" \
    | curl -s $ssl_flag --max-time "${BOOMI_TIMEOUT:-60}" -A "$ACP_USER_AGENT" -K - \
        -w $'\n%{http_code}' \
        "${BOOMI_API_URL:-https://api.boomi.com}/auth/jwt/generate/${BOOMI_ACCOUNT_ID}")
  rc=$?
  set -e
  code="${out##*$'\n'}"
  if (( rc != 0 )) || [[ "$code" != "200" ]]; then
    echo "ERROR: could not obtain a Boomi platform JWT (curl exit ${rc}, HTTP ${code:-000})." >&2
    echo "  Check BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID, and BOOMI_API_URL, or set ACP_TOKEN." >&2
    exit 1
  fi
  ACP_TOKEN="${out%$'\n'*}"
  ACP_TOKEN_ISSUED=$(date +%s)

  if (( _xtrace_enabled )); then set -x; fi
}

# --- Argument handling ---

help_requested() {
  local arg
  for arg in "$@"; do
    case "$arg" in --help|-h) usage; exit 0 ;; esac
  done
}

need() {
  # need <value> <message>
  [[ -n "${1:-}" ]] || { echo "ERROR: $2" >&2; exit 1; }
}

# --- Version ---

_skill_version() {
  cat "$(dirname "${BASH_SOURCE[0]}")/../VERSION" 2>/dev/null || echo "unknown"
}

ACP_USER_AGENT="boomi-companion/boomi-api-control-plane/$(_skill_version)"

# --- URL and query helpers ---

acp_url() {
  echo "${ACP_BASE_URL%/}/$1"
}

# Percent-encode a query value (unreserved chars pass through).
urlencode() {
  local s="$1" i c out=""
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$out"
}

# Accumulates QUERY from --key value pairs; repeated keys become repeated params.
QUERY=""
qs_add() {
  QUERY+="${QUERY:+&}$1=$(urlencode "$2")"
}

# Parse remaining args as --key value into QUERY. Sets default size when not given.
# Usage: parse_query "$@"
parse_query() {
  local has_size=0 key
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --*)
        key="${1#--}"
        [[ $# -ge 2 ]] || { echo "ERROR: $1 needs a value" >&2; exit 1; }
        [[ "$key" == "size" ]] && has_size=1
        qs_add "$key" "$2"
        shift 2 ;;
      *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
    esac
  done
  (( has_size )) || qs_add size 50
}

with_query() {
  # with_query <url>  -> url?QUERY
  if [[ -n "$QUERY" ]]; then echo "$1?$QUERY"; else echo "$1"; fi
}

# --- Request bodies ---

# Resolve a JSON argument to a file path: an existing file is used as-is, anything else is
# treated as inline JSON written to a temp file removed on exit.
BODY_FILE=""
json_body() {
  if [[ -f "$1" ]]; then
    BODY_FILE="$1"
  else
    BODY_FILE=$(mktemp)
    trap 'rm -f "$BODY_FILE"' EXIT
    printf '%s' "$1" > "$BODY_FILE"
  fi
}

# --- API helpers ---

# Emits a curl config file on stdout for `curl -K -`, keeping credentials out of argv.
curl_cfg() {
  (( $# % 2 == 0 )) || { echo "ERROR: curl_cfg needs directive/value pairs" >&2; return 1; }
  local val
  while [[ $# -gt 1 ]]; do
    val="$2"
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    printf '%s = "%s"\n' "$1" "$val"
    shift 2
  done
}

# Sets RESPONSE_BODY and RESPONSE_CODE. Bearer token reaches curl via stdin config, so
# stdin is reserved: never pipe into acp_api or acp_fetch_jwt, or use @- bodies.
# `--raw` as first arg skips the JSON Accept header (file downloads).
RESPONSE_BODY=""
RESPONSE_CODE=""
acp_api() {
  # Fence xtrace: the token is expanded below.
  local _xtrace_enabled=0
  case $- in *x*) _xtrace_enabled=1 ;; esac
  set +x

  if [[ "$ACP_TOKEN_SOURCE" == "jwt" ]] && (( $(date +%s) - ACP_TOKEN_ISSUED > ACP_JWT_REFRESH_SECONDS )); then
    acp_fetch_jwt
  fi

  local accept_args=(-H "Accept: application/json")
  if [[ "${1:-}" == "--raw" ]]; then accept_args=(); shift; fi

  local ssl_flag=""
  [[ "${BOOMI_VERIFY_SSL:-true}" == "false" ]] && ssl_flag="-k"

  local tmpfile
  tmpfile=$(mktemp)

  local rc
  set +e
  RESPONSE_CODE=$(curl_cfg header "Authorization: Bearer ${ACP_TOKEN}" \
    | curl -s $ssl_flag \
        --max-time "${BOOMI_TIMEOUT:-60}" \
        -A "$ACP_USER_AGENT" \
        -K - \
        "${accept_args[@]+"${accept_args[@]}"}" \
        -o "$tmpfile" -w "%{http_code}" \
        "$@")
  rc=$?
  set -e
  RESPONSE_BODY=$(cat "$tmpfile")
  rm -f "$tmpfile"

  if (( _xtrace_enabled )); then set -x; fi

  if (( rc != 0 )) || [[ -z "$RESPONSE_CODE" || "$RESPONSE_CODE" == "000" ]]; then
    echo "ERROR: could not reach the API Control Plane -- network or connection failure (curl exit ${rc})." >&2
    echo "  Check ACP_BASE_URL, network, and BOOMI_TIMEOUT (${BOOMI_TIMEOUT:-60}s)." >&2
    return 1
  fi
  return 0
}

# Unauthenticated GET (serverInfo, saasInfo, login/options).
acp_public_get() {
  local tmpfile rc
  tmpfile=$(mktemp)
  set +e
  RESPONSE_CODE=$(curl -s --max-time "${BOOMI_TIMEOUT:-60}" -A "$ACP_USER_AGENT" \
    -H "Accept: application/json" -o "$tmpfile" -w "%{http_code}" "$1")
  rc=$?
  set -e
  RESPONSE_BODY=$(cat "$tmpfile")
  rm -f "$tmpfile"
  (( rc == 0 )) && [[ -n "$RESPONSE_CODE" && "$RESPONSE_CODE" != "000" ]]
}

acp_ok() {
  (( RESPONSE_CODE >= 200 && RESPONSE_CODE < 300 ))
}

# Print body on success (or a status line for empty 2xx), error + body on failure.
finish() {
  if ! acp_ok; then
    echo "ERROR: HTTP $RESPONSE_CODE" >&2
    echo "$RESPONSE_BODY" >&2
    exit 1
  fi
  if [[ -z "$RESPONSE_BODY" ]]; then
    echo "OK (HTTP $RESPONSE_CODE)"
  else
    echo "$RESPONSE_BODY"
  fi
}

# First string value for a JSON key in RESPONSE_BODY (flat scan, first match).
json_str() {
  printf '%s' "$RESPONSE_BODY" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1
}

# --- Deploy and async helpers ---

# POST <path>/deploy (sync) or <path>/deploy/async then wait, per flags.
# Usage: run_deploy <resource-path-without-trailing-slash> [--async] [--no-wait]
run_deploy() {
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
    acp_api -X POST "$(acp_url "$path/deploy/async")"
    acp_ok || finish
    local job_id
    job_id=$(json_str id)
    echo "Job: $job_id"
    if (( wait )); then wait_for_job "$job_id"; fi
  else
    acp_api -X POST "$(acp_url "$path/deploy")"
    finish
  fi
}

# Poll a job id until terminal. Checks /jobs/{id}, then /boomi-jobs/{id} on 404.
# Terminal: SUCCEEDED, FAILED, DELETED (jobs) / COMPLETED, DISCARDED, CANCELLED (boomi-jobs).
wait_for_job() {
  local id="$1" deadline attempt state
  local interval=3 timeout=300
  deadline=$(( $(date +%s) + timeout ))
  while :; do
    acp_api "$(acp_url "jobs/$id")"
    if (( RESPONSE_CODE == 404 )); then
      acp_api "$(acp_url "boomi-jobs/$id")"
    fi
    acp_ok || { echo "ERROR: HTTP $RESPONSE_CODE polling job $id" >&2; echo "$RESPONSE_BODY" >&2; return 1; }
    state=$(json_str jobStatus)
    [[ -z "$state" ]] && state=$(json_str state)
    case "$state" in
      SUCCEEDED|COMPLETED) echo "$RESPONSE_BODY"; return 0 ;;
      FAILED|DELETED|DISCARDED|CANCELLED) echo "ERROR: job $id ended in state $state" >&2; echo "$RESPONSE_BODY" >&2; return 1 ;;
    esac
    if (( $(date +%s) >= deadline )); then
      echo "ERROR: job $id still '${state:-unknown}' after ${timeout}s" >&2
      echo "$RESPONSE_BODY" >&2
      return 1
    fi
    sleep "$interval"
  done
}
