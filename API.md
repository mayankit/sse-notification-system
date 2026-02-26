# API Reference

Complete API documentation for the SSE Notification System.

## Base URL

- **Local Development**: `http://localhost:3000`
- **Direct Node Access**: `http://localhost:3001`, `http://localhost:3002`, `http://localhost:3003`

## Authentication

Most endpoints require JWT authentication. Include the token in:

**Authorization Header (preferred):**
```
Authorization: Bearer <token>
```

**Query Parameter (for SSE):**
```
GET /events?token=<token>
```

---

## Authentication Endpoints

### POST /auth/signup

Create a new user account.

**Request:**
```bash
curl -X POST http://localhost:3000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "username": "alice",
    "email": "alice@example.com",
    "password": "password123",
    "displayName": "Alice Smith"
  }'
```

**Request Body:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `username` | string | Yes | Unique username (3-50 chars, alphanumeric + underscore) |
| `email` | string | Yes | Valid email address |
| `password` | string | Yes | Password (min 6 characters) |
| `displayName` | string | No | Display name (defaults to username) |

**Response (201 Created):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "username": "alice",
    "email": "alice@example.com",
    "displayName": "Alice Smith",
    "avatar": "A"
  }
}
```

**Error Responses:**
| Status | Description |
|--------|-------------|
| 400 | Missing required fields or invalid format |
| 409 | Username or email already exists |
| 500 | Server error |

---

### POST /auth/login

Authenticate and receive a JWT token.

**Request:**
```bash
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "alice",
    "password": "password123"
  }'
```

**Request Body:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `username` | string | Yes | Username |
| `password` | string | Yes | Password |

**Response (200 OK):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "username": "alice",
    "email": "alice@example.com",
    "displayName": "Alice Smith",
    "avatar": "A"
  }
}
```

**Error Responses:**
| Status | Description |
|--------|-------------|
| 400 | Missing username or password |
| 401 | Invalid credentials |
| 500 | Server error |

---

### GET /auth/me

Get current authenticated user's information.

**Request:**
```bash
curl http://localhost:3000/auth/me \
  -H "Authorization: Bearer <token>"
```

**Response (200 OK):**
```json
{
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "username": "alice",
    "email": "alice@example.com",
    "displayName": "Alice Smith",
    "avatar": "A",
    "createdAt": "2024-01-15T10:30:00.000Z"
  }
}
```

**Error Responses:**
| Status | Description |
|--------|-------------|
| 401 | Not authenticated or invalid token |
| 404 | User not found |

---

## SSE (Server-Sent Events) Endpoint

### GET /events

Establish a Server-Sent Events connection for real-time notifications.

**Request:**
```bash
# Using query parameter (recommended for EventSource)
curl -N "http://localhost:3000/events?token=<token>"

# Using Authorization header
curl -N http://localhost:3000/events \
  -H "Authorization: Bearer <token>"
```

**Query Parameters:**
| Parameter | Required | Description |
|-----------|----------|-------------|
| `token` | Yes* | JWT token (*or use Authorization header) |

**Headers:**
| Header | Description |
|--------|-------------|
| `Last-Event-ID` | Resume from specific event ID after reconnection |

**Response:** Server-Sent Events stream

**Event Types:**

#### `connected`
Sent immediately upon successful connection.
```
event: connected
data: {"userId":"550e8400-e29b-41d4-a716-446655440000","serverId":"server_1","connectedAt":"2024-01-15T10:30:00.000Z"}
```

#### `queued`
Sent after connection with any messages that arrived while offline.
```
event: queued
data: {"messages":[{"from":"bob-uuid","type":"chat","data":{"text":"Hello!"},"timestamp":"..."}]}
```

#### `message`
Real-time message from another user.
```
event: message
id: 42
data: {"from":"bob-uuid","type":"chat","data":{"text":"Hello Alice!"},"timestamp":"2024-01-15T10:35:00.000Z"}
```

#### `heartbeat`
Keep-alive signal sent every 30 seconds.
```
event: heartbeat
data: {"timestamp":"2024-01-15T10:35:00.000Z","serverId":"server_1"}
```

#### `reconnect`
Server requesting client to reconnect (during graceful shutdown).
```
event: reconnect
data: {"reason":"server_drain","retryAfter":2}
```

**JavaScript Client Example:**
```javascript
const token = 'your-jwt-token';
const eventSource = new EventSource(`/events?token=${token}`);

eventSource.addEventListener('connected', (e) => {
  const data = JSON.parse(e.data);
  console.log('Connected to:', data.serverId);
});

eventSource.addEventListener('message', (e) => {
  const message = JSON.parse(e.data);
  console.log('Message from:', message.from, message.data);
});

eventSource.addEventListener('queued', (e) => {
  const data = JSON.parse(e.data);
  console.log('Offline messages:', data.messages.length);
});

eventSource.onerror = (e) => {
  console.log('Connection error, will auto-reconnect');
};
```

---

## Messaging Endpoint

### POST /send

Send a message to another user.

**Request:**
```bash
curl -X POST http://localhost:3000/send \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{
    "to": "550e8400-e29b-41d4-a716-446655440001",
    "type": "chat",
    "data": {
      "text": "Hello Bob!"
    }
  }'
```

**Request Body:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `to` | string (UUID) | Yes | Recipient's user ID |
| `type` | string | Yes | Message type (e.g., "chat", "notification") |
| `data` | object | Yes | Message payload |

**Response (200 OK) - User Online:**
```json
{
  "success": true,
  "queued": false,
  "eventId": 42,
  "deliveredTo": "server_2"
}
```

**Response (200 OK) - User Offline:**
```json
{
  "success": true,
  "queued": true,
  "message": "User is offline, message queued"
}
```

**Error Responses:**
| Status | Description |
|--------|-------------|
| 400 | Missing required fields |
| 401 | Not authenticated |
| 429 | Rate limit exceeded |
| 500 | Server error |

**Message Types:**
You can use any string as the message type. Common types:
- `chat` - Chat messages
- `notification` - System notifications
- `typing` - Typing indicators
- `read` - Read receipts
- `presence` - Presence updates

---

## User Endpoints

### GET /users

List all registered users with their online status.

**Request:**
```bash
curl http://localhost:3000/users \
  -H "Authorization: Bearer <token>"
```

**Response (200 OK):**
```json
{
  "users": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "username": "alice",
      "displayName": "Alice Smith",
      "avatar": "A",
      "online": true,
      "serverId": "server_1"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "username": "bob",
      "displayName": "Bob Jones",
      "avatar": "B",
      "online": false,
      "serverId": null
    }
  ]
}
```

**Response Fields:**
| Field | Description |
|-------|-------------|
| `id` | User's UUID |
| `username` | Username |
| `displayName` | Display name |
| `avatar` | Avatar character (first letter of display name) |
| `online` | Whether user is currently connected via SSE |
| `serverId` | Which server node they're connected to (null if offline) |

---

## Health Endpoint

### GET /health

Health check endpoint for load balancers and monitoring.

**Request:**
```bash
curl http://localhost:3000/health
```

**Response (200 OK):**
```json
{
  "status": "ok",
  "serverId": "server_1",
  "connectedUsers": 5,
  "maxConnections": 50000,
  "redisStatus": "ok",
  "dbStatus": "ok",
  "uptime": 3600,
  "shuttingDown": false,
  "memoryMB": 48
}
```

**Response Fields:**
| Field | Description |
|-------|-------------|
| `status` | Overall health status ("ok" or "degraded") |
| `serverId` | Unique identifier for this server node |
| `connectedUsers` | Number of active SSE connections |
| `maxConnections` | Maximum allowed connections |
| `redisStatus` | Redis connection status |
| `dbStatus` | PostgreSQL connection status |
| `uptime` | Server uptime in seconds |
| `shuttingDown` | Whether server is in graceful shutdown mode |
| `memoryMB` | Memory usage in megabytes |

---

## Rate Limiting

All authenticated endpoints are rate limited:

- **Default**: 100 requests per 60 seconds per user
- **Response when exceeded**: `429 Too Many Requests`

```json
{
  "error": "rate_limit_exceeded",
  "retryAfter": 45
}
```

---

## Error Responses

All errors follow this format:

```json
{
  "error": "error_code",
  "message": "Human readable description"
}
```

**Common Error Codes:**
| Code | Status | Description |
|------|--------|-------------|
| `unauthorized` | 401 | Missing or invalid authentication |
| `forbidden` | 403 | Insufficient permissions |
| `not_found` | 404 | Resource not found |
| `validation_error` | 400 | Invalid request body |
| `rate_limit_exceeded` | 429 | Too many requests |
| `internal_error` | 500 | Server error |

---

## Complete Example: Chat Session

```bash
# 1. Create two users
curl -X POST http://localhost:3000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "email": "alice@example.com", "password": "pass123"}'

curl -X POST http://localhost:3000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"username": "bob", "email": "bob@example.com", "password": "pass123"}'

# 2. Login as both users
ALICE_TOKEN=$(curl -s -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "pass123"}' | jq -r '.token')

BOB_TOKEN=$(curl -s -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "bob", "password": "pass123"}' | jq -r '.token')

# 3. Get user list to find Bob's ID
BOB_ID=$(curl -s http://localhost:3000/users \
  -H "Authorization: Bearer $ALICE_TOKEN" | jq -r '.users[] | select(.username=="bob") | .id')

# 4. In Terminal 1: Connect Alice to SSE
curl -N "http://localhost:3000/events?token=$ALICE_TOKEN"

# 5. In Terminal 2: Connect Bob to SSE
curl -N "http://localhost:3000/events?token=$BOB_TOKEN"

# 6. In Terminal 3: Send message from Alice to Bob
curl -X POST http://localhost:3000/send \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ALICE_TOKEN" \
  -d "{\"to\": \"$BOB_ID\", \"type\": \"chat\", \"data\": {\"text\": \"Hello Bob!\"}}"

# Bob's terminal will show:
# event: message
# data: {"from":"alice-uuid","type":"chat","data":{"text":"Hello Bob!"},...}
```

---

## WebSocket Alternative Note

This system uses **Server-Sent Events (SSE)** instead of WebSockets because:

1. **Simpler Protocol**: HTTP-based, works through all proxies and load balancers
2. **Automatic Reconnection**: Built into the EventSource API
3. **One-Way Optimal**: Perfect for server-to-client push (which is our use case)
4. **No Special Infrastructure**: Works with standard HTTP load balancers

For bidirectional communication, clients use:
- SSE for receiving (GET /events)
- REST for sending (POST /send)

This hybrid approach gives us the best of both worlds while remaining simple and scalable.
