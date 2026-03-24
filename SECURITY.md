# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Open Brain, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

1. **Email**: Contact [Scott Nichols](https://www.linkedin.com/in/srnichols/) via LinkedIn
2. **GitHub**: Use [GitHub Security Advisories](https://github.com/srnichols/OpenBrain/security/advisories/new) to report privately

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Assessment**: Within 1 week
- **Fix**: Depending on severity, typically within 2 weeks for critical issues

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | ✅        |
| < 1.0   | ❌        |

## Security Best Practices for Deployment

- **Rotate `MCP_ACCESS_KEY` regularly** — Generate with `openssl rand -hex 32`
- **Never expose port 8080 to the public internet without TLS** — Use a reverse proxy (nginx, Tailscale Funnel, etc.)
- **Use Kubernetes Secrets or a secret manager** for `DB_PASSWORD` and `MCP_ACCESS_KEY`
- **Keep dependencies updated** — Dependabot is configured on this repo
- **Run as non-root** in Docker (default since v1.1)
- **Network isolation** — PostgreSQL should not be reachable from the public internet
