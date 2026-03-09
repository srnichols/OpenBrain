# Open Brain - Self-Hosted Kubernetes Deployment

> Tailored for the homelab: 3-node K8s cluster with Tailscale, Cloudflare, MetalLB, and Ollama.

---

## Your Cluster At a Glance

| Component | Details |
|---|---|
| **Nodes** | 3x `node-{1,2,3}` — 32 CPU / 96GB RAM each |
| **OS** | Ubuntu 24.04.4 LTS, K8s v1.31.14, containerd 1.7.28 |
| **CNI** | Flannel (vxlan), pod CIDR 10.244.x.0/24 |
| **Load Balancer** | MetalLB — IP pool on 192.168.x.x |
| **Ingress** | ingress-nginx |
| **Storage** | local-path provisioner → `/mnt/k8s-data/` |
| **DNS** | Cloudflare (namespace: `cloudflare`) |
| **VPN** | Tailscale (namespace: `tailscale`) |
| **TLS** | cert-manager (namespace: `cert-manager`) |
| **Existing DB** | Citus PostgreSQL (coordinator + 3 workers + 2 standby) |
| **Existing Cache** | Redis 3-replica HA with Sentinel |
| **Existing Messaging** | NATS 3-replica |
| **Service Mesh** | Dapr 1.16.3 (dapr-system namespace) |
| **Monitoring** | Prometheus HA, Grafana HA, Loki HA, Elasticsearch |
| **AI** | Ollama GPU Bridge at `ollama-gpu-bridge:11434` (llama3.2) |
| **App namespace** | `your-namespace` (existing app) |

---

## Architecture for Open Brain on Your Cluster

```
┌─────────────────────────────────────────────────────────────────────┐
│  K8s Cluster: node-{1,2,3}                              │
│                                                                     │
│  Namespace: openbrain                                               │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                                                              │   │
│  │  ┌─────────────────┐  ┌──────────────────────────────────┐  │   │
│  │  │  PostgreSQL      │  │  open-brain-api                  │  │   │
│  │  │  + pgvector      │  │  (Node/TS + Hono)                       │  │   │
│  │  │                  │  │                                   │  │   │
│  │  │  StatefulSet     │  │  - REST API (:8000)              │  │   │
│  │  │  1 replica       │  │  - MCP server (:8080)            │  │   │
│  │  │  PVC: 10Gi       │  │  - Capture + Search + Stats     │  │   │
│  │  │  local-path      │  │                                   │  │   │
│  │  └────────┬─────────┘  │  Deployment, 2 replicas          │  │   │
│  │           │             └──────────┬───────────────────────┘  │   │
│  │           │                        │                          │   │
│  │           └────────────────────────┘                          │   │
│  │                                                               │   │
│  │  ┌──────────────────────────────────────────────────────────┐ │   │
│  │  │  Shared from your-namespace (cross-namespace access)      │ │   │
│  │  │                                                           │ │   │
│  │  │  • ollama-gpu-bridge:11434  (embeddings + LLM)           │ │   │
│  │  │  • prometheus-ha            (metrics scraping)           │ │   │
│  │  │  • grafana-ha               (dashboards)                 │ │   │
│  │  │  • loki-ha                  (log aggregation)            │ │   │
│  │  └──────────────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  External Access:                                                   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  MetalLB LoadBalancer → 192.168.x.x (MCP + API)          │   │
│  │  Tailscale → Private access from your devices               │   │
│  │  Cloudflare Tunnel → brain.yourdomain.com (public MCP)      │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## What's Different from Nate's Supabase Version

| Nate's Stack | Your Self-Hosted Stack | Why |
|---|---|---|
| Supabase PostgreSQL | Dedicated PostgreSQL + pgvector pod | Full control, same cluster |
| Supabase Edge Functions (Deno) | Node.js + Hono (TypeScript) | Same language family as Nate's Deno, full MCP SDK |
| OpenRouter API | Ollama (`ollama-gpu-bridge:11434`) | Free, private, already running |
| `text-embedding-3-small` (1536-dim) | `nomic-embed-text` or `mxbai-embed-large` (768-1024 dim) | Local GPU, zero cost |
| `gpt-4o-mini` (metadata) | `llama3.2` via Ollama | Already configured in your MCP server |
| Supabase Dashboard | pgAdmin (existing) | Self-hosted UI |
| Supabase RLS | PostgreSQL native RLS | Same mechanism, you control policies |
| `?key=` URL auth | Kubernetes Secrets + Tailscale ACLs | Network-level + app-level auth |

---

## Key Advantage: Ollama Is Already Running

Your existing MCP server deployment already references Ollama:

```yaml
# From your your-mcp-server-deployment.yaml
- name: Ollama__Endpoint
  value: "http://ollama-gpu-bridge:11434"
- name: Ollama__Enabled
  value: "true"
- name: Ollama__DefaultModel
  value: "llama3.2"
```

Open Brain will use the **same Ollama instance** for:
1. **Embeddings**: `nomic-embed-text` model (768-dim vectors) — pull once, use forever
2. **Metadata extraction**: `llama3.2` — already loaded

Cross-namespace access: `http://ollama-gpu-bridge.your-namespace.svc.cluster.local:11434`

---

## Deployment Steps

### Step 1: Create Namespace

```bash
kubectl create namespace openbrain
kubectl label namespace openbrain pod-security.kubernetes.io/enforce=privileged
```

### Step 2: Pull Ollama Embedding Model

```bash
# Exec into Ollama pod and pull the embedding model
kubectl exec -n your-namespace deploy/ollama-gpu-bridge -- ollama pull nomic-embed-text
```

### Step 3: Copy ACR Pull Secret

```bash
# Copy the existing ACR pull secret from your-namespace to openbrain namespace
kubectl get secret acr-pull-secret -n your-namespace -o yaml \
  | sed 's/namespace: your-namespace/namespace: openbrain/' \
  | kubectl apply -f -
```

### Step 4: Apply Manifests

```bash
# From E:\GitHub\OpenBrain\k8s\ directory
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/openbrain-secrets-actual.yaml   # Your actual secrets (gitignored)
kubectl apply -f k8s/postgres-statefulset.yaml
kubectl apply -f k8s/openbrain-api-deployment.yaml
kubectl apply -f k8s/openbrain-api-service-metallb.yaml
kubectl apply -f k8s/openbrain-tailscale-service.yaml  # Tailscale MagicDNS access
```

### Step 5: Wait and Verify

```bash
# Wait for postgres to be ready (init.sql runs automatically via ConfigMap)
kubectl wait --for=condition=ready pod -l app=openbrain-postgres -n openbrain --timeout=120s

# Wait for API pods
kubectl wait --for=condition=ready pod -l app=openbrain-api -n openbrain --timeout=120s

# Check all pods
kubectl get pods -n openbrain

# Check services (MetalLB + Tailscale)
kubectl get svc -n openbrain
```

### Step 6: Test Endpoints

```bash
# Via MetalLB (LAN)
curl -s http://192.168.x.x:8000/health
curl -s http://192.168.x.x:8080/health

# Via Tailscale MagicDNS (anywhere on your tailnet)
curl -s http://openbrain.your-tailnet.ts.net:8000/health
curl -s http://openbrain.your-tailnet.ts.net:8080/health

# Test MCP SSE auth
curl -s "http://openbrain.your-tailnet.ts.net:8080/sse?key=YOUR_MCP_KEY" --max-time 2
```

### Step 7: Configure AI Clients

See [04-MCP-SERVER.md](04-MCP-SERVER.md) for client configs. Use these URLs:

| Client | URL |
|---|---|
| Claude Code / Cursor (Tailscale) | `http://openbrain.your-tailnet.ts.net:8080/sse?key=<KEY>` |
| Claude Code / Cursor (LAN) | `http://192.168.x.x:8080/sse?key=<KEY>` |
| Claude Desktop (Tailscale) | `http://openbrain.your-tailnet.ts.net:8080/sse?key=<KEY>` |

---

## Networking Options

### Option A: Tailscale MagicDNS (Private, Anywhere) ✅ Active

Access Open Brain from **any device on your Tailscale network**, anywhere in the world.
Uses the Tailscale K8s Operator with a `loadBalancerClass: tailscale` service.

```
Any device on your tailnet (laptop, phone, tablet, other servers)
  → http://openbrain.your-tailnet.ts.net:8000  (REST API)
  → http://openbrain.your-tailnet.ts.net:8080  (MCP SSE)
```

- **Tailscale IP**: `100.x.x.x`
- **MagicDNS**: `openbrain.your-tailnet.ts.net`
- **Encryption**: WireGuard tunnel (end-to-end encrypted, no TLS certs needed)
- **Auth**: MCP access key still required for MCP endpoints

### Option B: MetalLB LAN (Local Network) ✅ Active

Access from devices on your home network (192.168.x.x).

```
Devices on LAN
  → http://192.168.x.x:8000  (REST API)
  → http://192.168.x.x:8080  (MCP SSE)
```

### Option C: Cloudflare Tunnel (Public MCP, Optional)

Only needed for cloud AI services that require a public URL (Claude Desktop remote, ChatGPT plugins).
Since Claude Code and Cursor work locally with Tailscale, this is optional.

```
Claude Desktop / ChatGPT
  → https://brain.yourdomain.com (Cloudflare Tunnel)
  → Cloudflare namespace → ingress-nginx → openbrain-api service
```

Create a Cloudflare Tunnel pointing to the ClusterIP service:
```yaml
# In your cloudflare tunnel config
- hostname: brain.yourdomain.com
  service: http://openbrain-api.openbrain.svc.cluster.local:8080
```

---

## Monitoring Integration

Your existing Prometheus + Grafana + Loki stack can monitor Open Brain:

### Prometheus Scraping

The API deployment includes Prometheus annotations:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8000"
  prometheus.io/path: "/metrics"
```

### Grafana Dashboard

Import a Node.js/Hono dashboard or create custom panels for:
- Request rate to `/memories/search` and `/memories` endpoints
- Embedding generation latency (Ollama round-trip)
- PostgreSQL query duration
- Thought capture rate

### Loki Log Aggregation

Pod logs auto-collected by your existing Loki setup. Filter by:
```
{namespace="openbrain", app="openbrain-api"}
```

---

## Cost

| Component | Cost |
|---|---|
| PostgreSQL pod | ~256Mi RAM, 100m CPU (from your existing pool) |
| API pod (x2) | ~512Mi RAM, 200m CPU total |
| Ollama (shared) | Already running |
| Storage (10Gi PVC) | Local disk |
| Network (Tailscale/Cloudflare) | Already running |
| **Total** | **$0/month** (all self-hosted) |

---

## Comparison: Supabase vs Your Homelab

| Aspect | Supabase Free Tier | Your Homelab |
|---|---|---|
| Database | 500MB, shared infra | Unlimited, dedicated |
| Edge Function invocations | 500K/month | Unlimited |
| Embedding cost | $0.02/M tokens (OpenRouter) | $0 (Ollama local) |
| LLM metadata cost | $0.15/M tokens (gpt-4o-mini) | $0 (llama3.2 local) |
| Latency | Cloud round-trip | Local network (~1ms) |
| Privacy | Data on Supabase servers | Data never leaves your network |
| Uptime | Supabase SLA | Your responsibility |
| **Monthly cost** | **$0.10-$0.30** | **$0** |
