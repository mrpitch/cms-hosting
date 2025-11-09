#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-$HOME/runner.env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${REPO:?REPO not set (e.g. owner/repo)}"
: "${RUNNER_NAME:?RUNNER_NAME not set}"
: "${RUNNER_LABELS:=self-hosted,hetzner,docker}"
: "${RUNNER_REG_PAT:?RUNNER_REG_PAT not set}"

API="https://api.github.com/repos/${REPO}/actions/runners/registration-token"
IMAGE="ghcr.io/actions/runner:latest"   # official container
WORKDIR="/runner/_work"

fetch_token() {
  curl -sX POST -H "Authorization: token ${RUNNER_REG_PAT}" -H "Accept: application/vnd.github+json" "${API}" | jq -r '.token'
}

while true; do
  echo "[runner] Fetching registration token…"
  TOKEN="$(fetch_token)"
  if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
    echo "[runner] Failed to fetch token"; sleep 10; continue
  fi

  # pull latest runner
  docker pull "${IMAGE}" || true

  # Note: bind docker.sock to allow builds/deploys on host daemon
  docker run --rm \
    --name "${RUNNER_NAME}" \
    -e REPO_URL="https://github.com/${REPO}" \
    -e RUNNER_NAME="${RUNNER_NAME}" \
    -e RUNNER_LABELS="${RUNNER_LABELS}" \
    -e RUNNER_TOKEN="${TOKEN}" \
    -e RUNNER_WORKDIR="${WORKDIR}" \
    -e EPHEMERAL="true" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v gh-runner-data:/runner \
    "${IMAGE}"

  echo "[runner] Job finished; restarting in 10s…"
  sleep 10
done
