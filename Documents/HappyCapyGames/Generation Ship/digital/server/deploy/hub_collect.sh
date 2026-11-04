#!/bin/sh
# Daily HCG backend run: game numbers, Steam, Discord, YouTube, BGG, and a backup of hub.db
# (run by hub-collect.timer). The token comes from the API's own .env.
set -e
TOKEN=$(grep "^HUB_TOKEN=" /opt/hcg-api/.env | cut -d= -f2-)
curl -fsS -X POST -H "X-Hub-Token: $TOKEN" "https://api.happycapygames.com/v1/hub/collect"
echo
