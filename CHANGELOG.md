# Changelog

All notable changes to Foundry are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/).

## [1.21.0](https://github.com/theodaguier/foundry/compare/v1.20.0...v1.21.0) (2026-03-26)


### Features

* **foundry-kit:** beatmaker — add macro controls, concrete synth sound recipes per archetype ([66497e1](https://github.com/theodaguier/foundry/commit/66497e1465797886f8651f47b043884a14c514ce))
* **foundry-kit:** juce-expert — add oversampling pattern, clarify APVTS layout, fix lambda capture note ([93a7a78](https://github.com/theodaguier/foundry/commit/93a7a78aba5ede043eff6ca4a79f45dcffe54c11))

## [1.20.0](https://github.com/theodaguier/foundry/compare/v1.19.0...v1.20.0) (2026-03-26)


### Features

* **foundry-kit:** expand sound-engineer skill — full synthesis coverage (FM, wavetable, granular), utilities, instruments, complete DSP patterns ([ba4336c](https://github.com/theodaguier/foundry/commit/ba4336cc924847fa2bdfad029d96a3d85d4b9662))
* **foundry-kit:** rework art-director skill — visual identity over prescriptive palette, FoundryLookAndFeel as foundation not cage ([daa48c2](https://github.com/theodaguier/foundry/commit/daa48c225a7bb5899c3c72fb0be057b775269e42))

## [1.19.0](https://github.com/theodaguier/foundry/compare/v1.18.5...v1.19.0) (2026-03-26)


### Features

* **foundry-kit:** add art-director skill ([3fb5366](https://github.com/theodaguier/foundry/commit/3fb53663a2b9ca79650e18abce017bf5d47f40b0))
* **foundry-kit:** add beatmaker skill ([f5400eb](https://github.com/theodaguier/foundry/commit/f5400eb887d908e5c8899782a43fb0128c42c594))
* **foundry-kit:** add juce-expert skill ([f9d17e2](https://github.com/theodaguier/foundry/commit/f9d17e20a6bdf8411f5c69b060f9eb2a4a1cf228))
* **foundry-kit:** add master skill ([8ad833c](https://github.com/theodaguier/foundry/commit/8ad833c42fe1feba21de99876b8e99ab53c24b7b))
* **foundry-kit:** add sound-engineer skill ([ab1a66d](https://github.com/theodaguier/foundry/commit/ab1a66df4afe1c1e0108cbb055a6cedd9f32fd6c))

## [1.18.5](https://github.com/theodaguier/foundry/compare/v1.18.4...v1.18.5) (2026-03-25)


### Bug Fixes

* tolerate missing mac signing identity ([8ecc90d](https://github.com/theodaguier/foundry/commit/8ecc90db9e0cc0dad716f9d84eb125fcaf6bc70f))

## [1.18.4](https://github.com/theodaguier/foundry/compare/v1.18.3...v1.18.4) (2026-03-25)


### Bug Fixes

* fall back to unsigned desktop artifacts ([e7196a6](https://github.com/theodaguier/foundry/commit/e7196a600a3de866b6f7b1eae6cd5d7b2416dc60))

## [1.18.3](https://github.com/theodaguier/foundry/compare/v1.18.2...v1.18.3) (2026-03-25)


### Bug Fixes

* normalize desktop certificate secrets ([9aa641b](https://github.com/theodaguier/foundry/commit/9aa641b8922e8ead42d282678771a2434f22b621))

## [1.18.2](https://github.com/theodaguier/foundry/compare/v1.18.1...v1.18.2) (2026-03-25)


### Bug Fixes

* allow manual desktop release reruns ([4f6362d](https://github.com/theodaguier/foundry/commit/4f6362d5006d9189605e58f7801fed733d19ea77))

## [1.18.1](https://github.com/theodaguier/foundry/compare/v1.18.0...v1.18.1) (2026-03-25)


### Bug Fixes

* harden desktop certificate imports ([b735386](https://github.com/theodaguier/foundry/commit/b7353860e0c2a23edfb7126c65029d296d6daf94))

## [1.18.0](https://github.com/theodaguier/foundry/compare/v1.17.0...v1.18.0) (2026-03-25)


### Features

* trigger desktop release flow ([61372cc](https://github.com/theodaguier/foundry/commit/61372ccf97b4a1ed4f59cf0393964c1fe11fb1a7))

## [1.17.0](https://github.com/theodaguier/foundry/compare/v1.16.0...v1.17.0) (2026-03-25)


### Features

* redesign navigation with sidebar layout, sync app version with release-please ([#66](https://github.com/theodaguier/foundry/issues/66)) ([3f0d878](https://github.com/theodaguier/foundry/commit/3f0d8783106688ec1d8917a5a98f0e279c9e85a1))

## [1.16.0](https://github.com/theodaguier/foundry/compare/v1.15.0...v1.16.0) (2026-03-24)


### Features

* rewrite settings page with proper shadcn components and configurable install paths ([#63](https://github.com/theodaguier/foundry/issues/63)) ([a4b7214](https://github.com/theodaguier/foundry/commit/a4b7214ec9df6cf6e5df1f92ae5f470e77c7c139))

## [1.15.0](https://github.com/theodaguier/foundry/compare/v1.14.0...v1.15.0) (2026-03-24)


### Features

* add Codex CLI support as a generation backend ([#61](https://github.com/theodaguier/foundry/issues/61)) ([2a5271a](https://github.com/theodaguier/foundry/commit/2a5271a770a8b5d615d26525e41362df1770844a))

## [1.14.0](https://github.com/theodaguier/foundry/compare/v1.13.0...v1.14.0) (2026-03-24)


### Features

* plug-and-play onboarding with auto-install ([#59](https://github.com/theodaguier/foundry/issues/59)) ([7f18e5c](https://github.com/theodaguier/foundry/commit/7f18e5c9b95e2c40d85081c211e64d17c9db67a4))

## [1.13.0](https://github.com/theodaguier/foundry/compare/v1.12.0...v1.13.0) (2026-03-23)


### Features

* env-based credentials setup with conductor.json ([6c9da7d](https://github.com/theodaguier/foundry/commit/6c9da7d522dbf07021e33e24a3ce1cdbcdaec696))

## [1.12.0](https://github.com/theodaguier/foundry/compare/v1.11.0...v1.12.0) (2026-03-23)


### Features

* harden tauri generation pipeline ([#56](https://github.com/theodaguier/foundry/issues/56)) ([44dc5c8](https://github.com/theodaguier/foundry/commit/44dc5c81d8e5c296ff6c80106ce320e2d9368f88))


### Bug Fixes

* restore lost files and remove node_modules/dist from repo ([ebb3e0a](https://github.com/theodaguier/foundry/commit/ebb3e0aad1612fb44ab56ef4345ac41547cb9ee0))

## [1.11.0](https://github.com/theodaguier/foundry/compare/v1.10.0...v1.11.0) (2026-03-22)


### Features

* distinct refine flow with capped build loop, generation_type telemetry, and UI polish ([#55](https://github.com/theodaguier/foundry/issues/55)) ([7a13f6b](https://github.com/theodaguier/foundry/commit/7a13f6b410face7685927322d4d264c3cd4d8ab0))
* dynamic model catalog from provider APIs + CodexService fix ([#53](https://github.com/theodaguier/foundry/issues/53)) ([66df2d4](https://github.com/theodaguier/foundry/commit/66df2d4c8da0ee231ab9616339b83a4398878850)), closes [#48](https://github.com/theodaguier/foundry/issues/48)

## [1.10.0](https://github.com/theodaguier/foundry/compare/v1.9.0...v1.10.0) (2026-03-22)


### Features

* generation telemetry with local + Supabase storage ([#50](https://github.com/theodaguier/foundry/issues/50)) ([7c5e1a6](https://github.com/theodaguier/foundry/commit/7c5e1a6c91ad18b7edcad0550b65e72285ee4ca6))

## [1.9.0](https://github.com/theodaguier/foundry/compare/v1.8.0...v1.9.0) (2026-03-22)


### Features

* educational juce-kit and dedicated refine prompt ([#49](https://github.com/theodaguier/foundry/issues/49)) ([88c520e](https://github.com/theodaguier/foundry/commit/88c520ea4748f1bb72d650ff7812b9590021f7f0))
* plugin versioning, AI-generated names, unified build screen, and refine flow ([#46](https://github.com/theodaguier/foundry/issues/46)) ([b798f48](https://github.com/theodaguier/foundry/commit/b798f48f1d9c12f258214e85aa7ce7fc8ee84920)), closes [#41](https://github.com/theodaguier/foundry/issues/41)

## [1.8.0](https://github.com/theodaguier/foundry/compare/v1.7.0...v1.8.0) (2026-03-21)


### Features

* multi-agent support — switch between Claude Code and Codex at generation time ([#43](https://github.com/theodaguier/foundry/issues/43)) ([afbdb32](https://github.com/theodaguier/foundry/commit/afbdb32e339c29716a9426a45fe98dfbcae86f03)), closes [#38](https://github.com/theodaguier/foundry/issues/38)

## [1.7.0](https://github.com/theodaguier/foundry/compare/v1.6.0...v1.7.0) (2026-03-21)


### Features

* add Foundry logo as app icon and replace text branding with logo image ([#39](https://github.com/theodaguier/foundry/issues/39)) ([0c32cb5](https://github.com/theodaguier/foundry/commit/0c32cb5f74b091e28fdd016b93317c3862898aa9))

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
