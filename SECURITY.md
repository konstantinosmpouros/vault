# Security Policy

## Scope

This repository holds a **local** HashiCorp Vault setup (compose, server config) and operator scripts. It is retired as a production dependency and is not deployed anywhere. Reports are still welcome for:

- a secret committed to the repo (token, unseal key, AppRole `secret_id`, password, certificate key);
- a script that leaks credentials (prints, logs or writes them where it should not);
- an insecure default in `config/` or `docker-compose.yaml`.

Vulnerabilities in Vault itself belong to HashiCorp: see <https://www.hashicorp.com/security>.

## Supported versions

Only the `main` branch is maintained.

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub's private reporting instead: **Security → Report a vulnerability** on this repository.

Include what you found, where (file and line, or commit), and how to reproduce it. You will get an acknowledgement within 7 days.

## If a secret was committed

Rotate first, purge second — rewriting history does not undo a leak that was already fetched or indexed.

1. Revoke or rotate it in Vault (`vault token revoke`, re-key, new `secret_id`, new password).
2. Then purge it from history with `git filter-repo` and force-push.

## Rules this repo follows

- `data/` (the live Raft database), `tls/`, keys and `.env` files are gitignored and must never be committed.
- Scripts take credentials from environment variables only — no defaults, no hardcoded values.
- Unseal keys and root tokens are printed once by the init scripts and never written to disk by them.
- CI runs [gitleaks](https://github.com/gitleaks/gitleaks) over the full history on every push and pull request.
