# Changelog

All notable changes to Foundry are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/).

## [1.6.0](https://github.com/theodaguier/foundry/compare/v1.5.0...v1.6.0) (2026-03-21)


### Features

* add initial SwiftUI app with generation pipeline ([9cf083d](https://github.com/theodaguier/foundry/commit/9cf083deb14c43c202a2f2e4492640201c7450e0))
* add refine mode to iterate on generated plugins ([fc170a7](https://github.com/theodaguier/foundry/commit/fc170a7dfd49ffa4adc715ff2f209af795b54729))
* add Supabase auth with email+OTP and profile system ([#36](https://github.com/theodaguier/foundry/issues/36)) ([9137d1d](https://github.com/theodaguier/foundry/commit/9137d1dbad1519b28738e92bf44cbd433b1b5229))
* background builds with build queue page ([#35](https://github.com/theodaguier/foundry/issues/35)) ([e437459](https://github.com/theodaguier/foundry/commit/e437459b48dc32dd3c9d318b4f428e2976bdc3af))
* enrich instrument generation with synthesis knowledge and improve terminal observability ([#29](https://github.com/theodaguier/foundry/issues/29)) ([0cfa77a](https://github.com/theodaguier/foundry/commit/0cfa77aac205ca1084bd165330769e8e8c15c404))
* extract reusable design system and component library ([#23](https://github.com/theodaguier/foundry/issues/23)) ([03e441b](https://github.com/theodaguier/foundry/commit/03e441bcbfb5a6e80d717b45878feecc91f50eb3))
* **foundry:** add local plugin logo regeneration ([2ab1dc1](https://github.com/theodaguier/foundry/commit/2ab1dc1ce319564efb55f637a4ec28c754d7f1fd))
* **pipeline:** agent-expert architecture, closes [#17](https://github.com/theodaguier/foundry/issues/17) ([#18](https://github.com/theodaguier/foundry/issues/18)) ([41d2a5e](https://github.com/theodaguier/foundry/commit/41d2a5e4bb5914244ed6f270f8708d7e8a8c1683))
* rework generation pipeline — JUCE knowledge kit, event-driven flow, audit pass, no templates ([#27](https://github.com/theodaguier/foundry/issues/27)) ([#31](https://github.com/theodaguier/foundry/issues/31)) ([1cf089f](https://github.com/theodaguier/foundry/commit/1cf089f40f31f6a5fb375d84f2d3281b8b947218))
* **ui:** redesign UI following Apple HIG and App Store patterns ([#2](https://github.com/theodaguier/foundry/issues/2)) ([03931f6](https://github.com/theodaguier/foundry/commit/03931f6a21ffda0951d3d81ce82dec74a86bee08))


### Bug Fixes

* **build:** build universal binaries so Ableton's x86_64 scanner can load plugins ([4e0df61](https://github.com/theodaguier/foundry/commit/4e0df613a45b2c7de3f43a925b889c9c2868b59d))
* **ci:** improve release-please workflow with config files and auto-merge ([#15](https://github.com/theodaguier/foundry/issues/15)) ([a13e91b](https://github.com/theodaguier/foundry/commit/a13e91b9ca7402985e8dd340775c928fbe93c37f))
* eliminate build failures with viable stubs and expert prompt rewrite ([#25](https://github.com/theodaguier/foundry/issues/25)) ([3baf068](https://github.com/theodaguier/foundry/commit/3baf068f58762aee7f6d58a2914370e0a921bb24))
* **foundry:** harden generation and plugin install ([81fd5dc](https://github.com/theodaguier/foundry/commit/81fd5dc576f233048b7e18ecf6d8e3ed77437b59))
* move checkout step before release-please action ([#20](https://github.com/theodaguier/foundry/issues/20)) ([67d4898](https://github.com/theodaguier/foundry/commit/67d48985d942f9ba5258972986d6257d8ff0351c))
* **pipeline:** clean up temp build directories, closes [#9](https://github.com/theodaguier/foundry/issues/9) ([#13](https://github.com/theodaguier/foundry/issues/13)) ([6d48075](https://github.com/theodaguier/foundry/commit/6d48075ae53f92c6e3537ddbfb4b687ff9cd699e))
* **pipeline:** split build timeout into configure (60s) and build (120s), closes [#10](https://github.com/theodaguier/foundry/issues/10) ([#14](https://github.com/theodaguier/foundry/issues/14)) ([d0d7461](https://github.com/theodaguier/foundry/commit/d0d7461aa8eb1d063af9d6e5b75cf80754b29dd3))
* prevent auto* and method redefinition errors in generated plugins ([#21](https://github.com/theodaguier/foundry/issues/21)) ([8164e3d](https://github.com/theodaguier/foundry/commit/8164e3d4282b50d78c5eb3f13aa3a1a6a83aa114))
* remove AI slop design, use native macOS patterns and system-adaptive colors ([#33](https://github.com/theodaguier/foundry/issues/33)) ([d2e0f70](https://github.com/theodaguier/foundry/commit/d2e0f7067131c955230887043cea64a75ba2be49))


### Reverts

* restore GenerationPipeline.swift to pre-refactor state ([f8acc8d](https://github.com/theodaguier/foundry/commit/f8acc8d44a2f76aba3de5be68b12e4134a266d9b))

## [1.5.0](https://github.com/theodaguier/foundry/compare/v1.4.0...v1.5.0) (2026-03-21)


### Features

* background builds with build queue page ([#35](https://github.com/theodaguier/foundry/issues/35)) ([e437459](https://github.com/theodaguier/foundry/commit/e437459b48dc32dd3c9d318b4f428e2976bdc3af))


### Bug Fixes

* remove AI slop design, use native macOS patterns and system-adaptive colors ([#33](https://github.com/theodaguier/foundry/issues/33)) ([d2e0f70](https://github.com/theodaguier/foundry/commit/d2e0f7067131c955230887043cea64a75ba2be49))

## [1.4.0](https://github.com/theodaguier/foundry/compare/v1.3.0...v1.4.0) (2026-03-21)


### Features

* rework generation pipeline — JUCE knowledge kit, event-driven flow, audit pass, no templates ([#27](https://github.com/theodaguier/foundry/issues/27)) ([#31](https://github.com/theodaguier/foundry/issues/31)) ([1cf089f](https://github.com/theodaguier/foundry/commit/1cf089f40f31f6a5fb375d84f2d3281b8b947218))

## [1.3.0](https://github.com/theodaguier/foundry/compare/v1.2.1...v1.3.0) (2026-03-21)


### Features

* enrich instrument generation with synthesis knowledge and improve terminal observability ([#29](https://github.com/theodaguier/foundry/issues/29)) ([0cfa77a](https://github.com/theodaguier/foundry/commit/0cfa77aac205ca1084bd165330769e8e8c15c404))

## [1.2.1](https://github.com/theodaguier/foundry/compare/v1.2.0...v1.2.1) (2026-03-20)


### Bug Fixes

* eliminate build failures with viable stubs and expert prompt rewrite ([#25](https://github.com/theodaguier/foundry/issues/25)) ([3baf068](https://github.com/theodaguier/foundry/commit/3baf068f58762aee7f6d58a2914370e0a921bb24))

## [1.2.0](https://github.com/theodaguier/foundry/compare/v1.1.1...v1.2.0) (2026-03-20)


### Features

* extract reusable design system and component library ([#23](https://github.com/theodaguier/foundry/issues/23)) ([03e441b](https://github.com/theodaguier/foundry/commit/03e441bcbfb5a6e80d717b45878feecc91f50eb3))

## [1.1.1](https://github.com/theodaguier/foundry/compare/v1.1.0...v1.1.1) (2026-03-20)


### Bug Fixes

* prevent auto* and method redefinition errors in generated plugins ([#21](https://github.com/theodaguier/foundry/issues/21)) ([8164e3d](https://github.com/theodaguier/foundry/commit/8164e3d4282b50d78c5eb3f13aa3a1a6a83aa114))

## [1.1.0](https://github.com/theodaguier/foundry/compare/v1.0.1...v1.1.0) (2026-03-18)


### Features

* **pipeline:** agent-expert architecture, closes [#17](https://github.com/theodaguier/foundry/issues/17) ([#18](https://github.com/theodaguier/foundry/issues/18)) ([41d2a5e](https://github.com/theodaguier/foundry/commit/41d2a5e4bb5914244ed6f270f8708d7e8a8c1683))


### Bug Fixes

* move checkout step before release-please action ([#20](https://github.com/theodaguier/foundry/issues/20)) ([67d4898](https://github.com/theodaguier/foundry/commit/67d48985d942f9ba5258972986d6257d8ff0351c))

## [1.0.1](https://github.com/theodaguier/foundry/compare/v1.0.0...v1.0.1) (2026-03-18)


### Bug Fixes

* **ci:** improve release-please workflow with config files and auto-merge ([#15](https://github.com/theodaguier/foundry/issues/15)) ([a13e91b](https://github.com/theodaguier/foundry/commit/a13e91b9ca7402985e8dd340775c928fbe93c37f))
* **pipeline:** clean up temp build directories, closes [#9](https://github.com/theodaguier/foundry/issues/9) ([#13](https://github.com/theodaguier/foundry/issues/13)) ([6d48075](https://github.com/theodaguier/foundry/commit/6d48075ae53f92c6e3537ddbfb4b687ff9cd699e))
* **pipeline:** split build timeout into configure (60s) and build (120s), closes [#10](https://github.com/theodaguier/foundry/issues/10) ([#14](https://github.com/theodaguier/foundry/issues/14)) ([d0d7461](https://github.com/theodaguier/foundry/commit/d0d7461aa8eb1d063af9d6e5b75cf80754b29dd3))


### Reverts

* restore GenerationPipeline.swift to pre-refactor state ([f8acc8d](https://github.com/theodaguier/foundry/commit/f8acc8d44a2f76aba3de5be68b12e4134a266d9b))

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
