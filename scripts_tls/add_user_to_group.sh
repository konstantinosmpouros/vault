#!/usr/bin/env sh
#
# add_user_to_group.sh — add a userpass user to an identity group (TLS / prod / Dennis).
#
# A userpass login maps to an identity ENTITY; the entity is what joins a group
# and inherits its policies, and an ALIAS binds the login to that entity. This
# reuses the entity Vault auto-creates on first login if present, else creates
# the entity + alias. member_entity_ids is replaced on write, so it appends.
#
# Required: VAULT_USERNAME, VAULT_GROUP_NAME.
#
# Run as root (or a token with identity/* write):
#   docker cp scripts_tls/add_user_to_group.sh vault:/tmp/add_user_to_group.sh
#   docker exec -it -e VAULT_USERNAME=konstantinosmpouros \
#     -e VAULT_GROUP_NAME=analysts vault sh /tmp/add_user_to_group.sh
#
set -e
export VAULT_ADDR="https://localhost:8004"
export VAULT_CACERT="/vault/tls/ca.crt"

: "${VAULT_USERNAME:?set VAULT_USERNAME (the userpass login name)}"
: "${VAULT_GROUP_NAME:?set VAULT_GROUP_NAME}"

ACCESSOR="$(vault auth list | awk '$1=="userpass/" {print $3}')"
[ -n "$ACCESSOR" ] || { echo "userpass auth method not found — enable it first"; exit 1; }

# Reuse the auto-created login entity if it exists; otherwise create entity+alias.
ENTITY_ID="$(vault write -field=id identity/lookup/entity \
    alias_name="$VAULT_USERNAME" alias_mount_accessor="$ACCESSOR" 2>/dev/null || true)"
if [ -z "$ENTITY_ID" ]; then
    vault write identity/entity name="$VAULT_USERNAME" >/dev/null
    ENTITY_ID="$(vault read -field=id identity/entity/name/"$VAULT_USERNAME")"
    vault write identity/entity-alias name="$VAULT_USERNAME" \
        canonical_id="$ENTITY_ID" mount_accessor="$ACCESSOR" >/dev/null
fi

EXISTING="$(vault read -field=member_entity_ids identity/group/name/"$VAULT_GROUP_NAME" 2>/dev/null | tr -d '[]')"
MEMBERS="$ENTITY_ID"
for id in $EXISTING; do
    [ "$id" = "$ENTITY_ID" ] && continue
    MEMBERS="$MEMBERS,$id"
done

vault write identity/group name="$VAULT_GROUP_NAME" member_entity_ids="$MEMBERS"
echo "Added '$VAULT_USERNAME' (entity $ENTITY_ID) to group '$VAULT_GROUP_NAME'"
