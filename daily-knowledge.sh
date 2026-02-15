#!/usr/bin/env bash
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env.api"

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# ── Topic categories (rotate by day-of-year) ─────────────────────────────────
CATEGORIES=(
  "Docker container security hardening"
  "Linux firewall rules with nftables"
  "Automated backup strategies for self-hosted services"
  "SSH hardening and key management"
  "Wireguard VPN setup and configuration"
  "Nginx reverse proxy with SSL termination"
  "Log aggregation and monitoring with Grafana"
  "DNS sinkhole with Pi-hole or AdGuard"
  "Intrusion detection with Suricata or Snort"
  "Container orchestration basics with Docker Compose"
  "Automated vulnerability scanning with OpenVAS"
  "Network segmentation for homelabs"
  "Certificate management with Let's Encrypt"
  "Secrets management with Vault or SOPS"
  "Ansible automation for server provisioning"
  "Systemd service hardening and sandboxing"
  "Linux audit framework and log analysis"
  "File integrity monitoring with AIDE"
  "Reverse engineering network traffic with Wireshark"
  "Building a honeypot with Cowrie or T-Pot"
  "Git server self-hosting with Gitea"
  "Database backup and point-in-time recovery"
  "Container image scanning with Trivy"
  "Prometheus metrics and alerting"
  "Fail2ban advanced configuration and custom jails"
  "Linux user namespaces and rootless containers"
  "mTLS between microservices"
  "Cron job monitoring and dead man's switches"
  "Disk encryption with LUKS"
  "Incident response runbook creation"
)

DAY_OF_YEAR=$(date +%j | sed 's/^0*//')
CATEGORY_INDEX=$(( DAY_OF_YEAR % ${#CATEGORIES[@]} ))
TODAY_CATEGORY="${CATEGORIES[$CATEGORY_INDEX]}"
TODAY_DATE=$(date +%Y-%m-%d)

log "Starting daily knowledge generation"
log "Category: $TODAY_CATEGORY"

# ── Helper: call OpenClaw gateway ─────────────────────────────────────────────
call_llm() {
  local system_msg="$1"
  local user_msg="$2"
  local max_tokens="${3:-4096}"

  local payload
  payload=$(jq -n \
    --arg sys "$system_msg" \
    --arg usr "$user_msg" \
    --argjson max "$max_tokens" \
    '{
      model: "opus",
      max_tokens: $max,
      messages: [
        { role: "system", content: $sys },
        { role: "user", content: $usr }
      ]
    }')

  local response
  response=$(curl -s -f --max-time 120 \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENCLAW_TOKEN" \
    -d "$payload" \
    "$OPENCLAW_URL") || {
    log "ERROR: LLM call failed"
    return 1
  }

  echo "$response" | jq -r '.choices[0].message.content'
}

# ── Helper: BookStack API ────────────────────────────────────────────────────
bookstack_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local args=(-s -f --max-time 30
    -H "Authorization: Token ${BOOKSTACK_TOKEN_ID}:${BOOKSTACK_TOKEN_SECRET}"
    -H "Content-Type: application/json"
    -X "$method"
  )

  if [[ -n "$data" ]]; then
    args+=(-d "$data")
  fi

  curl "${args[@]}" "${BOOKSTACK_URL}/api/${endpoint}"
}

# ── Step 1: Get the shelf ID for "Daily Knowledge Base" ─────────────────────
log "Finding Daily Knowledge Base shelf..."
SHELF_ID=$(bookstack_api GET "shelves" | jq -r '.data[] | select(.name == "Daily Knowledge Base") | .id' | head -1)

if [[ -z "$SHELF_ID" || "$SHELF_ID" == "null" ]]; then
  log "ERROR: Shelf 'Daily Knowledge Base' not found. Create it first."
  exit 1
fi
log "Shelf ID: $SHELF_ID"

# ── Step 2: Generate project title ──────────────────────────────────────────
log "Generating project title..."
SYSTEM_TITLE="You are a creative technical writer who designs hands-on homelab and cybersecurity projects. Respond with ONLY the project title, nothing else. No quotes, no prefix."
USER_TITLE="Create a specific, creative title for a ~30 minute hands-on project in this category: ${TODAY_CATEGORY}. The title should describe a concrete, practical project someone can actually build or configure today. Make it specific and actionable, not generic."

PROJECT_TITLE=$(call_llm "$SYSTEM_TITLE" "$USER_TITLE" 100)
PROJECT_TITLE=$(echo "$PROJECT_TITLE" | head -1 | sed 's/^["]*//;s/["]*$//')
BOOK_TITLE="${TODAY_DATE} - ${PROJECT_TITLE}"
log "Book title: $BOOK_TITLE"

# ── Step 3: Generate page content ───────────────────────────────────────────
PAGE_TITLES=(
  "Overview and Goals"
  "Prerequisites and Environment Setup"
  "Core Concepts Explained"
  "Step 1: Initial Configuration"
  "Step 2: Building the Foundation"
  "Step 3: Core Implementation"
  "Step 4: Testing and Validation"
  "Security Considerations"
  "Troubleshooting Common Issues"
  "Next Steps and Expansion Ideas"
)

SYSTEM_CONTENT="You are a friendly senior engineer writing a hands-on tutorial. Write in markdown format.
Your style: practical, clear, opinionated. Use real commands, real config snippets, real file paths.
This is part of a daily knowledge base — each day is a standalone ~30 min project.
Do NOT use filler. Every paragraph should teach something concrete.
Write as if explaining to a motivated junior engineer who has basic Linux knowledge.
The overall project is: ${PROJECT_TITLE}
Category: ${TODAY_CATEGORY}"

# ── Step 4: Create book in BookStack ────────────────────────────────────────
log "Creating book..."
BOOK_DATA=$(jq -n --arg name "$BOOK_TITLE" --arg desc "Daily knowledge project: $TODAY_CATEGORY" \
  '{name: $name, description: $desc}')
BOOK_RESPONSE=$(bookstack_api POST "books" "$BOOK_DATA")
BOOK_ID=$(echo "$BOOK_RESPONSE" | jq -r '.id')

if [[ -z "$BOOK_ID" || "$BOOK_ID" == "null" ]]; then
  log "ERROR: Failed to create book. Response: $BOOK_RESPONSE"
  exit 1
fi
log "Book ID: $BOOK_ID"

# Assign book to shelf (append to existing books, not replace)
EXISTING_BOOKS=$(bookstack_api GET "shelves/$SHELF_ID" | jq '[.books[].id]')
UPDATED_BOOKS=$(echo "$EXISTING_BOOKS" | jq --argjson new "$BOOK_ID" '. + [$new]')
bookstack_api PUT "shelves/$SHELF_ID" \
  "$(jq -n --argjson books "$UPDATED_BOOKS" '{books: $books}')" > /dev/null 2>&1 || true

# ── Step 5: Generate and create each page ───────────────────────────────────
PREVIOUS_CONTENT=""
for i in "${!PAGE_TITLES[@]}"; do
  PAGE_NUM=$((i + 1))
  PAGE_TITLE="${PAGE_TITLES[$i]}"
  log "Generating page ${PAGE_NUM}/10: ${PAGE_TITLE}..."

  CONTEXT=""
  if [[ -n "$PREVIOUS_CONTENT" ]]; then
    # Send a summary of previous content for continuity (truncated to save tokens)
    CONTEXT="Previous pages covered: ${PREVIOUS_CONTENT:0:500}..."
  fi

  USER_MSG="Write page ${PAGE_NUM} of 10: \"${PAGE_TITLE}\"

${CONTEXT}

Write 400-800 words of practical, hands-on content for this section. Include:
- Real commands and configuration snippets where appropriate
- Clear explanations of WHY, not just HOW
- Specific file paths, port numbers, and package names
- Tips from experience that aren't in the official docs

Format as markdown. Start with a brief intro sentence, then dive into the content. Do NOT include the page title as a heading (BookStack adds it automatically)."

  PAGE_CONTENT=$(call_llm "$SYSTEM_CONTENT" "$USER_MSG" 4096)

  if [[ -z "$PAGE_CONTENT" ]]; then
    log "WARNING: Empty content for page ${PAGE_NUM}, skipping"
    continue
  fi

  # Track what we've covered for context continuity
  PREVIOUS_CONTENT="${PREVIOUS_CONTENT} | ${PAGE_TITLE}"

  # Create page via API (using markdown format)
  PAGE_DATA=$(jq -n \
    --argjson book_id "$BOOK_ID" \
    --arg name "$PAGE_TITLE" \
    --arg markdown "$PAGE_CONTENT" \
    --argjson priority "$PAGE_NUM" \
    '{book_id: $book_id, name: $name, markdown: $markdown, priority: $priority}')

  PAGE_RESPONSE=$(bookstack_api POST "pages" "$PAGE_DATA")
  PAGE_ID=$(echo "$PAGE_RESPONSE" | jq -r '.id')

  if [[ -z "$PAGE_ID" || "$PAGE_ID" == "null" ]]; then
    log "WARNING: Failed to create page ${PAGE_NUM}. Response: $PAGE_RESPONSE"
  else
    log "Created page ${PAGE_NUM}: ${PAGE_TITLE} (ID: ${PAGE_ID})"
  fi

  # Small delay to be kind to the LLM endpoint
  sleep 2
done

log "Daily knowledge generation complete: ${BOOK_TITLE}"
log "Book URL: ${BOOKSTACK_URL}/books/$(echo "$BOOK_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g')"
