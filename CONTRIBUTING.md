# Contributing to Open Brain

Thanks for your interest in contributing! Open Brain is a personal semantic memory server for AI coding agents. Here's how to get involved.

## Development Setup

### Prerequisites

- **Node.js 22+** — [Download](https://nodejs.org/)
- **Docker** — For running PostgreSQL locally
- **Ollama** — For local embeddings ([ollama.com](https://ollama.com))

### Getting Started

```bash
# Clone the repo
git clone https://github.com/srnichols/OpenBrain.git
cd OpenBrain

# Install dependencies
npm install

# Copy environment config
cp .env.example .env
# Edit .env with your settings

# Pull embedding models
ollama pull nomic-embed-text
ollama pull llama3.2

# Start PostgreSQL
docker compose up -d postgres

# Run in dev mode (hot reload)
npm run dev
```

### Verify Setup

```bash
# Type check
npm run typecheck

# Build
npm run build

# Run tests
npm test

# Health check (after starting dev server)
curl http://localhost:8000/health
```

## Project Structure

See [01-ARCHITECTURE.md](01-ARCHITECTURE.md) for the full system architecture and data flows.

```
src/
├── index.ts              # Entry point — REST + MCP servers
├── api/
│   └── routes.ts         # Hono REST API (8 routes)
├── mcp/
│   └── server.ts         # MCP server (7 tools)
├── db/
│   ├── connection.ts     # PostgreSQL pool (singleton)
│   └── queries.ts        # Parameterized SQL queries (7 functions)
└── embedder/
    ├── types.ts           # Embedder interface + 13 thought types
    ├── index.ts           # Provider factory
    ├── ollama.ts          # Ollama provider
    └── openrouter.ts      # OpenRouter provider
```

## Coding Conventions

- **TypeScript strict mode** — No `any`, explicit types on function signatures
- **Parameterized SQL** — Never interpolate user input into queries
- **Async/await** — All I/O operations are async
- **Error handling** — All catch blocks log and return structured JSON
- **Layer separation** — DB queries → MCP tools / REST routes (no business logic in routes)

## Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(mcp): add bulk delete tool
fix(queries): handle null project in stats query
test(api): add batch capture validation tests
docs(readme): update MCP tool reference
chore(deps): update vitest to 4.2
```

## Testing

### Unit Tests

- **Framework**: Vitest
- **Run**: `npm test`
- **Pattern**: Unit tests with mocked pg pool and embedder
- **Location**: `src/**/__tests__/*.test.ts`

All new features must include unit tests. All existing tests must continue to pass.

### Integration Tests

- **Run**: `npm run test:integration`
- **Requires**: A running Open Brain server (local or remote)
- **Location**: `src/__integration__/*.test.ts`
- **Coverage**: 27 tests — full CRUD lifecycle, validation, filtering, created_by

Set `OPENBRAIN_API_URL` to point at your deployment:

```bash
# Local Docker Compose
OPENBRAIN_API_URL=http://localhost:8000 npm run test:integration

# K8s via port-forward
kubectl port-forward -n openbrain svc/openbrain-api 8000:8000
OPENBRAIN_API_URL=http://localhost:8000 npm run test:integration

# Remote
OPENBRAIN_API_URL=https://your-host npm run test:integration
```

Integration tests auto-clean up all created test data. They are excluded from `npm test` to keep the unit test run fast.

## Pull Request Process

1. Fork the repo and create a branch from `master`
2. Make your changes
3. Ensure all checks pass:
   ```bash
   npm run typecheck
   npm run build
   npm test
   ```
4. Open a PR using the [PR template](.github/pull_request_template.md)
5. Address any review feedback

## What We're Looking For

- Bug fixes with regression tests
- New MCP tools or REST endpoints (with tests)
- Performance improvements (with benchmarks)
- Documentation improvements
- New embedding provider integrations

## What We're NOT Looking For

- UI/frontend (Open Brain is backend-only)
- Breaking changes to existing API contracts
- New database tables (extend the existing `thoughts` table)
- Changes to embedding dimensions

## Questions?

Open a [Discussion](https://github.com/srnichols/OpenBrain/discussions) or reach out on [LinkedIn](https://www.linkedin.com/in/srnichols/).
