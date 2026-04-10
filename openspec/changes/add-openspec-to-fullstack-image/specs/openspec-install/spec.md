## ADDED Requirements

### Requirement: OpenSpec version is configurable

The Dockerfile SHALL accept an `OPENSPEC_VERSION` build argument with a default value of `1.2.0`.

#### Scenario: Default version installation
- **WHEN** building the image without specifying `OPENSPEC_VERSION`
- **THEN** OpenSpec version `1.2.0` is installed

#### Scenario: Custom version installation
- **WHEN** building the image with `--build-arg OPENSPEC_VERSION=1.1.0`
- **THEN** OpenSpec version `1.1.0` is installed

### Requirement: OpenSpec command is available

The `openspec` command SHALL be available in the PATH after installation.

#### Scenario: Command is executable
- **WHEN** running `openspec --version` in the container
- **THEN** the command outputs the installed version number

### Requirement: OpenSpec is installed via npm

OpenSpec SHALL be installed using npm global install from the Node.js installation in `~/.local/node`.

#### Scenario: npm installation succeeds
- **WHEN** the Node.js installation step completes successfully
- **THEN** `npm install -g @fission-ai/openspec@${OPENSPEC_VERSION}` executes without error