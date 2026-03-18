# Foundry — Design Document
**App macOS desktop · Audio plugin generation · Direction artistique & UI/UX**

> **Last updated:** 2026-03-18  
> **Scope:** Design system, interface, direction artistique, composants, états, motion

---

## 1. Vision & positionnement design

Foundry est un outil de création — pas un DAW, pas un plugin store. C'est un atelier.

Le parti pris : **l'interface disparaît pour laisser la création exister.** L'utilisateur doit sentir qu'il parle à un collaborateur invisible, pas qu'il remplit un formulaire. Chaque écran doit avoir la densité et la retenue d'un bon outil professionnel — rien de trop, rien de décoratif.

**Ancrage esthétique :** dark, minimal, craft. Proche de Linear ou de Craft en termes de densité et de sérieux, mais avec la chaleur d'un instrument de musique plutôt que d'un outil SaaS. Glaze est la référence explicite — cette idée de local-first, d'interface qui fait confiance à l'utilisateur.

**Ce que l'interface ne doit jamais être :**
- Un générateur d'AI avec des champs texte et des boutons bleus
- Une interface "musicale" avec des skeuomorphismes de studio
- Un dashboard avec des métriques

---

## 2. Design System

### 2.1 Couleur

#### Palette de base

```
Background primary    #0A0A0A    /* Noir pur — jamais de blanc */
Background elevated   #111111    /* Cartes, modals, sidebars */
Background subtle     #1A1A1A    /* Hover states, sections */
Background muted      #242424    /* Inputs, tags */

Border default        #2A2A2A    /* Séparateurs, contours */
Border subtle         #1E1E1E    /* Séparateurs très légers */
Border focus          #484848    /* Focus ring */

Text primary          #F0EDE8    /* Légèrement chaud — jamais blanc pur */
Text secondary        #888480    /* Labels, métadonnées */
Text tertiary         #555250    /* Placeholder, disabled */
Text inverse          #0A0A0A    /* Sur fond clair (rare) */
```

**Principe clé :** le fond n'est jamais `#000000` et le texte n'est jamais `#FFFFFF`. Ce dixième de degré de température crée une chaleur imperceptible mais réelle qui distingue les interfaces craft des interfaces génériques.

#### Couleur d'accent

Foundry n'a pas d'accent global fixe — l'accent est **généré par plugin**. La propriété `iconColor` de chaque plugin (`Plugin.iconColor: String`) devient la couleur d'accentuation contextuelle dans la detail view.

Cette décision est centrale : l'identité visuelle de chaque plugin colore son environnement. C'est vivant.

Pour les états système (loading, success, error) :

```
State processing      #C8C4BC    /* Neutral warm — couleur par défaut */
State success         #5A8A6A    /* Vert foncé, pas flashy */
State error           #8A4A4A    /* Rouge désaturé */
State warning         #8A7A4A    /* Amber foncé */
```

#### Modes

**Dark uniquement pour v1.** Une app de création audio s'utilise dans des studios peu éclairés, sur des moniteurs étalonnés. Le mode light peut venir plus tard mais ne doit pas contraindre les décisions v1.

---

### 2.2 Typographie

**Font principale : [SF Pro](https://developer.apple.com/fonts/) avec fallback système**

SF Pro est le choix évident sur macOS non pas par paresse mais parce qu'il bénéficie du rendu optique natif, des features OpenType (tnum pour les chiffres, liga, kern), et de la cohérence avec l'OS. Le dévier demande une raison forte — ici on n'en a pas.

#### Hiérarchie

```
Display          SF Pro Display  32px  -0.5px  weight 600   /* Rare, grands titres */
Heading 1        SF Pro Display  22px  -0.3px  weight 600   /* Titres de section */
Heading 2        SF Pro Text     17px  -0.2px  weight 600   /* Sous-titres */
Body             SF Pro Text     13px  -0.1px  weight 400   /* Corps de texte */
Body medium      SF Pro Text     13px  -0.1px  weight 500   /* Labels importants */
Caption          SF Pro Text     11px   0px    weight 400   /* Méta, timestamps */
Caption medium   SF Pro Text     11px   0px    weight 500   /* Labels de tags */
Mono             SF Mono         12px   0px    weight 400   /* Prompts, logs */
Mono small       SF Mono         11px   0px    weight 400   /* Code, paths */
```

**Tracking :** conservateur. Sur du body text à 13px, 0 ou légèrement négatif (-0.1px). Ne jamais letter-spacer du texte courant positivement — c'est réservé aux labels tout-caps.

**Line-height :** 1.5 pour le body, 1.3 pour les headings. Ne pas serrer en dessous de 1.2 même pour les affichages.

**Chiffres tabulaires (`tnum`) activés** systématiquement dans les contextes où des nombres sont alignés (listes, stats, progress).

---

### 2.3 Spacing & Layout

**Base unit : 4px.** Tout multiple de 4. Les espaces "magiques" autorisés : 2px pour les micro-ajustements optiques.

```
space-1    4px
space-2    8px
space-3    12px
space-4    16px
space-5    20px
space-6    24px
space-8    32px
space-10   40px
space-12   48px
space-16   64px
```

**Layout général (fenêtre principale) :**

```
┌──────────────────────────────────────────────────────┐
│  Toolbar macOS                           [•][–][□]  │
├────────────────────────────────────────────────────── │
│                                                      │
│   [+ Create]                        [Settings icon] │
│                                                      │
│   ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│   │          │ │          │ │          │           │
│   │  Plugin  │ │  Plugin  │ │  Plugin  │           │
│   │   Card   │ │   Card   │ │   Card   │           │
│   │          │ │          │ │          │           │
│   └──────────┘ └──────────┘ └──────────┘           │
│                                                      │
└──────────────────────────────────────────────────────┘
```

Fenêtre **sans sidebar** — Foundry est monocolonne pour v1. La bibliothèque de plugins est la home. Le workflow est linéaire. Pas besoin de navigation latérale.

**Taille de fenêtre :**
- Min : 680 × 480px
- Default : 800 × 600px  
- Résizable, pas fullscreenable par défaut

**Grille des cards :**
- 3 colonnes en default (800px)
- Gap : 16px
- Card width : ~240px
- Auto-fit — la grille se réarrange en 2 colonnes sous ~640px

---

### 2.4 Effets & matières

**Blur / vibrancy :** utilisé avec parcimonie. Le toolbar et les modals flottants peuvent utiliser `NSVisualEffectView` avec `.dark` material. Les sidebars de progression pourraient bénéficier d'un vibrancy `.hudWindow`. Mais attention : l'abus de blur est le premier signal d'un design qui manque de structure.

**Ombres :**
```
shadow-sm    0 1px 3px rgba(0,0,0,0.4)    /* Cards au repos */
shadow-md    0 4px 12px rgba(0,0,0,0.5)   /* Cards hover, dropdowns */
shadow-lg    0 12px 32px rgba(0,0,0,0.6)  /* Modals, sheets */
```

**Borders :** toujours 1px, jamais plus. `border-radius` unifié :
```
radius-sm    4px    /* Tags, badges */
radius-md    8px    /* Cards, inputs */
radius-lg    12px   /* Modals, sheets */
radius-xl    16px   /* Grand modal plein écran */
```

---

### 2.5 Iconographie

**SF Symbols exclusivement.** Version 5+. Toujours en `hierarchical` ou `palette` rendering selon le contexte, jamais `monochrome` sur fond dark (le contraste est trop brutal).

Poids des symbols aligné sur le poids de la typo environnante : body text → `.regular`, boutons → `.medium`, actions primaires → `.semibold`.

**Pas d'icônes custom pour v1** sauf si SF Symbols ne couvre pas un besoin spécifique. Créer des icônes coûte de la cohérence.

---

## 3. Composants

### 3.1 Plugin Card

Le composant central de la bibliothèque. Deux états principaux : avec logo généré, sans logo (fallback icon + accent color).

```
┌────────────────────────┐
│                        │  ← 240 × 240px
│      [Logo / Icon]     │  ← carré plein, fond accent color
│                        │
│  ████████████ type-tag │  ← overlay bottom
└────────────────────────┘
  DrakeVox Synth           ← 13px medium, text primary
  Instrument · AU + VST3   ← 11px, text tertiary
```

**États :**
- **Default** : ombre sm, border 1px subtle
- **Hover** : ombre md, border focus, légère élévation (translateY -1px)
- **Pressed** : scale 0.98
- **Building** : overlay avec progress bar en bas de la carte, opacity sur l'icon
- **Failed** : icon d'erreur en overlay, border rouge désaturé

**Logo area :**
- Si `logoAssetPath` existe : image plein cadre, `object-fit: cover`
- Sinon : fond uni `iconColor`, SF Symbol centré (type icon) en blanc à 70% opacité

**Type tag** (overlay bottom-right) :
- `instrument` → label "Synth"
- `effect` → label "Effect"  
- `utility` → label "Tool"
- Background `rgba(0,0,0,0.5)`, blur léger, `border-radius: 4px`, `11px` caption medium

**Actions au hover :**
Petits boutons (icon only) apparaissent en bas de la card : [Refine] [⋯]  
Transition opacity 150ms ease-out. Pas de tooltips forcés — juste des icons lisibles.

---

### 3.2 Bouton primaire (Create)

```
[+ Create]
```

- Background `#F0EDE8` (text primary inversé), text `#0A0A0A`
- Height 32px, padding 0 16px
- `border-radius: 8px`
- SF Symbol `plus` à gauche, weight `.medium`
- Hover : `#FFFFFF`
- Active : scale 0.97

**Philosophie :** un seul bouton primaire visible en permanence dans l'interface. Pas de hiérarchie de boutons secondaires/tertiaires dans la barre principale — ça crée du bruit.

---

### 3.3 Prompt View

L'écran le plus important. C'est là que l'utilisateur exprime son intention.

```
┌───────────────────────────────────────────────────┐
│                                                   │
│  Describe the plugin you want to create           │
│                                                   │
│  ┌─────────────────────────────────────────────┐  │
│  │                                             │  │
│  │  A warm vintage chorus with tape saturation │  │
│  │  and subtle flutter...                      │  │
│  │                                             │  │
│  └─────────────────────────────────────────────┘  │
│                                                   │
│  ──────────────────────────────────────────────   │
│                                                   │
│  Format        Stereo/Mono        Presets         │
│  ○ AU          ● Stereo           ○ 0             │
│  ○ VST3        ○ Mono             ● 5             │
│  ● Both                           ○ 10            │
│                                                   │
│                              [→ Generate]         │
│                                                   │
└───────────────────────────────────────────────────┘
```

**Textarea :**
- Font Mono 14px — le prompt ressemble à du code/texte intentionnel, pas à un champ de recherche
- Placeholder en italique, text tertiary : `"A warm reverb with shimmer and long tail…"`
- Pas de label au-dessus — le placeholder suffit
- Minimum 4 lignes, auto-resize jusqu'à 8 lignes
- Pas de border au repos, border subtle au focus
- Focus ring : border-focus + glow très léger `rgba(240,237,232,0.05)`

**Quick Options :**
- Séparateur horizontal avant les options — pas de titre "Options"
- Radio buttons natifs macOS, alignés sur 3 colonnes
- Label de colonne : 11px caption, text tertiary, pas de bold

**Le bouton Generate :**
- Aligné à droite, bottom
- Label : `Generate` avec SF Symbol `arrow.right` — pas "Create Plugin", trop verbal
- Désactivé si textarea vide

---

### 3.4 Generation Progress View

L'utilisateur attend. C'est un moment de suspension créative — l'interface doit refléter ça, pas imiter un loading state de SaaS.

```
┌───────────────────────────────────────────────────┐
│                                                   │
│                                                   │
│          Generating your plugin                   │
│          "A warm vintage chorus..."               │
│                                                   │
│                                                   │
│     ✓  Preparing project                          │
│     ⟳  Generating DSP                  2m 14s    │
│     ·  Generating UI                              │
│     ·  Compiling                                  │
│     ·  Installing                                 │
│                                                   │
│                                                   │
│                              [Cancel]             │
│                                                   │
└───────────────────────────────────────────────────┘
```

**Philosophie :** pas de progress bar globale avec pourcentage. Les étapes sont la vérité. L'utilisateur comprend où il en est sans avoir besoin d'un chiffre inventé.

**Steps :**
- Completed `✓` : text secondary, SF Symbol `checkmark` en `state-success`
- Active `⟳` : text primary, SF Symbol `arrow.2.circlepath` avec rotation continue
- Pending `·` : text tertiary, point ou tiret discret

**Timer :** affiché uniquement sur l'étape active, à droite, mono 11px, text tertiary. Format `Xm Xs`.

**Le prompt :** affiché en truncated (1 ligne) sous le titre — rappel contextuel, pas mise en avant.

**Animation de la step active :** rotation du symbol, lente (2s/tour), ease-in-out. Pas de bounce, pas de pulse. Quelque chose de régulier et de calme.

---

### 3.5 Result View

```
┌───────────────────────────────────────────────────┐
│                                                   │
│         ┌─────────────┐                           │
│         │             │                           │
│         │    [Logo]   │                           │
│         │             │                           │
│         └─────────────┘                           │
│                                                   │
│         Vintage Chorus Pro                        │
│         Effect · AU + VST3                        │
│                                                   │
│         ─────────────────────────────             │
│                                                   │
│         [Open in DAW]        [Regenerate]         │
│                                                   │
│         [← Back to library]                       │
│                                                   │
└───────────────────────────────────────────────────┘
```

**Logo :** 120×120px, border-radius 16px, ombre md. Si pas de logo : fond `iconColor`, icon type centré.

**"Open in DAW"** : bouton primaire.  
**"Regenerate"** : bouton ghost (border + text, pas de fond). Pas destructif — ça lance juste une nouvelle génération du même prompt.

**"Back to library"** : lien texte discret, pas de bouton. Ne pas mettre de chevron gauche SF Symbol — la sémantique est claire.

---

### 3.6 Error View

```
┌───────────────────────────────────────────────────┐
│                                                   │
│         ⚠                                         │
│                                                   │
│         Build failed after 3 attempts             │
│                                                   │
│         Last error                                │
│         ┌─────────────────────────────────────┐   │
│         │ error: use of undeclared identifier │   │
│         │ 'ParameterID::distortion'           │   │
│         └─────────────────────────────────────┘   │
│                                                   │
│         [Try again]          [Modify prompt]      │
│                                                   │
└───────────────────────────────────────────────────┘
```

**Le log d'erreur :** mono, fond `#1A1A1A`, scrollable, max 4 lignes visibles. L'utilisateur peut lire le vrai message — pas une paraphrase vague "something went wrong".

**"Try again"** : relance exactement le même prompt.  
**"Modify prompt"** : retourne au Prompt View avec le texte pré-rempli.

**⚠ symbol :** SF Symbol `exclamationmark.triangle`, `state-error`, taille 32px. Pas d'animation.

---

### 3.7 Dependency Checker / Setup Screen

Affiché au premier lancement si des dépendances manquent.

**Principe :** liste claire des dépendances avec leur état. Pas une onboarding page avec un hero illustration. C'est un check technique — le traiter comme tel.

```
  Foundry needs a few tools to work.

  ✓  Xcode CLI Tools          Installed
  ✓  CMake                    Installed
  ⚠  JUCE SDK                 Not found — Downloading… [████░░░░] 43%
  ✗  Claude Code CLI          Missing

     Install Claude Code CLI:
     npm install -g @anthropic-ai/claude-code

                                        [Copy command]
```

**Chaque dépendance sur une ligne.** Status clair. Pour `Claude Code CLI` manquant : afficher la commande en mono + bouton "Copy command". Pas de lien vers une doc externe si on peut éviter.

Quand tout est prêt : le bouton "Open Foundry" s'active et l'écran se referme.

---

## 4. Navigation & Flow

### 4.1 Architecture de navigation

Foundry est une **single-window app** avec navigation par remplacement de vue. Pas de sidebar, pas de tab bar. Le modèle est celui d'un flow linéaire avec possibilité de retour.

```
Library (home)
  └── Prompt View
        └── Quick Options (inline, dans Prompt View)
              └── Generation Progress
                    ├── Result View
                    │     └── (back to Library)
                    └── Error View
                          ├── Try again → Generation Progress
                          └── Modify prompt → Prompt View

Library
  └── Plugin Detail (sheet ou modal)
        ├── Refine View
        │     └── Refine Progress → Result | Error
        └── Recreate Logo (modal dans le detail)
```

### 4.2 Transitions

**Library → Prompt View :** slide horizontal (trailing → leading), 250ms, spring amorti.

**Prompt → Progress :** cross-fade, 200ms. Pas de slide — ça casse le sentiment de progression.

**Progress → Result :** fade, 300ms. Moment de révélation — la transition doit laisser respirer.

**Progress → Error :** cross-fade rapide, 150ms. Pas de drama.

**Toutes les sheets/modals :** `NSWindow.animationBehavior = .utilityWindow` ou sheet standard macOS. Pas de transitions custom sur les fenêtres système.

---

## 5. Motion Design

### 5.1 Principes

**Purposeful over decorative.** Chaque animation répond à une question : est-ce que ça aide l'utilisateur à comprendre ce qui se passe ?

**Durées :**
```
instant      0ms       /* Pas d'animation — feedback immédiat */
fast         100ms     /* Micro-interactions (hover states) */
default      200ms     /* La plupart des transitions */
deliberate   300ms     /* Transitions de vue, modals */
slow         500ms     /* Révélations importantes (Result screen) */
```

**Easing :**
```
ease-out     cubic-bezier(0, 0, 0.3, 1)     /* Entrées — rapide puis ralentit */
ease-in      cubic-bezier(0.4, 0, 1, 1)     /* Sorties — lent puis accélère */
ease-in-out  cubic-bezier(0.4, 0, 0.2, 1)   /* Éléments persistants */
spring       stiffness: 400, damping: 30     /* Interactions physiques */
```

**Ce qu'on n'anime pas :**
- Les couleurs de texte
- Les borders (sauf focus ring)
- Tout ce qui est en dehors du viewport au repos

### 5.2 Animations spécifiques

**Step indicator actif (Progress) :**
- `@keyframes rotate` sur le symbol, 2000ms, `ease-in-out`, `infinite`
- Pas d'acceleration brusque

**Card hover :**
- `transform: translateY(-1px)` + ombre upgrade
- 100ms ease-out
- Pas de scale — trop agressif sur une grille dense

**Bouton primaire active :**
- `transform: scale(0.97)` + légère réduction d'opacité
- 80ms instant (ou spring)

**Logo apparaît dans Result View :**
- Fade + `transform: scale(0.9) → scale(1.0)`, 400ms spring
- Délai de 100ms après l'entrée de la vue pour laisser le layout se stabiliser

---

## 6. Accessibilité

### 6.1 Contraste

Tous les textes respectent WCAG 2.1 AA :
- Text primary `#F0EDE8` sur `#0A0A0A` → ratio ≈ 18:1 ✓
- Text secondary `#888480` sur `#0A0A0A` → ratio ≈ 5.2:1 ✓ (AA large)
- Text tertiary `#555250` sur `#0A0A0A` → ratio ≈ 3.1:1 — limite. À utiliser uniquement pour des éléments non-essentiels (placeholders, disabled).

### 6.2 Focus management

**Focus ring explicite** sur tous les éléments interactifs. Ne jamais `outline: none` sans alternative.
- Focus ring : border 2px `#F0EDE8` + offset 2px. Visible mais discret.

**Ordre de tabulation** logique et séquentiel. Sur le Prompt View : textarea → options → bouton Generate.

### 6.3 Réduction de mouvement

Respecter `prefers-reduced-motion`. Toutes les animations non-essentielles passent à `duration: 0` ou à des transitions opacity simples.

### 6.4 Tailles de cibles

Minimum 28×28px pour tous les éléments cliquables sur macOS (les touch targets desktop peuvent être plus petits que mobile mais pas en dessous de 24px).

---

## 7. Figma / Handoff Notes

### Variables

Toutes les couleurs, espacements et typographies sont définis comme **Figma Variables** (pas des styles) pour permettre la tokenisation directe vers Swift.

Structure des tokens :
```
color/background/primary
color/background/elevated
color/text/primary
color/text/secondary
...
spacing/4
spacing/8
...
typography/body/size
typography/body/weight
typography/body/tracking
```

### Composants

Chaque composant a ses variants nommés explicitement :
- `PluginCard/Default`, `PluginCard/Hover`, `PluginCard/Building`, `PluginCard/Failed`
- `Button/Primary/Default`, `Button/Primary/Hover`, `Button/Primary/Disabled`
- `Step/Pending`, `Step/Active`, `Step/Complete`

**Auto-layout sur tout.** Aucun composant avec des dimensions fixes hardcodées sauf les cards qui ont une width contrainte par la grille.

### Assets

- Icons : SF Symbols, exportés uniquement si custom
- Logos de plugins : traitement image `object-fit: cover`, coin radius 12px systématiquement

---

## 8. Décisions & rationale

| Décision | Raison |
|----------|--------|
| Dark only v1 | Public de créatifs audio, studios sombres, moniteurs étalonnés |
| Pas de sidebar | Flow linéaire — la nav latérale crée de la complexité sans bénéfice v1 |
| Mono pour le textarea prompt | Différencie le prompt d'un simple champ texte, crée un sentiment d'intention |
| Accent color par plugin | L'identité de chaque plugin colore son environnement — vivant et cohérent |
| Steps sans progress bar globale | Les pourcentages sont mensongers sur des processus IA — les étapes sont la vérité |
| Pas de logo generation automatique | 65s + 3.6GB RAM — trop lourd pour être systématique, juste en tant qu'action manuelle |
| SF Pro + SF Symbols | Rendu natif optimal, cohérence OS, pas de dette custom |

---

## 9. Ce qui viendra après v1

Ces décisions sont **hors scope v1** mais doivent être anticipées dans les tokens et la structure des composants pour ne pas créer de dette :

- **Mode light** → les tokens couleur sont déjà sémantiques, le switch se fait au niveau des valeurs
- **Taille de fenêtre variable** → la grille de cards est auto-fit, pas hardcodée
- **Audio preview in-app** → prévoir un emplacement dans la detail view pour un player
- **Community gallery** → la card existante peut évoluer avec un avatar d'auteur sans refonte
- **Tailles de fenêtre très grandes** → la grille passe à 4+ colonnes naturellement

---

*Ce document est la source de vérité design. Il évolue avec l'app. Toute décision prise en implémentation qui diverge doit être documentée ici avec sa justification.*
