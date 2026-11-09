#!/usr/bin/env sh
#
# vault_init.sh — bootstrap a FRESH local Vault (HTTP / non-TLS).
#
# What it does (and nothing user-specific):
#   1. Initialize Vault, unseal it, and PRINT the unseal keys + root token.
#      >>> SAVE THE PRINTED KEYS <<< — you need any 2 of the 3 to unseal Vault
#      again if it seals (it seals on every container restart). Re-unseal steps
#      are printed at the end.
#   2. Enable the auth methods + secrets engines the platform needs: userpass
#      (human login) and a Transit RSA key the bridge signs session JWTs with
#      (the private key never leaves Vault).
#   3. Create the bridge's AppRole machine identity and PRINT its role_id /
#      secret_id — put them in the app .env as VAULT_ROLE_ID / VAULT_SECRET_ID.
#
# It does NOT create any user account — see init_new_user.sh for that.
#
# Run against a fresh, started Vault container:
#   docker cp scripts/vault_init.sh vault:/tmp/vault_init.sh
#   docker exec -it vault sh /tmp/vault_init.sh
#
set -e
export VAULT_ADDR="http://127.0.0.1:8004"

# --- 1. Initialize + unseal + print keys -----------------------------------
INIT_OUT="$(vault operator init -key-shares=3 -key-threshold=2)"
echo "================= SAVE THESE — needed to unseal Vault again ================="
echo "$INIT_OUT"
echo "============================================================================="

UNSEAL_1="$(printf '%s\n' "$INIT_OUT" | awk '/^Unseal Key 1:/ {print $4}')"
UNSEAL_2="$(printf '%s\n' "$INIT_OUT" | awk '/^Unseal Key 2:/ {print $4}')"
ROOT_TOKEN="$(printf '%s\n' "$INIT_OUT" | awk '/^Initial Root Token:/ {print $4}')"

vault operator unseal "$UNSEAL_1"
vault operator unseal "$UNSEAL_2"
vault login "$ROOT_TOKEN" >/dev/null

# --- 2. Auth methods + engines (no users) ----------------------------------
vault auth enable userpass
vault auth tune -max-lease-ttl=24h -default-lease-ttl=4h userpass/

vault secrets enable transit
vault write transit/keys/jwt-rs256 type=rsa-2048   # exportable defaults to false — key never leaves Vault

cat >/tmp/magenticx_bridge_jwt.hcl <<'HCL'
path "transit/sign/jwt-rs256" { capabilities = ["update"] }
path "transit/keys/jwt-rs256" { capabilities = ["read"] }
# Read identity entity metadata (the `email` key) so a Vault login can be linked
# to the same user's Microsoft (Entra) login — a userpass username can't be an
# email, so the link email lives on the entity.
path "identity/entity/id/*" { capabilities = ["read"] }
HCL
vault policy write magenticx_bridge_jwt /tmp/magenticx_bridge_jwt.hcl

# --- 3. Bridge AppRole machine identity ------------------------------------
vault auth enable approle
vault write auth/approle/role/magenticx-bridge \
    token_policies="magenticx_bridge_jwt" \
    token_ttl=1h token_max_ttl=4h \
    secret_id_ttl=0 secret_id_num_uses=0

echo "================ bridge AppRole creds — put these in the app .env ==============="
echo "VAULT_ROLE_ID=$(vault read -field=role_id auth/approle/role/magenticx-bridge/role-id)"
echo "VAULT_SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/magenticx-bridge/secret-id)"
echo "============================================================================="

cat <<'NOTE'

Next steps:
  - Put the two VAULT_ROLE_ID / VAULT_SECRET_ID lines above into the app .env
  - Create the first user:  docker exec -it vault sh /tmp/init_new_user.sh
  - Re-unseal after a restart (Vault seals on restart) with any 2 of the keys:
        export VAULT_ADDR=http://127.0.0.1:8004
        vault operator unseal <UNSEAL_KEY_1>
        vault operator unseal <UNSEAL_KEY_2>
NOTE
