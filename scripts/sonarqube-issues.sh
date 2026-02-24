#!/usr/bin/env bash
# Fetch SonarQube issues for the vault project.
# Usage: ./scripts/sonarqube-issues.sh [--swift-only] [--json]
set -euo pipefail

TOKEN="e939e145b37c72c521e0afd4ff6be099c9f85986"
PROJECT="ehmo_vault"
BASE="https://sonarcloud.io/api"

LANGUAGES=""
JSON_MODE=false

for arg in "$@"; do
  case "$arg" in
    --swift-only) LANGUAGES="&languages=swift" ;;
    --json) JSON_MODE=true ;;
  esac
done

RESPONSE=$(curl -s -u "${TOKEN}:" \
  "${BASE}/issues/search?componentKeys=${PROJECT}&statuses=OPEN,CONFIRMED,REOPENED&ps=100&p=1${LANGUAGES}")

if $JSON_MODE; then
  echo "$RESPONSE" | python3 -m json.tool
else
  echo "$RESPONSE" | python3 -c "
import sys, json
from collections import Counter
d = json.load(sys.stdin)
total = d['total']
print(f'Open issues: {total}')
if total == 0:
    sys.exit(0)
print()
sev = Counter(i['severity'] for i in d['issues'])
for s in ['BLOCKER','CRITICAL','MAJOR','MINOR','INFO']:
    if s in sev: print(f'  {s}: {sev[s]}')
print()
for i in d['issues']:
    comp = i['component'].split(':')[-1]
    line = i.get('line','?')
    print(f'[{i[\"severity\"]:8}] {i[\"message\"][:80]}')
    print(f'           {comp}:{line}  rule={i[\"rule\"]}')
    print()
"
fi
