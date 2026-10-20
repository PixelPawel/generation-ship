#!/bin/sh
# Daily contest snapshot: the Real Play top 100 as they stand at 23:59 Berlin
# (run by score-snapshot.timer). The token comes from the API's own .env.
set -e
TOKEN=$(grep "^ADMIN_TOKEN=" /opt/hcg-api/.env | cut -d= -f2-)
curl -fsS -X POST -H "X-Admin-Token: $TOKEN" "https://api.happycapygames.com/v1/scores/snapshot?source=play"
echo
