## ADDED Requirements

### Requirement: Neo user creation with sudo

The system SHALL create a neo user with configurable UID/GID and NOPASSWD sudo permission.

#### Scenario: Neo user created with correct UID/GID
- **WHEN** building the image with USER_UID=1000 and USER_GID=1000
- **THEN** neo user exists with UID 1000 and GID 1000

#### Scenario: Neo has NOPASSWD sudo
- **WHEN** neo user executes `sudo <command>`
- **THEN** the command executes without password prompt

### Requirement: User-space directory structure

The system SHALL create a standard directory structure under neo's home for tool installation.

#### Scenario: Required directories exist
- **WHEN** neo user is created
- **THEN** the following directories exist with neo ownership:
  - `~/.local/bin` (for binaries)
  - `~/.local/share` (for tool data)
  - `~/opt` (for larger tools like Maven, Neovim)
  - `~/work` (working directory)

### Requirement: PATH configuration for neo tools

The system SHALL configure PATH to include all neo-installed tool locations.

#### Scenario: All tool paths accessible
- **WHEN** neo user logs in
- **THEN** `echo $PATH` includes:
  - `~/.local/bin`
  - `~/opt/maven/bin`
  - `~/opt/nvim/bin`

#### Scenario: Tools are executable without full path
- **WHEN** neo user runs `mvn --version`, `node --version`, `nvim --version`
- **THEN** each command executes successfully

### Requirement: User tools installed by neo

The system SHALL install all user-space tools under neo user context.

#### Scenario: Tools owned by neo
- **WHEN** listing tool directories
- **THEN** all files under `~/.local` and `~/opt` are owned by neo:neo

#### Scenario: Oh My Zsh installed for neo only
- **WHEN** neo user logs in with zsh
- **THEN** Oh My Zsh is active with plugins (zsh-autosuggestions, zsh-syntax-highlighting)

#### Scenario: Claude Code installed for neo
- **WHEN** neo user runs `claude --version`
- **THEN** command executes successfully