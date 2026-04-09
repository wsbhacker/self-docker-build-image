## Why

The current `fullstack.Dockerfile` creates the neo user at the end of the build process, causing several issues:
- User tools (uv, Claude Code) are installed to `/root/.local/bin`, inaccessible to neo
- Oh My Zsh is installed twice (for root and neo), wasting image layers
- neo user has no sudo permission, limiting flexibility for system operations
- Tools are scattered across system directories with inconsistent ownership

This refactor establishes neo as the primary user early, with all user-space tools installed by neo itself, and sudo as a backup option.

## What Changes

- Move neo user creation immediately after apt-get (system packages installation)
- Add NOPASSWD sudo permission for neo user
- Remove root's Oh My Zsh installation (wasted layer)
- Relocate all user tools to neo's home directory:
  - Maven: `/opt` → `~/opt/maven`
  - Node.js: `/usr/local` → `~/.local/node`
  - Neovim: `/opt` → `~/opt/nvim`
  - chezmoi: `/usr/local/bin` → `~/.local/bin`
  - uv: `/root/.local/bin` → `~/.local/bin`
  - Claude Code: (already neo) `~/.local/bin`
- Configure PATH via ENV to include all neo-installed tool locations
- All tools installed by neo user after `USER neo` directive

## Capabilities

### New Capabilities

- `neo-user-setup`: Defines neo user creation, sudo configuration, and directory structure for user-space tools

### Modified Capabilities

(None - this is a structural refactor, no behavioral changes to existing capabilities)

## Impact

- **Affected Files**: `fullstack-image/fullstack.Dockerfile`
- **PATH Changes**: From `/root/.local/bin:/opt/maven/bin:/opt/nvim-linux-x86_64/bin:${PATH}` to `~/.local/bin:~/opt/maven/bin:~/opt/nvim/bin:${PATH}`
- **Tool Locations**: All user tools moved to neo's home directory
- **Permissions**: neo gains NOPASSWD sudo access