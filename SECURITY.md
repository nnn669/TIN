# Security Policy

## Reporting a Vulnerability

Please report security vulnerabilities privately via GitHub Security Advisories.

## Sensitive Areas

- Token, secret, and variable management
- Android signing and release packaging
- MCP tool results and SSE transports
- Network requests and redirect handling
- Logging and credential redaction

## Safe Configuration

- Use least-privilege GitHub tokens
- Keep signing keys outside the repository
- Do not paste secrets into prompts unless the model/provider is trusted
- Keep App Control disabled unless the assistant is trusted

## Public Repository Hygiene

The repository intentionally ignores local signing files, build output, APK/AAB files, local SDK paths, and app-specific secret files.
