# Add OpenSpec to Fullstack Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenSpec CLI tool installation to the fullstack Docker image with configurable version via ARG parameter.

**Architecture:** Follow the existing pattern where each tool has an ARG for version configuration, an ENV to propagate the value, and a dedicated RUN step for installation. OpenSpec is an npm package that will be installed globally using the existing Node.js installation.

**Tech Stack:** Dockerfile, npm, Node.js 20.x, @fission-ai/openspec package

---

## File Structure

| File | Responsibility |
|------|----------------|
| `fullstack-image/fullstack.Dockerfile` | Single file modification - add ARG, ENV, and RUN step for OpenSpec |

---

### Task 1: Add OPENSPEC_VERSION ARG Parameter

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:10-19` (ARG section)

- [ ] **Step 1: Add ARG declaration in ARG section**

Add `ARG OPENSPEC_VERSION=1.2.0` after line 17 (after `CHEZMOI_VERSION`):

```dockerfile
ARG CHEZMOI_VERSION=2.70.0
ARG OPENSPEC_VERSION=1.2.0
ARG USER_UID=1000
ARG USER_GID=1000
```

**Location:** Insert between `ARG CHEZMOI_VERSION=2.70.0` (line 17) and `ARG USER_UID=1000` (line 18)

---

### Task 2: Add OPENSPEC_VERSION ENV Variable

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:29-38` (ENV section)

- [ ] **Step 1: Add ENV declaration in ENV section**

Add `ENV OPENSPEC_VERSION=${OPENSPEC_VERSION}` after line 36 (after `CHEZMOI_VERSION`):

```dockerfile
ENV CHEZMOI_VERSION=${CHEZMOI_VERSION}
ENV OPENSPEC_VERSION=${OPENSPEC_VERSION}
ENV USER_UID=${USER_UID}
ENV USER_GID=${USER_GID}
```

**Location:** Insert between `ENV CHEZMOI_VERSION=${CHEZMOI_VERSION}` (line 36) and `ENV USER_UID=${USER_UID}` (line 37)

---

### Task 3: Add OpenSpec npm Installation Step

**Files:**
- Modify: `fullstack-image/fullstack.Dockerfile:136-140` (near Claude Code installation)

- [ ] **Step 1: Add RUN step for OpenSpec installation**

Add a new RUN step before the Claude Code installation (before line 139). Insert after the chezmoi installation section:

```dockerfile
# ==========================================
# 17. 为 neo 用户安装 OpenSpec
# ==========================================
RUN ~/.local/node/bin/npm install -g @fission-ai/openspec@${OPENSPEC_VERSION}

# ==========================================
# 18. 为 neo 用户安装 Claude Code
# ==========================================
RUN curl -fsSL https://claude.ai/install.sh | bash
```

**Location:** Insert between line 135 (end of chezmoi section) and line 136 (Claude Code comment header)

---

### Task 4: Verify Dockerfile Syntax

**Files:**
- Verify: `fullstack-image/fullstack.Dockerfile`

- [ ] **Step 1: Read modified Dockerfile to verify structure**

Run: `cat fullstack-image/fullstack.Dockerfile | head -n 45`

Expected output should show:
- Line 17-18: `ARG OPENSPEC_VERSION=1.2.0` between CHEZMOI_VERSION and USER_UID
- Line 36-37: `ENV OPENSPEC_VERSION=${OPENSPEC_VERSION}` between CHEZMOI_VERSION and USER_UID

- [ ] **Step 2: Verify installation step location**

Run: `cat fullstack-image/fullstack.Dockerfile | sed -n '135,145p'`

Expected output should show:
- OpenSpec RUN step before Claude Code installation
- Comment headers updated with correct section numbers

---

### Task 5: Update GitHub Workflow (Optional - if workflow exists)

**Files:**
- Check: `.github/workflows/build-fullstack.yml` (if exists)

- [ ] **Step 1: Check if fullstack workflow exists**

Run: `ls .github/workflows/ | grep -i fullstack`

If no workflow exists, skip this task. If workflow exists, verify no changes needed (ARG/ENV approach allows build-time customization without workflow modification).

---

### Task 6: Commit Changes

**Files:**
- Commit: `fullstack-image/fullstack.Dockerfile`

- [ ] **Step 1: Stage and commit**

```bash
git add fullstack-image/fullstack.Dockerfile
git commit -m "$(cat <<'EOF'
feat: add OpenSpec CLI installation to fullstack image

- Add OPENSPEC_VERSION ARG with default 1.2.0
- Add OPENSPEC_VERSION ENV for version propagation
- Add npm global install step for @fission-ai/openspec

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Checklist

**1. Spec coverage:**
- ✅ ARG `OPENSPEC_VERSION=1.2.0` → Task 1
- ✅ ENV `OPENSPEC_VERSION=${OPENSPEC_VERSION}` → Task 2
- ✅ npm install command → Task 3
- ✅ Version configurable → Covered by ARG/ENV pattern

**2. Placeholder scan:**
- ✅ No TBD, TODO, or "implement later" phrases
- ✅ All code steps contain actual Dockerfile content
- ✅ All file paths are exact

**3. Type consistency:**
- ✅ Variable name `OPENSPEC_VERSION` consistent across ARG, ENV, and RUN
- ✅ Version format `1.2.0` matches semantic versioning pattern used by other tools

---

## Notes

- **Testing approach:** Per project CLAUDE.md, this project does NOT perform local Docker testing. Verification relies on syntax check and CI build success.
- **Build verification:** The GitHub Actions workflow will verify the installation works during the actual build process.
- **Version upgrade path:** Users can specify different versions via `--build-arg OPENSPEC_VERSION=x.y.z` at build time.