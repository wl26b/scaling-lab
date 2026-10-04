---
name: lab-session
description: >
  Start-of-session and end-of-session checklist for scaling-lab AWS work: check
  spend against the budget, bring a stage up, and before teardown save load test
  results from S3, then confirm nothing billable is left. Use for "start a lab
  session", "bring stage N up", "wrap up", "tear down" or "end the session".
---

# Lab session

The AWS account is on the Free plan, with a budget alarm (`infra/budget/`) at $15 per month, and the region is `ap-southeast-1`. Stacks live in `infra/stageN/`. The user runs `terraform apply` and `terraform destroy` themselves. Claude prepares and explains the commands, runs the read-only checks, and never runs apply or destroy.

**Never destroy `infra/budget/`.** It is the spending alarm and costs nothing.

## Start

0. **Check login:** `aws sts get-caller-identity`. If it says the session has expired, ask the user to run `! aws login`, then retry.
1. **Check spend.** Run:
   ```bash
   aws budgets describe-budgets --account-id "$(aws sts get-caller-identity --query Account --output text)" \
     --query 'Budgets[].{name:BudgetName,limit:BudgetLimit.Amount,spent:CalculatedSpend.ActualSpend.Amount,forecast:CalculatedSpend.ForecastedSpend.Amount}' --output table
   ```
   Use the `scaling-lab` row. Its limit is **per month** and resets on the 1st, so it shows this month's spend only, not the project total. Report the spend so far and what is left. If the forecast is over the limit, say so before going further.
2. **Check for leftovers** from an earlier session (see "Leftover check" below). Anything running is costing money now.
3. **Bring the stage up.** Give the user the command and say what it creates and roughly what it costs per hour:
   `terraform -chdir=infra/stageN apply`. Include `-var loadgen_enabled=false` when this session needs no load test.
4. **Deploy the app** after apply: `./scripts/deploy.sh stageN`.
5. **Stages with RDS (2+): restart the database before measuring.** The first deploy seeds 2.5M rows, which pushes the 1 GB `db.t4g.micro` into swap, and swap causes 10–30 s requests (proven in `results/stage2/README.md`). Restart, then load test:
   ```bash
   aws rds reboot-db-instance --db-instance-identifier scaling-lab
   aws rds wait db-instance-available --db-instance-identifier scaling-lab
   ```
   Do the same after any other bulk load or re-seed.

## End

Do these in order. Step 1 matters: `terraform destroy` deletes the artifact bucket **with all results in it** (`force_destroy = true`).

1. **Save results.** Load test runs upload to `s3://<artifact_bucket>/results/<run-id>/`. Copy each new run into the repo:
   ```bash
   BUCKET=$(terraform -chdir=infra/stageN output -raw artifact_bucket)
   aws s3 ls "s3://$BUCKET/results/"
   aws s3 cp --recursive "s3://$BUCKET/results/<run-id>/" results/stageN/<run-name>/
   ```
   Check that the local files exist and `results.csv` has rows before going on.
2. **Save other evidence** the write-up needs (CloudWatch screenshots or numbers, log excerpts). It is gone after destroy.
3. **Commit** the saved results, after the user approves.
4. **Tear down.** Give the user: `terraform -chdir=infra/stageN destroy`.
5. **Leftover check** after the destroy finishes.

## Leftover check

Run all of these. Each must come back empty:

```bash
R=ap-southeast-1
aws ec2 describe-instances --region $R --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output table
aws rds describe-db-instances --region $R --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus]' --output table
aws ec2 describe-nat-gateways --region $R --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'
aws ec2 describe-addresses --region $R --query 'Addresses[].PublicIp'
```

Stopped instances still bill for their disks, so they count as leftovers. If anything remains, show what it is and which stack it belongs to, and let the user decide what to do.
