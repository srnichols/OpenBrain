# Open Brain — Easy Setup Prompt

Paste this prompt into **any** AI chat (VS Code Copilot Agent Mode, Claude Code, Claude Desktop, Cursor, ChatGPT with terminal, etc.) and it will install and configure Open Brain automatically.

---

## The Prompt

```
I want to set up Open Brain — a persistent semantic memory system for AI tools. 
Clone https://github.com/srnichols/OpenBrain.git (or use the existing repo if already cloned).

Follow these steps exactly:

1. **Check prerequisites**: Verify Docker and Docker Compose are installed and the Docker daemon is running. Check for Node.js (needed for mcp-remote bridge). Check for Ollama if I want local embeddings.

2. **Ask me these questions** (wait for my answers before proceeding):
   - Which embedding provider? (ollama = free/local, openrouter = cloud/paid, azure-openai = Azure)
   - If openrouter: What's your API key?
   - If azure-openai: What's your endpoint, key, and deployment names?
   - If ollama: Is Ollama running locally? (Pull nomic-embed-text and llama3.2 if yes)
   - Which AI client should I configure? (VS Code Copilot / Claude Desktop / Claude Code / Skip)

3. **Generate .env file** from .env.example:
   - Generate a secure MCP_ACCESS_KEY using: openssl rand -hex 32
   - Generate a random DB_PASSWORD
   - Set DB_HOST=postgres (for Docker networking)
   - Set the embedder settings based on my answers
   - Set OLLAMA_ENDPOINT=http://host.docker.internal:11434 if using Ollama

4. **Start the stack**: Run `docker compose up -d --build`

5. **Wait and verify health**:
   - Poll http://localhost:8000/health until it returns {"status":"healthy"}
   - Check http://localhost:8080/health for the MCP server
   - Show me the health responses

6. **Configure my AI client** based on my choice:
   - **VS Code Copilot**: Add to .vscode/settings.json:
     {"mcp":{"servers":{"openbrain":{"type":"sse","url":"http://localhost:8080/sse?key=<MCP_KEY>"}}}}
   - **Claude Desktop**: Add to claude_desktop_config.json:
     {"mcpServers":{"openbrain":{"command":"npx","args":["-y","mcp-remote","http://localhost:8080/sse?key=<MCP_KEY>"]}}}
   - **Claude Code**: Add to ~/.claude/settings.json:
     {"mcpServers":{"openbrain":{"type":"sse","url":"http://localhost:8080/sse?key=<MCP_KEY>"}}}

7. **Verify it works**: Use the thought_stats MCP tool to confirm the connection is live.

8. **Show me a summary** of what was installed, the MCP key (first 16 chars), and next steps.

If anything fails, show me the error and suggest a fix. Don't skip steps.
```
