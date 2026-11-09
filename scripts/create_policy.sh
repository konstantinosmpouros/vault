#!/usr/bin/env sh
#
# create_policy.sh — write an ACL policy (HTTP / non-TLS).
#
# A policy is a named set of path capabilities. Attach it to a user, an entity,
# or a group (see add_policy_to_group.sh / add_user_to_group.sh).
#
# Required: VAULT_POLICY_NAME, and either VAULT_POLICY_FILE (an .hcl path inside
# the container) or VAULT_POLICY_HCL (the policy body inline).
#
# Run as root (or a token with sys/policies/acl write):
#   docker cp scripts/create_policy.sh vault:/tmp/create_policy.sh
#   docker exec -it \
#     -e VAULT_POLICY_NAME=analyst-read \
#     -e VAULT_POLICY_HCL='path "secret/data/analyst/*" { capabilities = ["read","list"] }' \
#     vault sh /tmp/create_policy.sh
#
set -e
export VAULT_ADDR="http://127.0.0.1:8004"

: "${VAULT_POLICY_NAME:?set VAULT_POLICY_NAME, e.g. analyst-read}"
if [ -n "${VAULT_POLICY_HCL:-}" ]; then
    VAULT_POLICY_FILE="/tmp/${VAULT_POLICY_NAME}.hcl"
    printf '%s\n' "$VAULT_POLICY_HCL" > "$VAULT_POLICY_FILE"
fi
: "${VAULT_POLICY_FILE:?set VAULT_POLICY_FILE=/path.hcl or VAULT_POLICY_HCL='path \"...\" { capabilities = [\"read\"] }'}"

vault policy write "$VAULT_POLICY_NAME" "$VAULT_POLICY_FILE"
vault policy read "$VAULT_POLICY_NAME"
echo "Wrote policy: $VAULT_POLICY_NAME"
