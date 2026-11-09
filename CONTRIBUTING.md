# Contributing

Thanks for your interest. This repo is small and in maintenance mode (see [README § Status](README.md#status)), so keep changes focused.

## Before you start

- Open an issue first for anything larger than a typo or a one-script fix.
- Security problems go through [SECURITY.md](SECURITY.md), never a public issue.

## Making a change

1. Fork and branch from `main`.
2. Test against a **throwaway** local Vault:
   ```sh
   docker compose up -d
   docker cp scripts/<script>.sh vault:/tmp/<script>.sh
   docker exec -it -e VAULT_TOKEN=<root token> vault sh /tmp/<script>.sh
   docker compose down && rm -rf data/   # reset afterwards
   ```
3. Open a pull request using the template. CI (ShellCheck, compose/config validation, LF check, gitleaks) must pass.

## Conventions

| Area | Rule |
| --- | --- |
| Commits / PR titles | [Conventional Commits](https://www.conventionalcommits.org/): `feat(scripts): subject`, `fix(config): subject`, `docs: subject`. No `!`. |
| Line endings | LF everywhere (enforced by `.gitattributes`). A CRLF shell script breaks in the Linux container. |
| Shell | POSIX `sh` — the Vault image is Alpine/BusyBox. No bash-isms, no `jq`. Start with `set -e`. |
| Script pairs | `scripts/` and `scripts_tls/` are mirrors. Change both; only the connection header differs. |
| Idempotency | Every script must be safe to run twice. |
| Secrets | Credentials come from environment variables only (`${VAR:?set VAR}`). Never add a default value; never echo a secret unless handing it over once is the script's purpose (init). |
| Docs | Each script's header lists its env vars and a `docker cp` / `docker exec` example. Update the README tables when a script is added or its inputs change. |

## License

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
