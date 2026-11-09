#!/usr/bin/env sh
#
# create_group.sh — create an internal identity group (TLS / prod / Dennis).
#
# An internal group holds entities (users) as members and a set of policies that
# every member INHERITS at login. Membership is managed by add_user_to_group.sh;
# policies by add_policy_to_group.sh (or pass VAULT_GROUP_POLICIES here).
#
# Required: VAULT_GROUP_NAME.  Optional: VAULT_GROUP_POLICIES (comma-separated).
#
# Run as root (or a token with identity/group write):
#   docker cp scripts_tls/create_group.sh vault:/tmp/create_group.sh
#   docker exec -it -e VAULT_GROUP_NAME=analysts \
#     -e VAULT_GROUP_POLICIES=analyst-read vault sh /tmp/create_group.sh
#
set -e
export VAULT_ADDR="https://localhost:8004"
export VAULT_CACERT="/vault/tls/ca.crt"

: "${VAULT_GROUP_NAME:?set VAULT_GROUP_NAME, e.g. analysts}"

# Internal group => explicit entity membership; group policies are inherited by
# every member at login. Only set policies when given, so re-running without
# VAULT_GROUP_POLICIES never wipes an existing group's policy list.
if [ -n "${VAULT_GROUP_POLICIES:-}" ]; then
    vault write identity/group name="$VAULT_GROUP_NAME" type="internal" policies="$VAULT_GROUP_POLICIES"
else
    vault write identity/group name="$VAULT_GROUP_NAME" type="internal"
fi
vault read identity/group/name/"$VAULT_GROUP_NAME"
echo "Created/updated internal group: $VAULT_GROUP_NAME"
