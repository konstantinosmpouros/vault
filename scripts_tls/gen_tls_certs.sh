#!/usr/bin/env sh
#
# gen_tls_certs.sh — create a private CA and a Vault server certificate for the
# TLS variant. Runs on the HOST (needs openssl), not inside the container.
#
# Writes into ./tls/ (gitignored):
#   ca.key   CA private key        — keep offline, never mount it into Vault
#   ca.crt   CA certificate        — clients trust this (VAULT_CACERT)
#   tls.key  server private key    — mounted read-only into Vault
#   tls.crt  server certificate    — SANs: DNS vault, DNS localhost (no IP SAN)
#
# Refuses to overwrite existing files. Usage, from the repo root:
#   sh scripts_tls/gen_tls_certs.sh
#
# Optional env: VAULT_TLS_DIR (default ./tls), VAULT_TLS_DAYS (default 825).
#
set -e
# Git Bash on Windows would rewrite "/CN=..." into a file path; no effect elsewhere.
export MSYS_NO_PATHCONV=1
DIR="${VAULT_TLS_DIR:-./tls}"
DAYS="${VAULT_TLS_DAYS:-825}"

if [ -e "$DIR/ca.key" ] || [ -e "$DIR/tls.key" ]; then
    echo "Refusing to overwrite: $DIR already holds keys. Remove them first to re-issue." >&2
    exit 1
fi
mkdir -p "$DIR"
umask 077

# --- CA ----------------------------------------------------------------------
openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 3650 \
    -keyout "$DIR/ca.key" -out "$DIR/ca.crt" \
    -subj "/CN=vault-local-ca" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"

# --- server cert ---------------------------------------------------------------
openssl req -newkey rsa:2048 -sha256 -nodes \
    -keyout "$DIR/tls.key" -out "$DIR/tls.csr" -subj "/CN=vault"

EXT="$DIR/tls.ext"
printf '%s\n' \
    "basicConstraints=critical,CA:FALSE" \
    "keyUsage=critical,digitalSignature,keyEncipherment" \
    "extendedKeyUsage=serverAuth" \
    "subjectAltName=DNS:vault,DNS:localhost" > "$EXT"

openssl x509 -req -sha256 -days "$DAYS" \
    -in "$DIR/tls.csr" -CA "$DIR/ca.crt" -CAkey "$DIR/ca.key" -CAcreateserial \
    -extfile "$EXT" -out "$DIR/tls.crt"

rm -f "$DIR/tls.csr" "$EXT" "$DIR/ca.srl"
chmod 600 "$DIR/ca.key" "$DIR/tls.key"
chmod 644 "$DIR/ca.crt" "$DIR/tls.crt"

echo "Wrote $DIR/{ca.key,ca.crt,tls.key,tls.crt}"
echo "Vault runs as uid 100: on a Linux host run  sudo chown 100:100 $DIR/tls.key  before starting it."
