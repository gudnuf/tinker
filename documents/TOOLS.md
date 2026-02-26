# tinker — tool reference

tools available to you inside the openclaw sandbox. all file and exec
operations are confined to the systemd sandbox — respect the boundaries.

---

## exec

shell access. runs commands inside the systemd sandbox.

**working directory:** /home/openclaw/projects/
**shell:** bash

use for:
- scaffolding projects (mkdir, git init, npm init, etc.)
- running code (node, python, deno, whatever fits the build)
- installing dependencies (npm install, pip install — they persist in the sandbox)
- running the balance and topup scripts
- git operations (add, commit — required before every deploy)
- nix deploys (`sudo nixos-rebuild switch --flake /home/openclaw/system#tinker`)
- subagent curl calls to ppq.ai

constraints:
- stay inside /home/openclaw/. no reading /etc/passwd, no writing to /tmp
  outside the sandbox, no network probing.
- no destructive commands outside /home/openclaw/projects/
- the only sudo command you run is `nixos-rebuild switch`. nothing else.
- commands that take > 30s should be run with awareness — post a status
  update so the channel knows you haven't died
- if a command fails, show the error output. don't silently retry.

## read

read file contents. returns the content of a file at a given path.

use for:
- reviewing code you've written or need to modify
- checking config files
- reading existing project files before constructing subagent prompts
- checking app modules in /home/openclaw/system/modules/apps/

scope: /home/openclaw/ and below.

## write

write content to a file. creates the file if it doesn't exist, overwrites if
it does.

use for:
- creating new source files during BUILD
- writing config files, package.json, etc.
- writing NixOS app modules to /home/openclaw/system/modules/apps/
- saving subagent prompt JSON to /tmp/

scope: /home/openclaw/projects/ for project files.
/home/openclaw/system/modules/apps/ for NixOS app modules.

## edit

modify specific parts of an existing file. more surgical than write — use
this for targeted changes during ITERATE instead of rewriting entire files.

use for:
- fixing bugs in existing code
- adding features to existing files
- updating config values

prefer edit over write when changing < 50% of a file.

## web_search

search the web. returns a list of results with titles, urls, and snippets.

use for:
- looking up library docs during a build ("how does express middleware work")
- finding API references ("stripe api create payment intent")
- checking if a package exists ("npm package for qr codes")

don't use for:
- general knowledge questions you already know the answer to
- anything not directly related to the current build

## web_fetch

fetch a URL and return its content.

use for:
- reading documentation pages found via web_search
- fetching API specs or examples
- checking if a deployed URL is live

don't use for:
- scraping random sites
- anything that looks like it's probing infrastructure

## message

send a message to the discord channel.

use for:
- all communication with the group
- posting code, status updates, proposals, summaries
- responding to bang commands

formatting rules:
- discord markdown: **bold**, *italic*, `inline code`, ```code blocks```
- keep messages under 1800 chars (hard limit is 2000, leave margin)
- use fenced code blocks with language tags: ```js, ```py, ```bash, etc.
- for long content (plans, code), break across multiple messages at logical
  boundaries. don't wall-of-text.
- numbered lists for proposals. bullet lists for updates.

---

## scripts

these live at /home/openclaw/scripts/ and are called via exec.

### check-balance.sh

check the ppq.ai credit balance.

```bash
bash /home/openclaw/scripts/check-balance.sh
```

reads API key from /run/secrets/openclaw.env (sources the file).
output: `ppq.ai balance: <N> credits`
exit 0 on success, exit 1 on error.

when to call:
- on `!balance` command
- before starting BUILD phase (FUND gate)
- every 3 steps during BUILD
- during WRAP as a courtesy

### topup.sh

generate a bitcoin lightning invoice for topping up credits.

```bash
bash /home/openclaw/scripts/topup.sh [amount] [currency]
```

- amount defaults to 10000, currency defaults to SATS
- example: `topup.sh 5 USD` or `topup.sh 50000 SATS`

reads API key from /run/secrets/openclaw.env (sources the file).

output: invoice ID, payment request (bolt11 string), checkout URL (if
available). then polls for payment confirmation (15 min timeout).

exit 0 when paid, exit 1 on error or expiry.

when to call:
- on `!topup` or `!topup N` command
- post the lightning invoice to #credits so anyone can pay it
- report payment confirmation or expiry back to the channel

note: the credit bot sidecar (tinker-credit-bot service) also handles
!topup and !balance directly via Discord — these scripts are the fallback
for when the bot calls them via exec.

---

## git workflow

nix flakes only see git-tracked files. untracked files are invisible to
`nixos-rebuild`. you MUST commit before every rebuild. always, no exceptions.

### commit-before-rebuild

three commands, always in this order, never skipped:

```bash
cd /home/openclaw/system
git add -A
git commit -m "tinker: {name} — {what changed}"
sudo nixos-rebuild switch --flake .#tinker
```

### commit cadence

commit at every meaningful checkpoint:

| event | message example |
|-------|----------------|
| plan finalized | `tinker: lightning-tip-jar — build plan (12 steps)` |
| build step done | `tinker: lightning-tip-jar — step 3: express routes` |
| app module written | `tinker: lightning-tip-jar — nixos module, port 10001` |
| first deploy | `tinker: lightning-tip-jar — v0 deploy` |
| iteration change | `tinker: lightning-tip-jar — iteration: dark mode toggle` |
| final wrap | `tinker: lightning-tip-jar — final` |

typical round: 15-25 commits. each small, focused, descriptive.

---

## nix deployment

you deploy apps by writing NixOS modules and running nixos-rebuild. the
system auto-imports any .nix file from modules/apps/.

### write the app module

create `/home/openclaw/system/modules/apps/{name}.nix`:

```nix
# Auto-generated by Tinker for round: {name}
{ config, pkgs, lib, ... }:
{
  systemd.services."tinker-{name}" = {
    description = "Tinker app: {name}";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      WorkingDirectory = "/home/openclaw/projects/{name}";
      ExecStart = "${pkgs.nodejs}/bin/node server.js";
      Restart = "on-failure";
      RestartSec = 5;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ "/home/openclaw/projects/{name}" ];
      PrivateTmp = true;
      NoNewPrivileges = true;
      MemoryMax = "256M";
      CPUQuota = "50%";
      Environment = [
        "PORT={port}"
        "NODE_ENV=production"
      ];
    };
  };

  services.caddy.virtualHosts."{name}.tinker.builders" = {
    extraConfig = ''
      reverse_proxy localhost:{port}
    '';
  };
}
```

adjust ExecStart for the tech stack (python, go, etc). for static sites,
skip the systemd service — just add a caddy file server:

```nix
services.caddy.virtualHosts."{name}.tinker.builders" = {
  extraConfig = ''
    root * /home/openclaw/projects/{name}/public
    file_server
  '';
};
```

### port allocation

apps get ports from 10001-10099. assign sequentially. scan existing modules
for used ports and pick the next available one. check
`/home/openclaw/system/modules/apps/.next-port` for the counter.

### deploy sequence

1. write app code to `/home/openclaw/projects/{name}/`
2. write NixOS module to `/home/openclaw/system/modules/apps/{name}.nix`
3. commit and rebuild:
   ```bash
   cd /home/openclaw/system
   git add -A
   git commit -m "tinker: {name} — {what changed}"
   sudo nixos-rebuild switch --flake .#tinker
   ```

### verify

after rebuild:
- check exit code. if != 0, rollback: `sudo nixos-rebuild switch --rollback`
- check service: `systemctl is-active tinker-{name}`
- check URL: `curl -s -o /dev/null -w '%{http_code}' https://{name}.tinker.builders`
- if anything fails, report in #build with the error and rollback.

### rollback

```bash
sudo nixos-rebuild switch --rollback
```

always rollback before debugging. never leave the system broken.

---

## subagent calls

you delegate code generation to subagent calls — direct API calls to ppq.ai
via curl. you construct the prompt and call the API. this keeps your context
clean and code quality high.

### the curl pattern

write the prompt to a temp JSON file, then call:

```bash
curl -s -X POST https://api.ppq.ai/chat/completions \
  -H "Authorization: Bearer $(grep OPENAI_API_KEY /run/secrets/openclaw.env | cut -d= -f2)" \
  -H "Content-Type: application/json" \
  -d @/tmp/step-{N}-prompt.json
```

### prompt format

```json
{
  "model": "openai/claude-sonnet-4.6",
  "max_tokens": 4096,
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." }
  ]
}
```

### context budget

- input: 8K tokens max (system ~200, step ~200, files ~4K, buffer ~3.4K)
- output: 4K tokens max

if a step needs more context, break it into sub-steps or summarize existing
code instead of including full files.

### response parsing

parse `.choices[0].message.content` from the response. extract code blocks
by filename (the subagent outputs files as fenced code blocks with the
filename as the info string).

### failure handling

- API error: retry once after 5s, then once more. if still failing, ask the
  group.
- bad code: re-prompt with the error. one retry. then attempt manual fix.
- off-script: discard and re-prompt with more explicit instructions.
