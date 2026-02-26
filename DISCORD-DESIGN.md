# Tinker — Discord Server Design

## Server Structure

```
WELCOME & INFO
  #readme              (read-only)  — what this is, how to participate
  #how-it-works        (read-only)  — phase diagram + example messages

BUILD
  #build               (interactive) — the one channel. bot lives here.
  #build-log           (read-only)   — bot auto-posts wrap summaries

COMMUNITY
  #general             (no bot)      — human chat, banter
  #ideas-parking-lot                 — async idea dump between sessions
  #showcase                          — share what you built

FUNDING
  #topup               (interactive) — !topup and !balance
  #credits-log         (read-only)   — payment confirmations

META (admin only)
  #ops                               — deploy logs, bot health
```

## Bot Channel Scope

Bot is active in: #build, #topup
Bot is NOT active in: #general, #readme, #announcements, #build-log

## Roles

| Role | Who | Purpose |
|------|-----|---------|
| @Admin | Server owner, operators | Full management, #ops access |
| @Moderator | Trusted members | Can write to read-only channels, can kick/mute |
| @Builder | Participants | Cosmetic/recognition (auto-assign is stretch goal) |
| @Bot | open-builder bot | Send messages, add reactions, read history, embeds |
| @everyone | Default | Read most channels, write in #general, #build, #topup |

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Channel model | Single #build, no threads for v1 | Lowest friction for meetup demo. Threads are v2. |
| Command access | Open to everyone | Matches open ethos. Add session-owner model if trolling appears. |
| Concurrent sessions | Blocked (one at a time) | Single agent context window. |
| Code after !wrap | Post in chat for v1, gist for v2 | Gist needs GitHub token infra. |
| !topup location | Acknowledge in #build, post invoice in #topup | Keeps build channel clean. |
| QR for invoices | Stretch goal | Killer demo moment but needs qrencode tooling. |
| Session timeouts | Nudge at 3 min, auto-cancel at 5 | Prevents orphaned sessions. NOT in AGENTS.md yet. |

## Meetup Demo Timeline (20 min)

| Time | Phase | Notes |
|------|-------|-------|
| 0:00 | QR code up, people join | Presenter talks briefly |
| 0:02 | !start | First !start within 3 min of invite |
| 0:02-0:05 | IDEATION | 3 min max. Have seed ideas ready. |
| 0:05-0:07 | SYNTHESIS + voting | |
| 0:07-0:14 | BUILD | ~7 min live coding |
| 0:14-0:18 | ITERATE | 1-2 feedback rounds |
| 0:18-0:19 | !wrap | |
| 0:19-0:20 | Lightning demo | !balance, someone !topup live |

## Demo Risks

- **Nobody has ideas** — presenter has 2-3 seed ideas ready as ice breakers
- **Credits run out** — have Lightning wallet loaded, turn it into a live funding demo
- **Bot errors during BUILD** — narrate it: "debugging live, this is normal"
- **Bad WiFi at venue** — mobile hotspot backup. Bot is server-side, only needs Discord client.
- **Troll !wraps mid-build** — presenter controls flow for demo. v2: session-owner model.

## TODO (not yet implemented)

- [ ] Add session timeouts to AGENTS.md (nudge at 3 min, cancel at 5)
- [ ] Configure bot to post invoices in #topup and acknowledge in #build
- [ ] Add !wrap access from BUILD phase (currently ITERATE only)
- [ ] QR code generation for Lightning invoices (stretch)
- [ ] Auto-post wrap summaries to #build-log
- [ ] Code export to GitHub gist on !wrap (v2)
