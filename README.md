# OpenClaw Daily BookStack

A cron job that uses [OpenClaw](https://openclaw.com) to generate a hands-on cybersecurity or homelab tutorial every day and publish it to a self-hosted [BookStack](https://www.bookstackapp.com/) wiki.

Each morning you wake up to a fresh 10-page guide you can actually follow — real commands, real configs, real file paths. No fluff.

## What it does

1. Picks today's topic from a rotating list of 30 categories (Docker security, Wireguard, Suricata, Ansible, LUKS, honeypots, etc.)
2. Asks Claude (via OpenClaw gateway) to generate a creative project title
3. Creates a new book in BookStack with 10 pages:
   - Overview and Goals
   - Prerequisites and Environment Setup
   - Core Concepts Explained
   - Steps 1-4: Hands-on implementation
   - Security Considerations
   - Troubleshooting Common Issues
   - Next Steps and Expansion Ideas
4. Adds the book to a "Daily Knowledge Base" shelf

The whole run takes about 6 minutes and produces a ~30-minute hands-on project.

## Example titles it has generated

- *Build an Ansible Playbook That Provisions a Hardened Docker Host with Fail2Ban and Automatic Security Updates*
- *Jailbreaking in Reverse: Locking Down a Home Assistant Add-On with Systemd Namespaces and Seccomp Filters*
- *Catching Shadows: Build an Auditd Tripwire to Detect Unauthorized SSH Key Injection*

## Prerequisites

- [OpenClaw](https://openclaw.com) installed and running (daemon + gateway)
- Docker and Docker Compose
- `jq` and `curl`

## Setup

### 1. Start BookStack

Create a `.env` file with your BookStack config:

```bash
APP_URL=http://localhost:8080
APP_KEY=base64:YOUR_KEY_HERE
DB_PASS=your_db_password
DB_ROOT_PASS=your_root_password
```

```bash
docker compose up -d
```

### 2. Create a BookStack API token

1. Log into BookStack at `http://localhost:8080`
2. Go to your profile > API Tokens > Create Token
3. Copy the Token ID and Token Secret

### 3. Configure API credentials

Create a `.env.api` file:

```bash
# BookStack
BOOKSTACK_URL=http://localhost:8080
BOOKSTACK_TOKEN_ID=your_token_id
BOOKSTACK_TOKEN_SECRET=your_token_secret

# OpenClaw gateway
OPENCLAW_URL=http://localhost:18789/v1/chat/completions
OPENCLAW_TOKEN=your_openclaw_token
```

### 4. Create the shelf

In BookStack, manually create a shelf called **"Daily Knowledge Base"**. The script looks for this shelf by name.

### 5. Schedule it

```bash
chmod +x daily-knowledge.sh
mkdir -p logs

# Run daily at 5 AM (adjust to your timezone)
crontab -e
```

Add:

```
0 10 * * * /path/to/daily-knowledge.sh >> /path/to/logs/cron.log 2>&1
```

### 6. Test it

```bash
./daily-knowledge.sh
```

Check `logs/` for today's log file.

## Customization

**Change the topics** — edit the `CATEGORIES` array in `daily-knowledge.sh`. Add whatever you're interested in learning about.

**Change the page count or structure** — edit the `PAGE_TITLES` array. Want 5 pages instead of 10? Just trim the list.

**Change the model** — swap `"opus"` in the `call_llm` function payload to whatever model your OpenClaw gateway serves.

**Change the writing style** — tweak the `SYSTEM_CONTENT` prompt. The current one targets a motivated junior engineer, but you could aim it at CTF players, sysadmins, or security auditors.

## Project structure

```
.
├── daily-knowledge.sh    # Main script — generates and publishes daily articles
├── docker-compose.yml    # BookStack + MariaDB
├── .env                  # BookStack environment config (not tracked)
├── .env.api              # API credentials (not tracked)
├── data/                 # BookStack application data (not tracked)
├── db/                   # MariaDB data (not tracked)
└── logs/                 # Daily execution logs (not tracked)
```

## How it uses OpenClaw

This project hits the OpenClaw gateway's `/v1/chat/completions` endpoint — the same OpenAI-compatible API that OpenClaw exposes. The script is just `curl` and `jq`, no SDKs needed. If you can talk to OpenClaw's gateway, you can adapt this pattern to generate anything: documentation, study guides, incident response runbooks, CTF writeups, whatever.

The key idea: **use an LLM as a content engine, use BookStack as the knowledge store, and let cron tie them together.**
