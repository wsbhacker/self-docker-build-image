## Context

Current `fullstack.Dockerfile` structure:

```
root installs system packages
root installs all tools to system directories
root installs Oh My Zsh for root (unused)
root creates neo user
neo installs Claude Code only
```

This causes:
- uv installed to `/root/.local/bin` (neo can't access)
- Double Oh My Zsh installation (wasted layers)
- neo lacks sudo for emergency system operations

The container is single-user (neo is primary, root is only for emergencies).

## Goals / Non-Goals

**Goals:**
- Create neo user immediately after apt-get
- Install all user tools with neo user to neo's home
- Grant neo NOPASSWD sudo for flexibility
- Remove redundant root Oh My Zsh

**Non-Goals:**
- Adding new tools or capabilities
- Changing tool versions
- Supporting multiple users

## Decisions

### D1: Tool Installation Location

**Decision**: Install all tools to neo's home directories.

**Alternatives considered**:
| Option | Pros | Cons |
|--------|------|------|
| System directories (/opt, /usr/local) | Shared access | Requires root, neo can't upgrade |
| User directories (~/opt, ~/.local) | neo owns everything | Only neo can use |

**Rationale**: Container is single-user. neo having full control is more valuable than hypothetical multi-user support.

### D2: sudo Configuration

**Decision**: NOPASSWD sudo for neo.

**Alternatives considered**:
| Option | Pros | Cons |
|--------|------|------|
| Password sudo | More secure | Interactive inconvenience |
| NOPASSWD sudo | Convenient | Slightly less secure |

**Rationale**: Development container context. Convenience outweighs marginal security gain from password.

### D3: Node.js Installation Method

**Decision**: Direct installation to `~/.local/node` (not nvm).

**Alternatives considered**:
| Option | Pros | Cons |
|--------|------|------|
| nvm/fnm | Version switching | Extra complexity, slower |
| Direct install | Simple, fast | Fixed version |

**Rationale**: ARG `NODE_VERSION` already provides version control at build time. nvm adds unnecessary complexity.

### D4: PATH Configuration Method

**Decision**: ENV directive only (no .zshrc export).

**Rationale**: ENV applies to all processes immediately. Writing to .zshrc is redundant and only affects shell sessions.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| PATH must be configured correctly for neo | Test with `which <tool>` after build |
| Tool upgrades require neo permissions (not sudo) | neo can upgrade directly - this is desired |
| User switching to root loses access to neo's tools | Root is emergency use only; acceptable limitation |
| wget/curl for versioned downloads may fail | Use ARG fallbacks, test with specific versions |