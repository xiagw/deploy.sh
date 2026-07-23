# AGENTS.md

This file provides guidance to the AI agent when working with code in this repository.

Bash wrapper around the Alibaba Cloud CLI (plugin mode, aliyun >= 3.4). Entry: `bash main.sh [-p <profile>] [-r <region>] <service> <operation> [args...]`. UI text is Chinese.

## Aliyun CLI 3.4+ parameter rules (critical)

- All API calls go through `call_aliyun_api` (base.sh), which appends `--profile` and auto-plugin-install flags. Never call `aliyun` directly in service modules.
- Plugin CLI renamed params that clash with reserved/global flags: use `--biz-region-id` (not `--region-id`/`--RegionId`) and `--biz-key-pair-name` (not `--key-pair-name`). Other commands may have similar `--biz-*` renames — verify with `aliyun <product> <command> --help` before adding/changing any call.
- Use new plugin-style kebab-case commands, not legacy PascalCase API names: `ram get-account-alias` (not `ram GetAccountAlias`), `sts get-caller-identity`, `ecs describe-key-pairs`. Exception: ACK uses REST style (`cs GET /clusters`).
- Central services ignore the user region: `cas` calls must use `--region cn-hangzhou`; `alidns` calls must use `--region public` (cn-hangzhou also fails). `ram`/`cdn` need no region.
- `--region` (global flag) selects the endpoint; `--biz-region-id` is the API's RegionId business param. Regional services often need both.

## Conventions

- Subcommands are verb-first: `get`, `add`, `set`, `del`, plus suffixed forms like `add-key`, `get-perm`, `del-vsw`. Do not introduce noun-first names (`key-add`).
- All yes/no confirmations must accept y/Y/yes case-insensitively: reuse `confirm_action` (base.sh) instead of inline `read`.
- Commands with optional args fall back to fzf interactive selection (`select_with_fzf`); auto-select when only one candidate.
- Variables `profile` and `region` are set in `main.sh` and used implicitly (not passed) by service functions.
- Logs go to `<repo-root>/data/logs/aliyun/<profile>/<region>/`, cached data to `data/cache/<profile>/<region>/<service>/` (utils.sh). Do not revert to the old `data/<profile>/<region>/logs/` layout.
- New service module: copy an existing simple module (e.g. `nat.sh`), implement `handle_<service>_commands`, add a case in `main.sh`.

## Testing

- No test suite. Verify with `bash -n <file>` then live calls, e.g. `bash main.sh -p flyh5 -r cn-hangzhou ecs get-key`. Append `</dev/null` and a timeout for non-interactive runs; `get-all` and `dns get` can exceed 2 minutes.
- `aliyun --cli-dry-run ...` prints the request without calling the API — use it to validate param names.

## Gotchas

- RAM permissions have two scopes: account-level (`ram list-policies-for-user`) and resource-group-level (`resourcemanager ListPolicyAttachments --PrincipalType IMSUser --PrincipalName "<user>@<alias>.onaliyun.com"`). The console shows both; querying only the first looks "empty".
- macOS: `main.sh` needs `greadlink` (Homebrew coreutils); `stat -c` in `load_module` is GNU-style.
