#!/usr/bin/env bash
# Print where each lab volume's data lives: SSD (performance tier) versus the
# capacity pool. Runs on the client instance through SSM, which reads the
# fsxadmin password from Secrets Manager itself, so it never leaves AWS.
set -euo pipefail

tf() { terraform -chdir="$(dirname "$0")/../terraform" output -raw "$1"; }
REGION=$(tf region)
INSTANCE=$(tf client_instance_id)
MGMT=$(tf fsx_management_dns)
SECRET=$(tf fsxadmin_secret_arn)

read -r -d '' REMOTE <<SH || true
set -e
PW=\$(aws secretsmanager get-secret-value --region $REGION --secret-id $SECRET --query SecretString --output text | jq -r .password)
curl -sk -u "fsxadmin:\$PW" 'https://$MGMT/api/storage/volumes?svm.name=svm1&name=tier_*&fields=name,tiering.policy,space.used,space.snapshot.used,space.performance_tier_footprint,space.capacity_tier_footprint' \
  | jq -r '["volume","policy","used_gib","snapshot_gib","ssd_gib","pool_gib"], (.records[] | [.name, .tiering.policy] + ([.space.used, .space.snapshot.used, .space.performance_tier_footprint, .space.capacity_tier_footprint] | map(((. // 0) / 1073741824 * 100 | round) / 100))) | @tsv'
SH

ID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE" --document-name AWS-RunShellScript \
  --comment "ontap-lab footprint" --parameters "$(jq -n --arg c "$REMOTE" '{commands: [$c]}')" \
  --query Command.CommandId --output text)

for _ in $(seq 1 30); do
  STATUS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$ID" --instance-id "$INSTANCE" --query Status --output text 2>/dev/null || true)
  case "$STATUS" in Success | Failed | TimedOut | Cancelled) break ;; esac
  sleep 3
done

date -u +"%Y-%m-%dT%H:%M:%SZ"
aws ssm get-command-invocation --region "$REGION" --command-id "$ID" --instance-id "$INSTANCE" \
  --query StandardOutputContent --output text | column -t
[ "$STATUS" = Success ] || { echo "SSM command $STATUS" >&2; exit 1; }
