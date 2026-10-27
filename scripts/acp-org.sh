#!/usr/bin/env bash
# Organization operations.

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-org.sh <subcommand> [args]

Subcommands:
  list [--text <t>] [--name <n>] [--type BOTH|CONSUMER|PUBLISHER] [--parent <id>] [--page <n>] [--size <n>] [--sort <field,asc|desc>]
  get <org-id>
  default                                  the tenant's default organization
  create <json-file|json-string>           required: name, displayName, email; optional: description, parent, type
  update <org-id> <json-file|json-string>  full DTO (send writable fields only)
  delete <org-id>
  publish-environments <org-id>            environments this org may publish to
  subscribe-environments <org-id>          environments this org may subscribe in

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
    acp_api "$(with_query "$(acp_url organizations)")" ;;
  get)
    need "${1:-}" "Need <org-id>"
    acp_api "$(acp_url "organizations/$1")" ;;
  default)
    acp_api "$(acp_url organizations/default)" ;;
  create)
    need "${1:-}" "Need <json-file|json-string>"
    json_body "$1"
    acp_api -X POST -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url organizations)" ;;
  update)
    need "${2:-}" "Need <org-id> <json-file|json-string>"
    json_body "$2"
    acp_api -X PUT -H "Content-Type: application/json" --data-binary "@$BODY_FILE" "$(acp_url "organizations/$1")" ;;
  delete)
    need "${1:-}" "Need <org-id>"
    acp_api -X DELETE "$(acp_url "organizations/$1")" ;;
  publish-environments)
    need "${1:-}" "Need <org-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "organizations/$id/publishEnvironments")")" ;;
  subscribe-environments)
    need "${1:-}" "Need <org-id>"; id="$1"; shift
    parse_query "$@"
    acp_api "$(with_query "$(acp_url "organizations/$id/subscribeEnvironments")")" ;;
  *) usage >&2; exit 1 ;;
esac

finish
