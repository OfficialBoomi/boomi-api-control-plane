#!/usr/bin/env bash
# Verify .env keys and reach the API Control Plane tenant.

source "$(dirname "$0")/acp-common.sh"

usage() {
  cat <<'EOF'
Usage: acp-env-check.sh [--help]

Resolves the credential and base URL from .env, then:
  - GET /serverInfo and /saasInfo (unauthenticated): tenant, version, tier, Boomi/CAM links
  - GET /users/current (authenticated): confirms the token and shows the user's role and organization
  - GET /tierLimits (authenticated): API and portal counts against tier limits

Credential: ACP_TOKEN when set, else a platform JWT from BOOMI_USERNAME, BOOMI_API_TOKEN, BOOMI_ACCOUNT_ID.
Base URL: ACP_BASE_URL when set, else derived from BOOMI_ACCOUNT_ID (na region).
EOF
}
help_requested "$@"

load_env
require_tools curl

echo "=== Environment ==="
for v in ACP_BASE_URL ACP_TOKEN BOOMI_USERNAME BOOMI_API_TOKEN BOOMI_ACCOUNT_ID; do
  if var_is_set "$v"; then echo "  $v=SET"; else echo "  $v=UNSET"; fi
done
acp_resolve_base_url
acp_resolve_token
echo "  Base URL: ${ACP_BASE_URL%/}"
if [[ "$ACP_TOKEN_SOURCE" == "jwt" ]]; then
  echo "  Credential: Boomi platform JWT from BOOMI_* (obtained OK)"
else
  echo "  Credential: ACP_TOKEN"
fi

echo
echo "=== Tenant (unauthenticated) ==="
for p in serverInfo saasInfo; do
  url="$(acp_url "$p")"
  if acp_public_get "$url" && acp_ok; then
    echo "  GET /$p -- HTTP $RESPONSE_CODE"
    echo "  $RESPONSE_BODY"
  else
    echo "  GET /$p -- HTTP ${RESPONSE_CODE:-000} FAIL" >&2
    echo "  $RESPONSE_BODY" >&2
    exit 1
  fi
done

echo
echo "=== Token (authenticated) ==="
acp_api "$(acp_url users/current)" || exit 1
if ! acp_ok; then
  echo "  GET /users/current -- HTTP $RESPONSE_CODE FAIL" >&2
  echo "  $RESPONSE_BODY" >&2
  exit 1
fi
echo "  GET /users/current -- HTTP $RESPONSE_CODE OK (user: $(json_str username), role: $(json_str role))"
echo "  $RESPONSE_BODY"

acp_api "$(acp_url tierLimits)" || exit 1
if acp_ok; then
  echo "  GET /tierLimits -- HTTP $RESPONSE_CODE"
  echo "  $RESPONSE_BODY"
else
  echo "  GET /tierLimits -- HTTP $RESPONSE_CODE (non-fatal; token may lack ACCESS_TENANT_DATA)"
fi
