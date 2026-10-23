#!/usr/bin/env bash
# Scrape -> model -> commit -> push -> dispatch deploy, repeated until END_TIME.
# Used by .github/workflows/election-night.yml and canvass.yml, and runnable locally as the fallback when
# GitHub-hosted runners cannot reach electionresults.utah.gov:
#   UTEL_RAW_DIR=... pipeline/scripts/election_night_loop.sh
#
# Environment:
#   END_TIME        ISO timestamp to stop at (default: now + 5h45m)
#   SLEEP_SECONDS   pause between scrapes (default 100)
#   DEPLOY_MIN_GAP  minimum seconds between deploy dispatches (default 180)
#   ONCE=1          do a single scrape and exit (canvass mode)
#   DEPLOY=0        commit/push but do not dispatch deploy.yml
#   PUSH=0          commit locally only
set -u
cd "$(git rev-parse --show-toplevel)"

SLEEP_SECONDS="${SLEEP_SECONDS:-100}"
DEPLOY_MIN_GAP="${DEPLOY_MIN_GAP:-180}"
DEFAULT_END=$(( $(date -u +%s) + 5*3600 + 45*60 ))
if [ -n "${END_TIME:-}" ]; then
  END_EPOCH=$(date -u -d "$END_TIME" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$END_TIME" +%s)
else
  END_EPOCH=$DEFAULT_END
fi
PATHS=(web/public/data/results/2026-general web/public/data/config.json web/public/data/national)
last_deploy=0
deploy_pending=0
export UTEL_SKIP_CONNCHECK=0

log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }

push_with_retry() {
  for attempt in 1 2 3 4; do
    if git pull --rebase --autostash -q origin main && git push -q origin HEAD:main; then return 0; fi
    log "push attempt $attempt failed; retrying"
    sleep $(( attempt * 3 ))
  done
  return 1
}

maybe_deploy() {
  [ "${DEPLOY:-1}" = "0" ] && { deploy_pending=0; return; }
  local now; now=$(date -u +%s)
  if [ "$deploy_pending" = "1" ] && [ $(( now - last_deploy )) -ge "$DEPLOY_MIN_GAP" ]; then
    if gh workflow run deploy.yml --ref main; then
      log "deploy dispatched"
      last_deploy=$now
      deploy_pending=0
    else
      log "deploy dispatch failed (will retry)"
    fi
  fi
}

while :; do
  log "scrape start"
  # A failure here must not block Utah results.
  Rscript pipeline/scripts/build_national.R || log "national build failed (previous data left in place)"
  if Rscript pipeline/scripts/scrape_live.R; then
    export UTEL_SKIP_CONNCHECK=1
    if [ -n "$(git status --porcelain -- "${PATHS[@]}")" ]; then
      git add -- "${PATHS[@]}"
      git commit -q -m "Live results $(date -u +%Y-%m-%dT%H:%MZ)"
      if [ "${PUSH:-1}" = "0" ] || push_with_retry; then
        deploy_pending=1
      else
        log "push failed; keeping local commit"
      fi
    else
      log "no data changes"
    fi
  else
    log "scrape failed (previous good data left in place)"
  fi
  maybe_deploy
  [ "${ONCE:-0}" = "1" ] && break
  [ "$(date -u +%s)" -ge "$END_EPOCH" ] && break
  sleep "$SLEEP_SECONDS"
done

# A final deploy so the last committed state always goes out, even if throttled earlier.
if [ "$deploy_pending" = "1" ]; then
  DEPLOY_MIN_GAP=0 maybe_deploy
fi
log "loop finished"
