#!/usr/bin/env bash
# Governance dashboards and rule set reads.

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-governance.sh <subcommand> [args]

Scores and findings:
  api-scores --category SECURITY|QUALITY [--owner <org-id>] [--sort <field,dir>] [--page <n>] [--size <n>]   APIs with findings in that category
  org-scores [--page <n>] [--size <n>]
  rule-violations [--category SECURITY|QUALITY] [--page <n>] [--size <n>]     most violated rules
  shadow-apis [--owner <org-id>] [--page <n>] [--size <n>]                    APIs without a specification
  zombie-apis [--owner <org-id>] [--page <n>] [--size <n>]                    APIs without subscriptions for 90 days
  active-apis --from <YYYY-MM-DD> --until <YYYY-MM-DD>
  active-subscriptions --from <YYYY-MM-DD> --until <YYYY-MM-DD>
  api-subscriptions | application-subscriptions | product-subscriptions [--owner <org-id>] [--approvalStatus <s>] [--page <n>] [--size <n>]

Rule sets:
  rulesets [--text <t>] [--name <n>] [--enabled true|false] [--defaultRuleSet true|false] [--page <n>] [--size <n>]
  ruleset <ruleset-id>
  ruleset-rules <ruleset-id>            rule names, categories, severities (bare array)
  ruleset-file <ruleset-id> [--target-path <p>]   download the Spectral file (default active-development/rule_sets/<id>.yaml); built-in rule sets have none

Credentials from .env: BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID (or ACP_TOKEN); ACP_BASE_URL optional.
EOF
}
[[ -z "${1:-}" ]] && { usage; exit 0; }
help_requested "$@"

sub="$1"; shift
acp_init

range_query() {
  # --from / --until only (dates, both required), no default size
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from|--until) need "${2:-}" "$1 needs a YYYY-MM-DD value"; qs_add "${1#--}" "$2"; shift 2 ;;
      *) echo "ERROR: unexpected argument '$1'" >&2; exit 1 ;;
    esac
  done
  [[ "$QUERY" == *from=* && "$QUERY" == *until=* ]] || { echo "ERROR: --from and --until (YYYY-MM-DD) are required" >&2; exit 1; }
}

case "$sub" in
  api-scores)
    parse_query "$@"
    [[ "$QUERY" == *category=* ]] || { echo "ERROR: --category SECURITY|QUALITY is required" >&2; exit 1; }
    acp_api "$(with_query "$(acp_url governance/apiScores)")" ;;
  org-scores)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url governance/organizationScores)")" ;;
  rule-violations)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url governance/ruleViolations)")" ;;
  shadow-apis)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url governance/shadowApis)")" ;;
  zombie-apis)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url governance/zombieApis)")" ;;
  active-apis)
    range_query "$@"
    acp_api "$(with_query "$(acp_url governance/activeApis)")" ;;
  active-subscriptions)
    range_query "$@"
    acp_api "$(with_query "$(acp_url governance/activeSubscriptions)")" ;;
  api-subscriptions)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url governance/apiSubscriptions)")" ;;
  application-subscriptions)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url governance/applicationSubscriptions)")" ;;
  product-subscriptions)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url governance/productSubscriptions)")" ;;
  rulesets)
    parse_query "$@"
    acp_api "$(with_query "$(acp_url ruleSets)")" ;;
  ruleset)
    need "${1:-}" "Need <ruleset-id>"
    acp_api "$(acp_url "ruleSets/$1")" ;;
  ruleset-rules)
    need "${1:-}" "Need <ruleset-id>"
    acp_api "$(acp_url "ruleSets/$1/ruleInfos")" ;;
  ruleset-file)
    need "${1:-}" "Need <ruleset-id>"; id="$1"; shift
    target=""
    [[ "${1:-}" == "--target-path" ]] && target="${2:-}"
    [[ -z "$target" ]] && target="active-development/rule_sets/${id}.yaml"
    acp_api --raw "$(acp_url "ruleSets/$id/file")"
    acp_ok || finish
    [[ -n "$RESPONSE_BODY" ]] || { echo "ERROR: rule set $id has no downloadable file (built-in rule sets return an empty body)." >&2; exit 1; }
    mkdir -p "$(dirname "$target")"
    printf '%s\n' "$RESPONSE_BODY" > "$target"
    echo "Saved to: $target"
    exit 0 ;;
  *) usage >&2; exit 1 ;;
esac

finish
