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
- Auth comme gate d'entrée unique (futur) — vérification Keychain silencieuse
- Setup inline avec deux états : avertissement doux (deps OK) vs bloquant (deps manquantes)
- Welcome screen au premier lancement post-signup
- Options de génération condensées dans PromptView (expandable)
- Inspector panel latéral pour le détail plugin (non intrusif)
- Build log accessible en cas d'erreur
- Error recovery inline dans GenerationView
- AccountView dédiée (plan, usage, danger zone)

```mermaid
flowchart TD
    LAUNCH([App Launch])

    subgraph AUTH ["🔐 Auth layer — future"]
        KEYCHAIN{Keychain\ntoken valide?}
        LOGIN[LoginView\nemail + password]
        FORGOT[ForgotPasswordView\nreset par email]
        SIGNUP[SignupView]
        AUTH_OK([Authenticated])
        KEYCHAIN -->|token absent\nou expiré| LOGIN
        LOGIN -->|forgot password| FORGOT
        FORGOT -->|email envoyé| LOGIN
        LOGIN -->|no account| SIGNUP
        SIGNUP -->|account created| WELCOME
        LOGIN -->|success| KEYCHAIN_STORE[Store token\nin Keychain]
        KEYCHAIN_STORE --> ONBOARD
    end

    WELCOME[WelcomeView\nWhat is Foundry · CTA]
    ONBOARD{First\nlaunch?}
    SETUP_DEPS{Deps\nmanquantes?}
    SETUP_BLOCK[Banner bloquant\n+ bouton + désactivé]
    SETUP_WARN[Banner doux\ndismissable]
    LIBRARY[PluginLibraryView\nroot]
    INSPECTOR[Inspector panel\ninfos · formats · prompt · paths]
    PROMPT[PromptView\n+ options collapsibles]
    GEN[GenerationView\nprogression + timer]
    BUILD_OK{Build OK?}
    RETRY[Retry inline\n≤ 3 attempts]
    ERROR_INLINE[Error state inline\n+ message + retry]
    BUILD_LOG[BuildLogView\nlog de compilation]
    RESULT[ResultView]
    REFINE[RefineView]
    REFINE_PROG[RefineProgressView]
    SETTINGS[SettingsView\nCmd+,]
    ACCOUNT[AccountView\nplan · usage · danger zone]

    KEYCHAIN -->|token valide| ONBOARD
    WELCOME --> ONBOARD
    ONBOARD -->|first run| SETUP_DEPS
    ONBOARD -->|returning| SETUP_DEPS
    SETUP_DEPS -->|manquantes| SETUP_BLOCK
    SETUP_DEPS -->|toutes OK| SETUP_WARN
    SETUP_WARN -->|dismissed| LIBRARY
    SETUP_BLOCK --> LIBRARY

    LIBRARY -->|+ New plugin\n↳ bloqué si deps KO| PROMPT
    LIBRARY -->|Click card| INSPECTOR
    LIBRARY -->|Right-click card| CTX[Context menu\nRefine · Rename · Delete · Finder]
    LIBRARY -->|Settings Cmd+,| SETTINGS

    INSPECTOR -->|Refine| REFINE
    INSPECTOR -->|Regenerate| PROMPT

    CTX -->|Refine| REFINE
    CTX -->|Regenerate| PROMPT

    SETTINGS -->|Account| ACCOUNT
    ACCOUNT -->|Logout| LOGIN
    ACCOUNT -->|Delete account| LOGIN

    PROMPT -->|Generate\n↳ options inline| GEN

    GEN --> BUILD_OK
    BUILD_OK -->|yes| RESULT
    BUILD_OK -->|no| RETRY
    RETRY -->|3× failed| ERROR_INLINE
    ERROR_INLINE -->|View log| BUILD_LOG
    ERROR_INLINE -->|Retry| GEN
    ERROR_INLINE -->|Back| LIBRARY
    BUILD_LOG -->|Back| ERROR_INLINE
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
| Auth | ❌ absente | ✅ Keychain silencieux + Login/Signup/ForgotPassword |
| Welcome | ❌ absent | ✅ WelcomeView post-signup |
| Setup | Sheet modale unique | Banner doux ou bloquant selon état des deps |
| Options génération | Écran séparé (QuickOptionsView) | Section collapsible dans PromptView |
| Detail plugin | Sheet modale (PluginDetailView) | Inspector panel latéral non intrusif |
| Actions plugin | Via detail sheet | Context menu direct |
| Error recovery | Vue séparée (ErrorView) | État inline dans GenerationView |
| Build log | ❌ absent | ✅ BuildLogView accessible depuis l'erreur |
| Account | ❌ absent | ✅ AccountView (plan · usage · danger zone) |
| Logout | ❌ absent | ✅ via AccountView |
| Nombre d'écrans | 9 vues | 7 vues core + 4 auth (future) |
