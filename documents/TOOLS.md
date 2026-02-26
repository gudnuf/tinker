# open-builder — Tool Reference

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
- running the topup and balance scripts

constraints:
- stay inside /home/openclaw/. no reading /etc/passwd, no writing to /tmp
  outside the sandbox, no network probing.
- no destructive commands outside /home/openclaw/projects/
- commands that take > 30s should be run with awareness — post a status
  update so the channel knows you haven't died
- if a command fails, show the error output. don't silently retry.

## read

read file contents. returns the content of a file at a given path.

use for:
- reviewing code you've written or need to modify
- checking config files
- reading script outputs saved to files

scope: /home/openclaw/ and below.

## write

write content to a file. creates the file if it doesn't exist, overwrites if
it does.

use for:
- creating new source files during BUILD
- writing config files, package.json, etc.
- saving build artifacts

scope: /home/openclaw/projects/ for project files.

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
- checking if a URL/endpoint is live

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
- for long code, break across multiple messages at logical boundaries

---

## scripts

these live at /home/openclaw/scripts/ and are called via exec.

### check-balance.sh

check the ppq.ai credit balance.

```bash
bash /home/openclaw/scripts/check-balance.sh
```

output: current balance in USD (and sats if available).
exit 0 on success, exit 1 on error.

reads api key from /run/secrets/ppq-api-key.

when to call:
- on `!balance` command
- before starting BUILD phase
- if you suspect credits are running low
- during WRAP as a courtesy

### topup.sh

generate a bitcoin lightning invoice for topping up credits.

```bash
bash /home/openclaw/scripts/topup.sh [amount_in_sats]
```

default amount: 10000 sats.

output: lightning invoice (payment request string) and invoice ID.
the script polls for payment confirmation (15 min timeout).
exit 0 when paid, exit 1 on error or expiry.

reads api key from /run/secrets/ppq-api-key.

when to call:
- on `!topup` or `!topup N` command
- post the lightning invoice to discord so anyone can pay it
- report payment confirmation or expiry back to the channel
