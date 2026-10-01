---
name: gcloud
description: How to run gcloud / kubectl on this machine — they are NOT installed natively; every call goes through the google/cloud-sdk docker image with a shared credentials dir. Use whenever a task needs GCP (Cloud Logging, GKE pods, Pub/Sub topics/subscriptions/backlog, Cloud Monitoring, IAM) — e.g. "查 stag log", "看 pod", "backlog 卡了幾則", "dead-letter", "誰有 publisher 權限".
---

# gcloud / kubectl on this machine

## The one fact everything else follows from

`gcloud` and `kubectl` are **not on PATH** and not under Homebrew. Do not
`brew install` them and do not look for `~/.kube/`. Every call is:

```bash
G=(docker run --rm --platform linux/amd64 \
   -v "$HOME/.config/gcloud-cli:/root/.config/gcloud" \
   -v "$HOME/.config/gcloud-cli/kube:/root/.kube" \
   google/cloud-sdk:latest)
"${G[@]}" gcloud <args>
```

- Credentials live in **`~/.config/gcloud-cli`** (mounted as the container's
  `~/.config/gcloud`); the kubeconfig lives beside them in
  `~/.config/gcloud-cli/kube` (mounted as `~/.kube`). `~/.config/gcloud/` on
  the host holds only a Cloud SQL service-account key for a proxy — it is not
  a login and must not be reused for anything else.
- Stay on the user's own login. A service-account key would not expire, but
  it is a long-lived secret on a laptop and every `seek` / `kubectl exec` /
  ConfigMap patch would be audited as the SA instead of the person.
- `--platform linux/amd64` silences the arm64 mismatch warning; the image has
  no arm64 build.
- The image ships `kubectl` and the GKE auth plugin, so no second image.

## Credentials expire daily

Check first; a stale login fails deep inside a query with
`Reauthentication failed. cannot prompt during non-interactive execution`:

```bash
"${G[@]}" gcloud auth list --filter=status:ACTIVE --format='value(account)'
```

Re-login needs a TTY. The `!` prefix in a CLI session has none, so the user
runs this in a real terminal:

```bash
docker run --rm -it -v ~/.config/gcloud-cli:/root/.config/gcloud \
  google/cloud-sdk:latest gcloud auth login --no-launch-browser
```

The auto-mode classifier may block `auth list`, `get-iam-policy`,
`kubectl exec … env` and similar as credential reads. When that happens,
hand the exact command to the user to run with `!` and continue from the
output — do not route around the block.

## The container is one-shot

Nothing persists between `docker run` calls except the two mounted dirs.
Consequences:

- `kubectl` works only after a cluster entry exists in the mounted
  kubeconfig. Run once per cluster (it writes `~/.config/gcloud-cli/kube/config`
  on the host); if `kubectl` says `localhost:8080 … connection refused`, the
  entry is missing or the `kube` mount was left out:
  ```bash
  "${G[@]}" gcloud container clusters get-credentials <cluster> --zone <zone> --project <project> -q
  "${G[@]}" kubectl get pods -n <ns>
  ```
  The kubeconfig stores no token — the GKE auth plugin asks gcloud each time,
  so the daily login expiry above still applies.
- Chain several gcloud calls in one `bash -c` to avoid paying image startup
  per call.
- Project IDs, cluster names, zones, namespaces and container names are
  **project knowledge**: read them from the repo's own skill or CLAUDE.md
  (`gke-migrate`, `aegis`, …), never guess.

## Cloud Logging

```bash
"${G[@]}" gcloud logging read \
  'resource.labels.container_name="<container>" AND "<keyword>"' \
  --project <project> --freshness 2h --limit 20 --order asc \
  --format 'value(timestamp,severity,textPayload)'
```

- Logs are UTC. Convert before comparing with Slack or a screenshot (Taipei
  = UTC+8).
- Nest/winston lines carry ANSI colour codes; pipe through
  `sed -E 's/\x1b\[[0-9;]*m//g'`.
- A multi-line stack trace is one entry per line. Query a ±2 s window around
  one timestamp with `--order asc` to read it whole.
- To find out which *other* service was active at a moment, query the window
  with `NOT resource.labels.container_name="<this one>"` and print
  `resource.labels.container_name`. Only `k8s_cluster` / `k8s_node` noise
  means the actor was outside the cluster.
- Pub/Sub data-access audit logs (`protoPayload.methodName="google.pubsub.v1.Publisher.Publish"`)
  are **off by default**; an empty result means "not enabled", not "nobody
  published".

## Pub/Sub

```bash
"${G[@]}" gcloud pubsub subscriptions list --project <project> \
  --format='value(name,topic,deadLetterPolicy.deadLetterTopic,deadLetterPolicy.maxDeliveryAttempts)'
"${G[@]}" gcloud pubsub subscriptions describe <sub> --project <project> \
  --format='yaml(topic,ackDeadlineSeconds,deadLetterPolicy,retryPolicy,messageRetentionDuration)'
```

- A topic named `<something>.failed` is usually a **dead-letter target**:
  list subscriptions and read the `deadLetterPolicy` column before assuming
  an application publishes to it.
- `subscriptions pull` (without `--auto-ack`) returns nothing while a running
  consumer holds the lease on the messages; it is not evidence of an empty
  backlog. Use the metrics below.
- `subscriptions seek --time=now` acks **every** outstanding message on that
  subscription. It is the way to drain poison messages, and it is
  destructive: the user runs it, never the agent.

## Cloud Monitoring (backlog, dead-letter counts)

`gcloud monitoring` has no `time-series` subcommand. Use the REST API with an
access token minted in the same container:

```bash
"${G[@]}" bash -c '
TOK=$(gcloud auth print-access-token)
END=$(date -u +%Y-%m-%dT%H:%M:%SZ); START=$(date -u -d "-2 hours" +%Y-%m-%dT%H:%M:%SZ)
M=num_undelivered_messages        # or oldest_unacked_message_age, dead_letter_message_count
curl -s -H "Authorization: Bearer $TOK" \
  "https://monitoring.googleapis.com/v3/projects/<project>/timeSeries?filter=metric.type%3D%22pubsub.googleapis.com%2Fsubscription%2F$M%22%20AND%20resource.labels.subscription_id%3D%22<sub>%22&interval.startTime=$START&interval.endTime=$END" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); ts=d.get(\"timeSeries\",[]); print([(p[\"interval\"][\"endTime\"][11:16], p[\"value\"]) for p in ts[0][\"points\"][:6]] if ts else \"none\")"'
```

- Points come **newest first**; reverse them before reading a timeline, or
  the earliest event is the one you truncate.
- The metric lags 1–2 minutes behind reality; after a `seek`, re-check after
  ~2 minutes before declaring the backlog drained.
- Omit the `subscription_id` clause to get every subscription in one call
  (useful for `dead_letter_message_count`: it names which subscription forwarded
  to a `.failed` topic and when).

## What to record afterwards

The project IDs, cluster, namespace, container names, Slack webhook ↔ channel
mapping and the Pub/Sub dead-letter topology are per-project facts. When a
session discovers one that is not already in that repo's skill or CLAUDE.md,
add it there — not here, and not to GLOBAL_RULES.md.
