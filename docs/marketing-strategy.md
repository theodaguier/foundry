# Foundry — Stratégie Business & Marketing

> Dernière mise à jour : 22 mars 2026

---

## 1. Ce que Foundry vend réellement

Foundry ne vend pas "de l'IA" ni "du code". Foundry vend trois choses :

### Le raccourci

Sans Foundry, créer un plugin audio custom nécessite :

- Apprendre le C++ (6-12 mois)
- Maîtriser JUCE (2-3 mois)
- Comprendre le DSP audio (des années)
- Ou payer un développeur freelance (3 000 – 15 000 $)

Foundry compresse tout ça en 5 minutes.

### L'infrastructure invisible

L'utilisateur n'a pas à installer JUCE, configurer CMake, écrire du C++, débugger les builds, ni installer manuellement les plugins au bon endroit. Foundry fait tout ça en arrière-plan.

### La fiabilité

L'agent expert + boucle de correction automatique + validation qualité garantit un plugin compilé, installé et fonctionnel. Un utilisateur seul avec un LLM obtiendrait du code C++ qu'il ne saurait pas compiler.

---

## 2. Analyse concurrentielle

### Concurrent direct principal

**CubeSoundLab** (AudioFusion: Bureau) — lancé fin 2025.

| | CubeSoundLab | Foundry |
|---|---|---|
| Génération | Cloud (secondes) | Local (2-5 min) |
| Plateformes | Mac + Windows | Mac only (Windows = roadmap) |
| Onboarding | Zéro installation | Xcode + CMake requis |
| Instruments (VSTi) | ❌ FX only | ✅ |
| Souveraineté | Dépendance serveur | 100% local |
| Pricing | Crédits + 599$ Enterprise | Achat unique 59$ |

### Positionnement différenciant

Ne pas concurrencer CubeSoundLab sur la vitesse — jouer la carte opposée :

> **Local-first. No cloud. Vos plugins vous appartiennent vraiment.**

Compilation locale = plugin souverain, pas de compte requis, pas de serveur qui peut fermer. Argument premium, pas discount.

---

## 3. Pricing

### Structure

| Plan | Prix | Contenu |
|---|---|---|
| **Free** | 0 $ | 3 plugins à vie (pas par mois) |
| **Early Adopter** | **49 $** | 20 plugins/mois, mises à jour 1 an — limité aux 200 premiers clients |
| **Standard** | **59 $** | 20 plugins/mois, mises à jour 1 an |
| **Commercial** | **199 $** | Illimité + droit de revendre les plugins générés |

### Rentabilité par client (Standard)

| Poste | Montant |
|---|---|
| Revenu | 59 $ |
| Claude API (20 plugins × ~1 $) | ~20 $ |
| **Marge brute** | **~39 $ (66 %)** |

### Règles pricing

- ❌ Pas d'abonnement mensuel — le marché audio achète des plugins, pas des subs
- ❌ Pas de crédits — crée de l'anxiété à chaque génération
- ❌ Pas de prix < 40 $ — signal de faible valeur
- ✅ Achat unique = zéro friction cognitive
- ✅ Early adopter limité aux 200 premiers = urgence crédible (pas une fausse deadline)

### Psychologie du prix

- **Anchoring** : Le comparable est un freelance à 5 000 $. Face à ça, 59 $ est dérisoire.
- **Mental Accounting** : "Ce plugin m'a coûté 3 $" (59 $ / 20 plugins/mois) vs. Serum à 189 $.
- **Zero-Price Effect** : Les 3 plugins gratuits éliminent tout risque perçu.
- **Loss Aversion** : Une fois les 3 plugins créés et utilisés en production, ne PAS acheter = perdre l'accès à de nouveaux plugins.

---

## 4. Benchmark de prix

| Alternative | Coût | Délai |
|---|---|---|
| Freelance JUCE | 3 000 – 15 000 $ | 2-8 semaines |
| Apprendre C++/JUCE | 0 $ (temps) | 6-18 mois |
| Plugin existant approchant | 50 – 200 $ | Immédiat |
| CubeSoundLab | Crédits (~5-10 $/plugin) | Secondes |
| **Foundry** | **59 $ (20 plugins/mois)** | **2-5 min** |

---

## 5. Positionnement

### Message central

> **"Your sound doesn't exist yet. Build it."**

L'IA est un détail d'implémentation. Le producteur s'en fiche de comment ça marche. Il veut son plugin, son son, son identité sonore.

### Ce que Foundry est

Un outil de création. Le premier outil qui permet à un producteur de musique de construire ses propres plugins audio, de A à Z, sans écrire une seule ligne de code, entièrement en local.

### Ce que Foundry n'est pas

- Un service de samples ou de presets
- Un marketplace de plugins
- Un outil de mastering automatisé
- Un concurrent de DAWs ou de plugins existants

---

## 6. Roadmap

### Phase 1 — Validation (semaines 1-4)
**Objectif : taux de succès de génération > 80% sur 50 plugins testés**

- [ ] Beta fermée 10-20 producteurs (Reddit : r/musicproduction, r/WeAreTheMusicMakers)
- [ ] Instrumenter la pipeline : logger chaque génération (prompt, type, succès/échec, durée)
- [ ] Identifier les 3 archetypes de prompts qui marchent le mieux
- [ ] Recueillir témoignages + vidéos de plugins dans des DAWs réels

### Phase 2 — Lancement public (semaines 5-8)
**Objectif : 50 clients payants, NPS > 40**

- [ ] Landing page avec vidéo démo 45 sec
- [ ] Essai gratuit 3 plugins, sans carte bancaire
- [ ] Prix early adopter 49 $ (200 premiers clients)
- [ ] Posts Reddit + thread Twitter/X
- [ ] 1ère vidéo YouTube démo brute

### Phase 3 — Croissance (mois 3-6)
**Objectif : 200+ clients, 10 000 $/mois**

- [ ] Prix standard 59 $
- [ ] Galerie publique de plugins communauté
- [ ] YouTube 1 vidéo/semaine
- [ ] Discord communauté Foundry
- [ ] Licence Commercial 199 $ pour revente

### Phase 4 — Expansion (mois 6-12)
**Objectif : ouvrir le marché Windows (60% des producteurs)**

- [ ] Rewrite UI Electron ou Tauri (issue #52)
- [ ] Lancement Windows
- [ ] Évaluer génération cloud si demande confirmée

---

## 7. Communication

### Canaux par ordre de priorité

**1. YouTube — Priorité maximale**
Format : démos 45-90 sec + tutoriels 3-5 min. Le concept se vend visuellement.

**2. Reddit**
r/musicproduction, r/WeAreTheMusicMakers, r/synthesizers, r/audioproduction. Posts authentiques, démos honnêtes.

**3. Twitter/X**
Threads démo, plugins générés. Format : courte vidéo + prompt utilisé.

**4. Discord**
Communauté Foundry. Les early users deviennent des évangélistes.

### Règles de communication

- Ne jamais mettre "AI-powered" en headline — en 2026 c'est un repoussoir
- Montrer le résultat, pas la tech
- Ne pas survendre : honnêteté > hyperbole
- Une vidéo de 30 sec dans Ableton vaut plus que 1 000 mots de copy

---

## 8. Métriques clés

| Métrique | Cible | Pourquoi |
|---|---|---|
| Taux de conversion essai → achat | > 15 % | Valide la proposition de valeur |
| Taux de succès de génération | > 85 % | Fiabilité = confiance = rétention |
| Coût API moyen par plugin | < 1,50 $ | Rentabilité du modèle |
| Plugins générés par user/mois | 3-5 | Indique l'engagement réel |
| NPS | > 50 | Bouche-à-oreille organique |
| Clients payants (fin phase 2) | 50 | Validation marché |
| Revenu mensuel (fin phase 3) | 10 000 $ | Viabilité business |
