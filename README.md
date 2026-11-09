# Vault — identity & secrets

Single-node HashiCorp Vault (Raft storage) that runs **with or without TLS**, plus idempotent operator scripts for `userpass` login, Transit JWT signing, AppRole machine identity and group-based RBAC.

> **Status:** retired from mAgenticX with plan 29 (Entra SSO + OCI KMS signing). See [Status](#status).

HashiCorp Vault is mAgenticX's **identity provider** and **JWT signing backend**. It plays three distinct roles:

| Role | Vault feature | Used by |
| --- | --- | --- |
| **Human login** (verify username/password) | `userpass` auth method | bridge `VaultUserpassProvider` → `VaultAuthenticator` |
| **Session-JWT signing** (RSA private key never leaves Vault) | `transit` engine, key `jwt-rs256` | bridge `VaultServiceClient.sign()` |
| **Bridge machine identity** (so the bridge can call Transit) | `approle` role `magenticx-bridge` | bridge `VaultServiceClient` (AppRole login) |

The user logs in with userpass; the bridge then mints its **own** stateless RS256 session JWT (signed via Transit, using its AppRole token) and hands it to the browser as cookies. The full request flow is documented in the mAgenticX repo (`docs/flows/authentication-and-session.md`).

---

## Status

| | |
| --- | --- |
| **Consumers** | None. mAgenticX moved to Microsoft Entra sign-in + OCI KMS signing (plan 29, 2026-09-27). |
| **Production** | Not deployed. The old Swarm stack was removed from the VM on purpose. |
| **This repo** | A single-node Vault in two variants — **HTTP** and **TLS** — with compose files, server configs and operator scripts for each, plus the record of the old identity model. |

## Two variants: HTTP and TLS

| | HTTP | TLS |
| --- | --- | --- |
| Use for | Local development | Anything beyond your own machine (it was the production setup) |
| Compose | `docker-compose.yaml` | `docker-compose.tls.yaml` |
| Server config | `config/http.json` | `config/tls.json` (cert, key, CA from `./tls/`) |
| Certificates | — | `scripts_tls/gen_tls_certs.sh` → private CA + server cert in `./tls/` |
| Operator scripts | `scripts/` | `scripts_tls/` |
| `VAULT_ADDR` | `http://127.0.0.1:8004` | `https://localhost:8004` (or `https://vault:8004`) |

Both listen on `:8004` inside the `vault` network only, store data in `./data` (Raft), and use the same container name, so run **one at a time**. Nothing is published to the host — operate Vault with `docker exec`.

## Quick start

Requires Docker with Compose v2. The TLS variant also needs `openssl` on the host.

### HTTP

```sh
docker compose up -d
docker cp scripts/vault_init.sh vault:/tmp/vault_init.sh
docker exec -it vault sh /tmp/vault_init.sh           # FRESH data/ only — prints unseal keys + root token
```

### TLS

```sh
sh scripts_tls/gen_tls_certs.sh                       # once — writes ./tls/{ca.key,ca.crt,tls.key,tls.crt}
sudo chown 100:100 tls/tls.key                        # Linux hosts only: Vault runs as uid 100
docker compose -f docker-compose.tls.yaml up -d
docker cp scripts_tls/vault_tls_init.sh vault:/tmp/vault_tls_init.sh
docker exec -it vault sh /tmp/vault_tls_init.sh       # FRESH data/ only
```

- **Store the unseal keys and root token offline.** They are printed once and cannot be recovered.
- `data/` and `tls/` are created locally and gitignored. `tls/ca.key` is not mounted into Vault — keep it offline.
- A restarted Vault comes back **sealed** — see [Operational lifecycle](#operational-lifecycle).

## Repository files

| File | What |
| --- | --- |
| `docker-compose.yaml` / `docker-compose.tls.yaml` | Single-node Vault, HTTP / TLS |
| `config/http.json` / `config/tls.json` | Server config: Raft storage, listener `:8004`, UI on |
| `scripts/` / `scripts_tls/` | Operator scripts over HTTP / HTTPS; `scripts_tls/gen_tls_certs.sh` issues the certs |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to propose changes |
| [SECURITY.md](SECURITY.md) | How to report a vulnerability or a leaked secret |
| [LICENSE](LICENSE) | MIT |

---

## Folder layout

```
vault/
├── docker-compose.yaml       # HTTP variant
├── docker-compose.tls.yaml   # TLS variant
├── config/
│   ├── http.json             # listener without TLS
│   └── tls.json              # listener with cert / key / client CA from /vault/tls
├── scripts/                  # operator scripts, HTTP
├── scripts_tls/              # the same scripts over HTTPS + gen_tls_certs.sh
├── data/                     # Raft storage (runtime, gitignored)
└── tls/                      # generated CA + server cert (runtime, gitignored)
```

`scripts/` and `scripts_tls/` are mirror images — identical logic, the only difference is the connection header:

| | `scripts/` (HTTP) | `scripts_tls/` (TLS) |
| --- | --- | --- |
| `VAULT_ADDR` | `http://127.0.0.1:8004` | `https://localhost:8004` |
| `VAULT_CACERT` | — | `/vault/tls/ca.crt` |

> **TLS gotcha:** for the TLS variant use `https://vault:8004` or `https://localhost:8004` — **never `https://127.0.0.1:8004`**. The server cert has DNS SANs (`vault`, `localhost`) but **no IP SAN**, so connecting by IP fails with `x509: … doesn't contain any IP SANs`.

The `data/` directory (raft storage) is **runtime state** — it is the actual Vault database and must not be committed or shared.

---

## The identity model — policies vs users vs groups

This is the part that's easy to get wrong. In Vault, **a policy is a named set of path capabilities**, and it can be attached at three levels — all **additive** at login:

```
                       ┌─ token_policies on the userpass user  (e.g. "default")
effective policies  ───┼─ policies on the user's identity ENTITY
   (union at login)    └─ policies on every GROUP the entity belongs to   ← RBAC lives here
```

So the answer to "are policies on a group or a user?" is **both are possible** — but the scalable, RBAC-style pattern is **policy → group → users(entities) as members**:

- A **policy** grants capabilities (`analyst-read`).
- A **group** (internal) holds member entities and a list of policies; **every member inherits the group's policies** at login.
- A **userpass user** is represented by an identity **entity**; an **alias** binds the `userpass` login to that entity. The *entity* (not the raw username) is what joins a group.

```
policy ──attached to──> group ──has member──> entity ──alias──> userpass login
```

When `konstantinosmpouros` (in group `analysts`, which has policy `analyst-read`) logs in, their token's effective policies = `["default", "analyst-read"]`.

---

## Scripts

Every script is run inside the Vault container and is **idempotent**. Pattern:

```sh
docker cp <folder>/<script>.sh vault:/tmp/<script>.sh
docker exec -it [-e VAR=value ...] vault sh /tmp/<script>.sh
```

All scripts require you to be authenticated as **root** (or a token with the relevant capabilities). Each script's header documents its exact env vars + an example.

### Bootstrap (run once per Vault)

| Script | Purpose |
| --- | --- |
| `vault_init.sh` / `vault_tls_init.sh` | Initialize + unseal a **fresh** Vault, print the unseal keys + root token, then enable `userpass`, the Transit `jwt-rs256` key, the `magenticx_bridge_jwt` policy, and the `magenticx-bridge` AppRole. Prints the AppRole `role_id`/`secret_id`. |
| `init_new_user.sh` / `init_tls_new_user.sh` | Create a `userpass` user (`VAULT_NEW_USERNAME` / `VAULT_NEW_PASSWORD`, both required). |

### RBAC (run as needed)

| Script | Required env | Does |
| --- | --- | --- |
| `create_policy.sh` | `VAULT_POLICY_NAME` + (`VAULT_POLICY_FILE` or `VAULT_POLICY_HCL`) | `vault policy write` |
| `create_group.sh` | `VAULT_GROUP_NAME` (opt. `VAULT_GROUP_POLICIES`) | create an **internal** identity group |
| `add_policy_to_group.sh` | `VAULT_GROUP_NAME`, `VAULT_POLICY_NAME` | append a policy to a group (read-modify-write, preserves existing) |
| `add_user_to_group.sh` | `VAULT_USERNAME`, `VAULT_GROUP_NAME` | ensure the user's entity+alias, then add the entity to the group (append) |

> Both `add_*` scripts **append** rather than overwrite, because `identity/group` *replaces* the `policies` / `member_entity_ids` lists on every write. They use `vault ... -field=` + `awk`/`tr` (no `jq` — the Vault Alpine image doesn't ship it).

---

## Operational lifecycle

1. **Init once** (`vault_*_init.sh`) → **save the printed unseal keys + root token** somewhere safe. Losing them = locked out, no recovery.
2. **Vault re-seals on every container restart.** After any restart, re-unseal with **any 2 of the 3** keys:
   ```sh
   export VAULT_ADDR=https://localhost:8004 VAULT_CACERT=/vault/tls/ca.crt   # (or http://127.0.0.1:8004 local)
   vault operator unseal <KEY_1>
   vault operator unseal <KEY_2>
   ```
   The bridge depends on Vault for **all** auth (signing JWTs), so while Vault is sealed, `login`/`refresh` return 500.
3. **Create users / groups / policies** as needed with the scripts above.

---

## End-to-end RBAC example

```sh
# 1. a policy (capabilities)
docker exec -it -e VAULT_POLICY_NAME=analyst-read \
  -e VAULT_POLICY_HCL='path "secret/data/analyst/*" { capabilities = ["read","list"] }' \
  vault sh /tmp/create_policy.sh

# 2. a group with that policy
docker exec -it -e VAULT_GROUP_NAME=analysts -e VAULT_GROUP_POLICIES=analyst-read \
  vault sh /tmp/create_group.sh

# 3. add a user → inherits analyst-read on next login
docker exec -it -e VAULT_USERNAME=konstantinosmpouros -e VAULT_GROUP_NAME=analysts \
  vault sh /tmp/add_user_to_group.sh
```

---

## Wiring RBAC into the application code

**Important:** none of the above affects mAgenticX **yet**. Today the bridge uses Vault only to verify the password and read the `entity_id`; it mints its own session JWT (signed by its AppRole identity) and **discards the user's Vault token and its policies**. So a user's groups/policies currently govern only what they could do *inside Vault directly* — they have **no effect in the app**.

To make them enforce, carry the user's roles along the chain **Vault login → session JWT → FastAPI deps**. Five seams:

### 1. Capture roles at login — `core/vault.py`
The userpass login response's `auth` block already carries the effective policies: `identity_policies` is exactly the set inherited from the entity + its groups (your RBAC roles); `token_policies` is the user's own (`default`).

```python
@dataclass(slots=True)
class VaultAuthResult:
    vault_user_id: str
    username: str
    roles: tuple[str, ...] = ()                      # NEW

# inside authenticate(), after building auth_block:
identity_policies = auth_block.get("identity_policies") or []
roles = tuple(p for p in identity_policies if p != "default")
return VaultAuthResult(vault_user_id=vault_user_id, username=username, roles=roles)
```
No extra Vault call and **no extra bridge permission** — the user's own login returns their policies.

### 2. Normalize into the provider identity — `core/auth_providers.py`
`AuthIdentity` already has a `groups` field; populate it:
```python
return AuthIdentity(
    subject=result.vault_user_id, username=result.username,
    provider=self.name, groups=result.roles,         # NEW
)
```

### 3. Embed in the JWT — `core/jwt_tokens.py`
```python
async def mint_tokens(user_id, *, sid=None, login_at=None, is_active=True, roles=()):   # + roles
    ...
    access_claims  = {**base, "typ": ACCESS_TYPE,  "act": is_active, "roles": list(roles), "exp": ..., "jti": ...}
    refresh_claims = {**base, "typ": REFRESH_TYPE, "lat": login_at,  "roles": list(roles), "exp": ..., "jti": ...}
```
`verify()` returns the full claims dict already, so the `roles` claim flows through with no change there.

### 4. Thread through login/refresh + expose on the context — `core/auth_session.py`
```python
async def mint_login_session(user, roles=()):                           # login passes identity.groups
    return await mint_tokens(user.id, is_active=user.is_active, roles=roles)

async def rotate_session(ctx, *, is_active=True):                       # carry roles across refresh
    return await mint_tokens(ctx.user_id, sid=ctx.id, login_at=ctx.login_at, is_active=is_active, roles=ctx.roles)

@dataclass(slots=True)
class AuthContext:
    ...
    roles: tuple[str, ...] = ()                                         # NEW

@dataclass(slots=True)
class AuthUser:
    id: str
    is_active: bool
    roles: tuple[str, ...] = ()                                         # NEW

# in _resolve():            roles=tuple(claims.get("roles") or ())
# in require_current_user(): return AuthUser(id=ctx.user_id, is_active=ctx.is_active, roles=ctx.roles)
```
And in `router/auth.py` `authenticate()`:
```python
issued = await mint_login_session(user, roles=identity.groups)
```

### 5. Enforce — `core/auth_session.py` + routers
A dependency factory that composes with the existing session check:
```python
def require_roles(*required: str, mode: str = "any"):
    async def _dep(user: AuthUser = Depends(require_current_user)) -> AuthUser:
        have = set(user.roles)
        ok = have.issuperset(required) if mode == "all" else bool(have & set(required))
        if not ok:
            logger.warning("rbac_denied", "Missing required role", required=list(required), have=list(have))
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Insufficient permissions.")
        return user
    return _dep
```
Use it on any endpoint (it pulls in `require_session` → `require_current_user` transitively):
```python
@router.post("/admin/reindex")
async def reindex(
    _: AuthUser = Depends(require_roles("admin")),
    __: None = Depends(require_csrf_protection),
):
    ...
```

### Freshness / staleness (read this before shipping)
Roles are captured at **login** and frozen into the JWT; carrying them across refresh (step 3) keeps them fixed for the whole session, so **a Vault group change only takes effect on the user's next login** (≤ 10 days). Two ways to bound that:

- **Re-fetch on refresh** — in `rotate_session`, instead of carrying `ctx.roles`, look the user's *current* policies up by entity: `GET identity/entity/id/<entity_id>` → `policies` + `group_ids`. Roles then refresh every ≤ 8 h. This requires **expanding the bridge's Vault policy** to add `read` on `identity/entity/id/*` (and `identity/group/id/*` if you resolve group names) — do it with `create_policy.sh` / `add_policy_to_group.sh`. (Login-time capture in step 1 needs no such grant.)
- **Force re-login** on a role change — revoke the session via the logout denylist (`logout_denylist.revoke(sid, ...)`), so the next request must re-authenticate.

### Policy names vs group names
The login response carries **policy** names (`identity_policies`), so the cheapest RBAC checks *policy* names (`require_roles("analyst-read")`). If you'd rather check **group** names (`require_roles("analysts")`), resolve them from `entity_id → group_ids → group names` — extra Vault reads plus the identity-read grant above.

---

## Where authorization checks live (the enforcement model)

Once roles are in the JWT, *enforcing* them is a **layered gate at the request boundary** — a chain of FastAPI dependencies that run before the endpoint body, plus one check inside it. Authorization is **not** scattered through business logic; it is declared per route.

### The request gate

```
                       ┌──────────────────────────────────────────────────┐
  HTTPS request        │                 dialogue_bridge                   │
  cookie:              │                                                   │
  __Host-mx_session ──►│  ① require_session            (authN)             │
   = <JWT>             │      • RS256 sig valid (Vault Transit pubkey)     │
                       │      • not expired / nbf ok                       │ ──► 401
                       │      • sid not in logout denylist                 │
                       │                ↓                                  │
                       │  ② require_roles("admin", …)  (authZ · coarse)    │
                       │      • read `roles` claim — NO Vault/DB call      │ ──► 403
                       │      • admin?  in group X?                        │
                       │                ↓                                  │
                       │  ③ require_csrf_protection    (mutations only)    │ ──► 403
                       │                ↓                                  │
                       │  ════════════ endpoint body ════════════         │
                       │  ④ ownership filter           (authZ · fine)      │
                       │      • SELECT … WHERE user_id = ctx.user_id       │ ──► 404
                       └──────────────────────────────────────────────────┘
```

| Layer | Dependency | Question | Fail | Cost |
|---|---|---|---|---|
| ① authN | `require_session` | Is the JWT real, unexpired, not logged out? | 401 | pubkey cached — no network |
| ② authZ · role | `require_roles(...)` | admin / in group X? (from the **JWT claim**) | 403 | free (claim read) |
| ③ CSRF | `require_csrf_protection` | double-submit token matches (mutations) | 403 | free |
| ④ authZ · ownership | query filter in `utils/` | is this row **yours**? | 404 | one DB read |

### Two kinds of authorization — you need BOTH

The JWT answers "who are you and what roles do you hold." It can **not** answer "is *this* row yours." Don't let the role gate stand in for ownership.

| Question | Kind | Decided | Cost |
|---|---|---|---|
| "Is this user an admin / in `analysts`?" | **Role** (coarse) | dependency, from the **JWT `roles` claim** | free |
| "Can this user open **conversation #842**?" | **Ownership** (fine) | in `utils/`, at the **DB query** (`WHERE user_id = …`) | a DB read |

> A valid `analyst` token will pass `require_roles("analyst-read")` for `GET /conversations/{id}` — the gate has no idea the conversation belongs to *someone else*. That's why every resource query is scoped by `user_id`. RBAC **adds** the role gate; it never **replaces** ownership scoping.

### How the roles got into the token (recap)

```
browser           bridge                          Vault
  │ POST /login      │                              │
  │ user + pass ────►│  userpass/login/<user> ─────►│ verify password,
  │                  │                              │ resolve entity + groups
  │                  │  auth.identity_policies ◄────│
  │                  │     = ["default","analyst-read"]
  │                  │                              │
  │                  │  build JWT { sub, sid,       │
  │                  │     roles:["analyst-read"] } │
  │                  │  transit/sign ──────────────►│ (RSA private key never leaves)
  │                  │         signature ◄──────────│
  │ Set-Cookie ◄─────│  __Host-mx_session=<JWT>     │
```

### Which check do I add?

```
What does this endpoint protect?
│
├─ "only certain roles may call it at all"        → require_roles("admin")               [boundary]
│
├─ "any logged-in user, but only their own data"  → require_session  +  WHERE user_id=…  [data layer]
│
├─ "a user's data addressed as /users/{id}/…"     → require_bound_user_id                 [boundary + path]
│
└─ "admins only AND still row-scoped"             → require_roles(...)  +  WHERE user_id=…
```

### Worked examples

```python
# (a) Coarse only — admin-gated, no per-row scope
@router.post("/admin/agents/resync")
async def resync_agents(
    _: AuthUser = Depends(require_roles("admin")),
    __: None    = Depends(require_csrf_protection),
):
    await rebuild_agent_cache()

# (b) Ownership only — any logged-in user, but only THEIR conversation
@router.get("/conversations/{conversation_id}")
async def get_conversation(
    conversation_id: str,
    user: AuthUser   = Depends(require_current_user),         # authN only
    db: AsyncSession = Depends(get_db),
):
    convo = await conversations.get_for_user(db, conversation_id, user_id=user.id)  # WHERE id=? AND user_id=?
    if convo is None:
        raise HTTPException(404)   # not-found and not-yours look identical — don't leak existence

# (c) Both — admin feature that reads across users by design
@router.get("/admin/users/{user_id}/audit")
async def audit(
    user_id: str,
    _: AuthUser      = Depends(require_roles("admin")),       # coarse gate
    db: AsyncSession = Depends(get_db),
):
    return await audit_log.for_user(db, user_id)             # admin may read any user_id here
```

### Staleness in practice

Roles are read from Vault **once, at login**, and frozen into the JWT; refresh carries the same set forward:

```
 login                                                              re-login
   │ roles read from Vault → frozen in JWT                             │ roles re-read
   ▼                                                                   ▼
   ├─ access 8h ─┬─ access 8h ─┬─ … ─┐  (refresh reuses the SAME roles)
   │  refresh ───┘  refresh ───┘     │
   │                                 └──────────── hard cap: 10 days ──┘
   │
   └─ ⚠ a Vault group change made mid-session takes effect only at NEXT login
        (unless rotate_session re-fetches roles by entity_id → effect within ≤8h,
         which needs the bridge policy widened to read identity/*)
```

### Anti-patterns

- **Don't call Vault per request** to check a role — read the JWT `roles` claim. The per-request statelessness is the whole point.
- **Don't let the role gate cover ownership** — a valid token for the right role still must not read another user's rows. Scope every query by `user_id`.
- **Don't scatter `if user.role == "admin"` through business logic** — declare `require_roles(...)` at the route: it can't be forgotten, and it's unit-testable in isolation.
- **Don't put ownership checks in a dependency that can't see the data** — they belong in `utils/` where the row is loaded.
- **Don't return 403 for another user's resource** — return the same 404 as a missing one, so you don't leak which ids exist.
