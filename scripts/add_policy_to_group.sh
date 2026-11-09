#!/usr/bin/env sh
#
# add_policy_to_group.sh — attach a policy to a group, preserving existing ones
# (HTTP / non-TLS).
#
# identity/group REPLACES the policies list on write, so this reads the current
# set and appends (deduped) rather than clobbering it.
#
# Required: VAULT_GROUP_NAME, VAULT_POLICY_NAME.
#
# Run as root (or a token with identity/group read+write):
#   docker cp scripts/add_policy_to_group.sh vault:/tmp/add_policy_to_group.sh
#   docker exec -it -e VAULT_GROUP_NAME=analysts \
#     -e VAULT_POLICY_NAME=analyst-read vault sh /tmp/add_policy_to_group.sh
#
set -e
export VAULT_ADDR="http://127.0.0.1:8004"

: "${VAULT_GROUP_NAME:?set VAULT_GROUP_NAME}"
: "${VAULT_POLICY_NAME:?set VAULT_POLICY_NAME}"

EXISTING="$(vault read -field=policies identity/group/name/"$VAULT_GROUP_NAME" 2>/dev/null | tr -d '[]')"
NEW="$VAULT_POLICY_NAME"
for p in $EXISTING; do
    [ "$p" = "$VAULT_POLICY_NAME" ] && continue
    NEW="$NEW,$p"
done

vault write identity/group name="$VAULT_GROUP_NAME" policies="$NEW"
echo "Group '$VAULT_GROUP_NAME' policies are now: $NEW"
