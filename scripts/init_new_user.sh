#!/usr/bin/env sh
#
# init_new_user.sh — create a userpass user (HTTP / non-TLS).
#
# Both VAULT_NEW_USERNAME and VAULT_NEW_PASSWORD are required (no defaults, so
# no credential lives in the repo).
#
# Vault must already be initialized + unsealed (run vault_init.sh first) and you
# must be authenticated as root, or a token allowed to write auth/userpass/users:
#
#   docker cp scripts/init_new_user.sh vault:/tmp/init_new_user.sh
#   docker exec -it -e VAULT_NEW_USERNAME=<user> -e VAULT_NEW_PASSWORD=<pass> -e VAULT_TOKEN=<root token from vault_init.sh> vault sh /tmp/init_new_user.sh
#
set -e
export VAULT_ADDR="http://127.0.0.1:8004"

USERNAME="${VAULT_NEW_USERNAME:?set VAULT_NEW_USERNAME}"
PASSWORD="${VAULT_NEW_PASSWORD:?set VAULT_NEW_PASSWORD}"

# Users only authenticate — the bridge signs session JWTs with its own AppRole
# identity, so a plain `default` policy is all a human user needs.
vault write auth/userpass/users/"$USERNAME" password="$PASSWORD" token_policies="default"
vault read auth/userpass/users/"$USERNAME"
echo "Created userpass user: $USERNAME"
