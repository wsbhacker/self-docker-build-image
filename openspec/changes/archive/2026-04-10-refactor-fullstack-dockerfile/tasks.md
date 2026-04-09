## 1. Restructure Root Phase

- [x] 1.1 Remove root's Oh My Zsh installation (lines 105-111)
- [x] 1.2 Add sudo package to apt-get
- [x] 1.3 Move neo user creation after apt-get
- [x] 1.4 Add neo sudoers configuration with NOPASSWD

## 2. Restructure Neo Phase

- [x] 2.1 Add USER neo directive after user creation
- [x] 2.2 Create neo directory structure (~/.local/bin, ~/.local/share, ~/opt, ~/work)
- [x] 2.3 Move Oh My Zsh installation to neo phase
- [x] 2.4 Move Maven installation to ~/opt/maven
- [x] 2.5 Move Node.js installation to ~/.local/node
- [x] 2.6 Move Neovim installation to ~/opt/nvim
- [x] 2.7 Move chezmoi installation to ~/.local/bin
- [x] 2.8 Move uv installation to ~/.local/bin
- [x] 2.9 Keep Claude Code installation (already neo)

## 3. Configure Environment

- [x] 3.1 Update PATH ENV to neo's tool locations
- [x] 3.2 Update SHELL ENV to /bin/zsh
- [x] 3.3 Set WORKDIR to ~/work

## 4. Verify and Clean Up

- [x] 4.1 Remove duplicate/redundant code blocks
- [x] 4.2 Verify all ARG declarations are preserved
- [x] 4.3 Verify all ENV declarations are correct
- [x] 4.4 Ensure final CMD is preserved