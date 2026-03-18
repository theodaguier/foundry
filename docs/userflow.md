# Foundry — User Flows

## 1. Current Flow (as-is)

```mermaid
flowchart TD
    LAUNCH([App Launch])
    SETUP_CHECK{Setup OK?}
    SETUP[SetupView\nsheet modal]
    LIBRARY[PluginLibraryView\nroot]
    EMPTY{Plugins\nexist?}
    PROMPT[PromptView\nDescribe plugin]
    OPTS[QuickOptionsView\nFormat · Channels · Presets]
    GEN[GenerationProgressView\n5 steps · timer]
    BUILD_OK{Build\nsuccess?}
    BUILD_RETRY{Attempt\n≤ 3?}
    ERROR[ErrorView]
    RESULT[ResultView\nsuccess screen]
    DETAIL[PluginDetailView\nsheet modal]
    REFINE[RefineView\ndescribe change]
    REFINE_PROG[RefineProgressView]

    LAUNCH --> SETUP_CHECK
    SETUP_CHECK -->|missing deps| SETUP
    SETUP -->|all ready| LIBRARY
    SETUP_CHECK -->|ok| LIBRARY

    LIBRARY --> EMPTY
    EMPTY -->|no plugins| PROMPT
    EMPTY -->|has plugins| DETAIL
    LIBRARY -->|toolbar +| PROMPT

    PROMPT -->|Continue| OPTS
    OPTS -->|Generate or Skip| GEN

    GEN --> BUILD_OK
    BUILD_OK -->|yes| RESULT
    BUILD_OK -->|no| BUILD_RETRY
    BUILD_RETRY -->|retry| GEN
    BUILD_RETRY -->|3 failures| ERROR

    ERROR -->|back| LIBRARY
    GEN -->|Cancel| LIBRARY

    RESULT -->|Done / Back| LIBRARY
    RESULT -->|Refine| REFINE

    DETAIL -->|Regenerate| OPTS
    DETAIL -->|Delete / Rename / Finder| LIBRARY

    REFINE -->|Apply| REFINE_PROG
    REFINE_PROG -->|success| RESULT
    REFINE_PROG -->|fail| ERROR
```

---

## 2. Improved Flow — Simple & Minimal (auth-ready)

**Principes directeurs :**
- Auth comme gate d'entrée unique (futur) — isolée du reste du flow
- Setup intégré inline au premier lancement post-auth (pas de sheet modale)
- Options de génération condensées dans PromptView (expandable, pas un écran séparé)
- Actions sur les plugins via menu contextuel direct (pas de sheet detail)
- Refine accessible depuis la library sans étape intermédiaire
- Error recovery inline dans la vue de progression

```mermaid
flowchart TD
    LAUNCH([App Launch])

    subgraph AUTH ["🔐 Auth layer — future"]
        AUTH_CHECK{Session\nvalide?}
        LOGIN[LoginView\nemail + password]
        SIGNUP[SignupView]
        AUTH_OK([Authenticated])
        LOGIN -->|no account| SIGNUP
        SIGNUP -->|created| AUTH_OK
        LOGIN -->|success| AUTH_OK
    end

    ONBOARD{First\nlaunch?}
    SETUP_INLINE[Inline setup banner\nin library]
    LIBRARY[PluginLibraryView\nroot]
    PROMPT[PromptView\n+ options collapsibles]
    GEN[GenerationView\nprogression + timer]
    BUILD_OK{Build OK?}
    RETRY[Retry inline\n≤ 3 attempts]
    ERROR_INLINE[Error state inline\n+ message + retry]
    RESULT[ResultView]
    REFINE[RefineView]
    REFINE_PROG[RefineProgressView]
    SETTINGS[SettingsView\n+ account / logout]

    LAUNCH --> AUTH_CHECK
    AUTH_CHECK -->|no session| LOGIN
    AUTH_CHECK -->|valid session| ONBOARD
    AUTH_OK --> ONBOARD

    ONBOARD -->|first run| SETUP_INLINE
    ONBOARD -->|returning| LIBRARY
    SETUP_INLINE -->|dismissed| LIBRARY

    LIBRARY -->|+ New plugin| PROMPT
    LIBRARY -->|Right-click card| CTX[Context menu\nRefine · Rename · Delete · Finder]
    LIBRARY -->|Settings icon| SETTINGS
    SETTINGS -->|Logout| LOGIN

    CTX -->|Refine| REFINE
    CTX -->|Regenerate| PROMPT

    PROMPT -->|Generate\n↳ options inline| GEN

    GEN --> BUILD_OK
    BUILD_OK -->|yes| RESULT
    BUILD_OK -->|no| RETRY
    RETRY -->|3× failed| ERROR_INLINE
    ERROR_INLINE -->|Retry| GEN
    ERROR_INLINE -->|Back| LIBRARY
    GEN -->|Cancel| LIBRARY

    RESULT -->|Done| LIBRARY
    RESULT -->|Refine| REFINE

    REFINE -->|Apply| REFINE_PROG
    REFINE_PROG -->|success| RESULT
    REFINE_PROG -->|fail| ERROR_INLINE
```

---

## Delta résumé

| Aspect | Actuel | Amélioré |
|--------|--------|----------|
| Auth | ❌ absente | ✅ gate d'entrée isolée (future) |
| Setup | Sheet modale | Banner inline dismissable |
| Options génération | Écran séparé (QuickOptionsView) | Section collapsible dans PromptView |
| Actions plugin | Sheet detail → actions | Menu contextuel direct |
| Error recovery | Vue séparée (ErrorView) | État inline dans GenerationView |
| Refine depuis library | Via detail sheet | Via context menu direct |
| Logout / account | ❌ absent | ✅ via Settings |
| Nombre d'écrans | 9 vues | 6 vues core + 2 auth (future) |
