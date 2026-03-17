# Changelog

All notable changes to Foundry are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/).

## 1.0.0 (2026-03-17)


### Features

* add initial SwiftUI app with generation pipeline ([9cf083d](https://github.com/theodaguier/foundry/commit/9cf083deb14c43c202a2f2e4492640201c7450e0))
* add refine mode to iterate on generated plugins ([fc170a7](https://github.com/theodaguier/foundry/commit/fc170a7dfd49ffa4adc715ff2f209af795b54729))
* **foundry:** add local plugin logo regeneration ([2ab1dc1](https://github.com/theodaguier/foundry/commit/2ab1dc1ce319564efb55f637a4ec28c754d7f1fd))
* **ui:** redesign UI following Apple HIG and App Store patterns ([#2](https://github.com/theodaguier/foundry/issues/2)) ([03931f6](https://github.com/theodaguier/foundry/commit/03931f6a21ffda0951d3d81ce82dec74a86bee08))


### Bug Fixes

* **build:** build universal binaries so Ableton's x86_64 scanner can load plugins ([4e0df61](https://github.com/theodaguier/foundry/commit/4e0df613a45b2c7de3f43a925b889c9c2868b59d))
* **foundry:** harden generation and plugin install ([81fd5dc](https://github.com/theodaguier/foundry/commit/81fd5dc576f233048b7e18ecf6d8e3ed77437b59))

## [0.1.0] - 2026-03-17

### Features

- **foundry:** add local plugin logo regeneration (`2ab1dc1`)
- **ui:** redesign UI following Apple HIG and App Store patterns (`03931f6`)
- add refine mode to iterate on generated plugins (`fc170a7`)
- add initial SwiftUI app with generation pipeline (`9cf083d`)

### Bug Fixes

- **foundry:** harden generation and plugin install (`81fd5dc`)
- **build:** build universal binaries so Ableton's x86_64 scanner can load plugins (`4e0df61`)

### Refactoring

- **ui:** deduplicate shared components and improve code quality (`c063654`)

### Documentation

- add foundry logo (`47dfa64`)
- add marketing strategy document (`1f44eb5`)
- **spec:** add plugin logo regeneration design (`d37e284`)
- add CLAUDE.md with project architecture and conventions (`912fc4b`)
