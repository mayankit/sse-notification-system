# SSE Notification System

A production-grade real-time notification system using Node.js, Express, and Server-Sent Events (SSE). Architected to scale to **10 million concurrent users** with zero sticky sessions — all routing and coordination through Redis.

[![Node.js](https://img.shields.io/badge/Node.js-20+-green.svg)](https://nodejs.org/)
[![Docker](https://img.shields.io/badge/Docker-Ready-blue.svg)](https://www.docker.com/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue.svg)](https://www.postgresql.org/)
[![Redis](https://img.shields.io/badge/Redis-7-red.svg)](https://redis.io/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

- **Real-time Messaging**: Server-Sent Events for instant push notifications
- **User Authentication**: JWT-based signup/login with bcrypt password hashing
- **Horizontal Scaling**: Zero sticky sessions - any node can serve any user
- **Multi-Node Architecture**: 3 load-balanced nodes in development
- **Offline Message Queue**: Messages queued when users are offline
- **Cross-Node Communication**: Redis Pub/Sub for message routing
- **Rate Limiting**: Redis-based rate limiting per user
- **Graceful Shutdown**: Connection draining with reconnect signaling
- **Cloud Ready**: Infrastructure as Code for AWS, GCP, and Azure

## One-Command Setup

### macOS / Linux
```bash
git clone https://github.com/mayankit/sse-notification-system.git
cd sse-notification-system
chmod +x scripts/setup-local.sh
./scripts/setup-local.sh
```

### Windows (Run as Administrator)
```powershell
git clone https://github.com/mayankit/sse-notification-system.git
cd sse-notification-system
.\scripts\setup-local.ps1
```

This script automatically:
- Installs Docker if needed
- Starts Docker daemon
- Builds and runs all services (PostgreSQL, Redis, 3 app nodes, Nginx)
- Opens the application in your browser

## Manual Quick Start

```bash
# Start everything (PostgreSQL + Redis + 3 app nodes + Nginx)
docker compose up --build

# Chat UI with login/signup
open http://localhost:3000/chat.html

# Legacy test UI
open http://localhost:3000

# Node health dashboard
open http://localhost:3000/dashboard.html

# Individual node health (bypasses Nginx)
curl http://localhost:3001/health
curl http://localhost:3002/health
curl http://localhost:3003/health

# Grafana Dashboard (admin/admin)
open http://localhost:3030

# Prometheus UI
open http://localhost:9090
```

## Monitoring & Metrics

The system includes built-in monitoring with **Prometheus** and **Grafana**:

| URL | Description | Credentials |
|-----|-------------|-------------|
| http://localhost:3030 | Grafana Dashboard | admin / admin |
| http://localhost:9090 | Prometheus UI | - |
| http://localhost:3000/metrics | Prometheus metrics | - |

### Available Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `sse_connected_users` | Gauge | Currently connected SSE users |
| `sse_messages_sent_total` | Counter | Messages delivered to online users |
| `sse_messages_queued_total` | Counter | Messages queued for offline users |
| `sse_connections_total` | Counter | Total SSE connections established |
| `sse_disconnections_total` | Counter | Total SSE disconnections |
| `sse_auth_success_total` | Counter | Successful authentications |
| `sse_auth_failure_total` | Counter | Failed authentications |
| `sse_errors_total` | Counter | Total errors |
| `sse_memory_heap_bytes` | Gauge | Heap memory usage |
| `sse_redis_connected` | Gauge | Redis connection status (1=up, 0=down) |
| `sse_db_connected` | Gauge | PostgreSQL connection status |

### Data Persistence

All data is persisted across restarts using Docker volumes:

| Service | Volume | Description |
|---------|--------|-------------|
| PostgreSQL | `postgres_data` | User accounts, credentials |
| Redis | `redis_data` | Sessions, message queues (AOF enabled) |
| Prometheus | `prometheus_data` | Metrics history |
| Grafana | `grafana_data` | Dashboard configurations |

```bash
# View volumes
docker volume ls

# Remove all data (fresh start)
docker compose down -v
```

## How to Prove No Sticky Sessions

1. Open http://localhost:3000
2. Watch the "Connected to: server_X" badge on each panel. Alice, Bob, Carol land on different nodes (round-robin).
3. Send a message from Alice (server_1) to Carol (server_3). It delivers instantly despite different nodes.
4. Disconnect Bob. Send him messages from Alice and Carol. Reconnect Bob — watch the queued flush deliver all missed messages.
5. Open dashboard.html — confirm users are spread across nodes and all three nodes show connectedUsers = 1.

## Switching Redis in Production

The application code never changes. Only environment variables change.

**AWS ElastiCache:**
```
REDIS_URL=rediss://your-cluster.cache.amazonaws.com:6380
REDIS_TLS=true
```

**GCP Memorystore:**
```
REDIS_URL=redis://10.0.0.3:6379
REDIS_TLS=false
```

**Upstash (serverless, zero infrastructure):**
```
REDIS_URL=rediss://default:token@your.upstash.io:6380
REDIS_TLS=true
```

**Self-hosted Redis Cluster:**
```
REDIS_URL=redis://redis-cluster-hostname:6379
REDIS_TLS=false
```

## Architecture

### Local Dev (docker-compose)

```
Browser (Alice, Bob, Carol)
      │
Nginx :3000  (round-robin, NO sticky)
 ├── app1 :3001  (server_1)
 ├── app2 :3002  (server_2)
 └── app3 :3003  (server_3)
      │
Redis :6379  (Docker container)
```

### Production (any cloud)

```
Browser (millions of users)
      │
Cloud Load Balancer  (round-robin, NO sticky)
 ├── app pod / instance  (server_A)
 ├── app pod / instance  (server_B)
 └── app pod / instance  (server_N)
      │
Managed Redis  (ElastiCache / Memorystore / Upstash)
(no Redis in docker-compose, no Redis in app servers)
```

### Message Flow (cross-node delivery)

```
Alice (server_1)  →  POST /send  →  Nginx  →  server_3
                                                   │
                                          HGET user:bob:session
                                          → { serverId: "server_2" }
                                                   │
                                          PUBLISH user:bob {payload}
                                                   │
                                                Redis
                                                   │
                                          server_2 SUBSCRIBE fires
                                                   │
                                          localClients.get("bob").write()
                                                   │
                                          Bob receives message
```

## What Changes at 10M Users

### DOES change (infrastructure only):
- Redis → Redis Cluster (sharding across multiple Redis nodes)
- Add more app server instances behind load balancer
- Use CDN edge (Cloudflare, Fastly) to terminate SSE at the edge
- Replace Nginx with cloud load balancer (AWS ALB, GCP LB)
- Use secret manager (AWS Secrets Manager, GCP Secret Manager) to inject REDIS_URL instead of env files

### DOES NOT change:
- Application code — zero lines
- API contract — identical endpoints
- Pub/sub pattern — same Redis channels
- Two-layer state model — localClients + Redis metadata
- Client-side EventSource code — unchanged

## API Endpoints

See [API.md](./API.md) for complete API documentation with examples.

### Quick Reference

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/auth/signup` | No | Create new user account |
| POST | `/auth/login` | No | Login and get JWT token |
| GET | `/auth/me` | Yes | Get current user info |
| GET | `/events` | Yes | SSE connection endpoint |
| POST | `/send` | Yes | Send message to user |
| GET | `/users` | Yes | List all users with online status |
| GET | `/health` | No | Health check |

### Authentication

All endpoints except `/auth/signup`, `/auth/login`, and `/health` require JWT authentication:

```bash
# Get token via login
TOKEN=$(curl -s -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "password123"}' | jq -r '.token')

# Use token in requests
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/users

# Or pass as query param for SSE
curl -N "http://localhost:3000/events?token=$TOKEN"
```

## Project Structure

```
src/
  config/
    index.js          — Environment configuration
    database.js       — PostgreSQL connection pool
    redis.js          — Redis client factory
  connections/
    manager.js        — SSE connection management
  models/
    User.js           — User model (CRUD, password verification)
  services/
    inbox.js          — Offline message queue
  messaging/
    publisher.js      — Redis pub/sub publisher
    subscriber.js     — Redis pub/sub subscriber
  middleware/
    auth.js           — JWT authentication middleware
    rateLimit.js      — Redis-based rate limiting
  routes/
    auth.js           — POST /auth/signup, /auth/login, GET /auth/me
    events.js         — GET /events (SSE)
    send.js           — POST /send
    users.js          — GET /users
    health.js         — GET /health
  utils/
    jwt.js            — JWT token utilities
  server.js           — Express setup, graceful shutdown

public/
  chat.html           — Chat UI with login/signup
  index.html          — Legacy 3-panel test UI
  dashboard.html      — 3-node health dashboard

infra/
  aws/                — AWS CDK (ECS + RDS + ElastiCache)
  gcp/                — GCP Terraform (Cloud Run + Cloud SQL + Memorystore)
  azure/              — Azure Terraform (Container Apps + PostgreSQL + Redis)
```

## Data Models

### PostgreSQL (Users)

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(50) UNIQUE NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  display_name VARCHAR(100),
  avatar VARCHAR(10),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  last_login TIMESTAMP WITH TIME ZONE
);
```

### Redis (Sessions & Messaging)

| Key | Type | TTL | Value |
|-----|------|-----|-------|
| `user:{uuid}:session` | HASH | 24hr | `{ serverId, connectedAt, lastEventId }` |
| `server:{serverId}:status` | STRING | 60s* | `"active"` (*refreshed every 30s) |
| `inbox:{uuid}` | LIST | 7 days | JSON stringified message objects |
| `ratelimit:{uuid}:{window}` | STRING | 60s | integer count |
| `event:id:counter` | STRING | none | global integer, only ever INCR'd |
| `stream:{uuid}` | STREAM | 1hr | MAXLEN 500, entries: `{event, data}` |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | 3000 |
| `SERVER_ID` | Unique server identifier | server_1 |
| `DATABASE_URL` | PostgreSQL connection string | postgresql://postgres:postgres@localhost:5432/sseapp |
| `REDIS_URL` | Redis connection URL | redis://localhost:6379 |
| `REDIS_TLS` | Enable TLS for Redis | false |
| `JWT_SECRET` | JWT signing secret | (change in production!) |
| `JWT_EXPIRES_IN` | JWT token expiration | 7d |
| `HEARTBEAT_INTERVAL` | Heartbeat interval in ms | 30000 |
| `MAX_CONNECTIONS_PER_SERVER` | Max SSE connections | 50000 |
| `INBOX_TTL_SECONDS` | Offline message TTL | 604800 (7 days) |
| `EVENT_STREAM_MAXLEN` | Max events in stream | 500 |
| `EVENT_STREAM_TTL` | Stream TTL in seconds | 3600 |
| `RATE_LIMIT_MAX` | Max requests per window | 100 |
| `RATE_LIMIT_WINDOW_SECONDS` | Rate limit window | 60 |

For cloud deployments, you can also use individual database variables:
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`

## Cloud Deployment (One Command)

### AWS
```bash
cd infra/aws
./deploy.sh deploy
```

### Google Cloud Platform
```bash
cd infra/gcp
export GCP_PROJECT_ID=your-project-id
./deploy.sh deploy
```

### Microsoft Azure
```bash
cd infra/azure
./deploy.sh deploy
```

## Documentation

| Guide | Description |
|-------|-------------|
| [Local Setup](docs/LOCAL_SETUP.md) | Complete local setup for Mac, Linux, Windows |
| [AWS Deployment](docs/AWS_DEPLOYMENT.md) | Deploy to AWS using CDK |
| [GCP Deployment](docs/GCP_DEPLOYMENT.md) | Deploy to GCP using Terraform |
| [Azure Deployment](docs/AZURE_DEPLOYMENT.md) | Deploy to Azure using Terraform |

## License

MIT
