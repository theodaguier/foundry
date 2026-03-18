# Foundry — Stratégie Marketing

> Document récapitulatif — Mars 2026

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

## 2. Le vrai benchmark de prix

Les alternatives réelles pour un producteur qui veut un plugin sur mesure :

| Alternative | Coût | Délai | Résultat |
|---|---|---|---|
| Embaucher un dev JUCE freelance | 3 000 – 15 000 $ | 2-8 semaines | Plugin sur mesure |
| Apprendre le C++/JUCE soi-même | 0 $ (mais du temps) | 6-18 mois | Peut-être un plugin |
| Acheter un plugin existant qui s'en approche | 50 – 200 $ | Immédiat | Compromis, pas exactement ce qu'on veut |
| Ne rien faire | 0 $ | — | Frustration, son générique |
| **Foundry** | **59 $** | **5 min** | **Plugin custom, exactement ce qu'on veut** |

L'ancrage naturel : un plugin custom coûte normalement des milliers d'euros. Foundry le fait pour 59 $.

---

## 3. Modèle de pricing recommandé — Hybride

### Structure

| Plan | Prix | Contenu |
|---|---|---|
| **Essai gratuit** | 0 $ | 3 plugins (à vie, pas par mois) |
| **Achat unique** | **59 $** | 20 plugins/mois, mises à jour pendant 1 an |
| **Crédits supplémentaires** | 5 $ pour 5 plugins | Pour les mois où on dépasse les 20 |
| **Mises à jour (après 1 an)** | 29 $/an (optionnel) | Accès aux nouvelles versions |

### Pourquoi ce modèle

**L'essai gratuit de 3 plugins** exploite l'effet de dotation (Endowment Effect). Une fois que le producteur a créé ses 3 plugins et les utilise dans son DAW, ces plugins sont les siens. Il les a décrits, ils portent son nom, son son. Il ne peut plus s'en passer.

**59 $ en achat unique** s'aligne avec les habitudes du marché audio. Les musiciens achètent des plugins, des packs, des instruments virtuels. Ils connaissent ce format. Zéro friction cognitive. Ce montant est suffisamment bas pour être un achat impulsif face au coût réel d'un dev freelance, mais suffisamment élevé pour signaler de la valeur.

**20 plugins/mois** est largement suffisant pour 99 % des utilisateurs. La limite sert surtout à maîtriser les coûts d'API côté serveur, pas à frustrer.

**Les crédits supplémentaires** couvrent les power users sans créer de perte financière.

### Psychologie du prix

- **Anchoring** : Le comparable est un freelance à 5 000 $. Face à ça, 59 $ est dérisoire.
- **Mental Accounting** : "Ce plugin m'a coûté 3 $" (59 $ / 20 plugins/mois) vs. Serum à 189 $.
- **Zero-Price Effect** : Les 3 plugins gratuits éliminent tout risque perçu. L'utilisateur teste avant de payer.
- **Loss Aversion** : Une fois les 3 plugins créés et utilisés en production, ne PAS acheter Foundry signifie perdre l'accès à la création de nouveaux plugins. La perte pèse plus que le gain.

---

## 4. Positionnement

### Ce que Foundry est

Un outil de création. Le premier outil qui permet à un producteur de musique de construire ses propres plugins audio, de A à Z, sans écrire une seule ligne de code.

### Ce que Foundry n'est pas

- Un service de samples ou de presets
- Un marketplace de plugins
- Un outil de mastering automatisé
- Un concurrent de DAWs ou de plugins existants

Foundry est dans sa propre catégorie : la **création d'outils audio sur mesure**.

### Le message central

> **"Your sound doesn't exist yet. Build it."**

L'IA est un détail d'implémentation. Le producteur s'en fiche de comment ça marche. Il veut son plugin, son son, son identité sonore.

---

## 5. Communication

### Canaux par ordre de priorité

#### 1. YouTube — Priorité maximale

Format : démos de 45-90 secondes + tutoriels de 3-5 minutes.

Le concept "je décris un plugin et je l'utilise dans mon morceau" est intrinsèquement captivant. Les producteurs passent des heures sur YouTube à chercher des outils et des techniques.

Exemple de vidéo type :

```
[Écran noir]
"I want a granular delay with pitch shifting and a tape saturation mode"
[On tape Enter]
[Progress bar, time-lapse de 2 min]
[Le plugin apparaît dans Ableton]
[On joue un beat, on tourne les knobs]
[Texte : "Your plugin. Your sound. Foundry."]
```

Pas besoin d'expliquer l'IA, JUCE, Claude, le C++. La magie parle d'elle-même.

#### 2. Reddit

Subreddits cibles : r/musicproduction, r/WeAreTheMusicMakers, r/synthesizers, r/audioproduction.

Les producteurs y découvrent des outils et font confiance aux recommandations de pairs. Posts authentiques, démos honnêtes, participation aux discussions. Pas de marketing corporate.

#### 3. Twitter/X

Threads de démo, partage de plugins générés. Le côté "wow" génère du partage organique. Format idéal : courte vidéo + description du prompt utilisé.

#### 4. Discord — Communauté Foundry

Les premiers utilisateurs deviennent des évangélistes. Ils partagent leurs prompts, leurs plugins, s'entraident. C'est un effet réseau : plus il y a de monde, plus il y a d'idées de plugins, plus le produit semble indispensable.

### Règles de communication

- **Ne jamais mettre "AI-powered" en headline.** En 2026, tout le monde le revendique. C'est un repoussoir. Montrer le résultat, pas la tech.
- **Ne pas comparer à des outils qui n'ont rien à voir.** Foundry est dans sa propre catégorie.
- **Ne pas survendre.** Si les plugins générés ne sont pas parfaits dans 100 % des cas, le dire. L'honnêteté construit plus de confiance que l'hyperbole.
- **Montrer, ne pas expliquer.** Une vidéo de 30 secondes d'un plugin généré et fonctionnel dans Ableton vaut plus que 1 000 mots de copy.

---

## 6. Stratégie de lancement

### Phase 1 — Beta fermée (semaines 1-4)

- Inviter 20-50 producteurs via Reddit/Discord/Twitter.
- Objectif : feedback sur la qualité des plugins, les prompts qui marchent, les frictions UX.
- Ces beta testeurs deviennent les premiers advocates.
- Leur offrir Foundry gratuitement à vie en échange de témoignages et de vidéos.

### Phase 2 — Lancement public (semaines 5-6)

- Landing page avec vidéo de démo en hero.
- Essai gratuit de 3 plugins, pas de carte bancaire requise.
- Prix de lancement : **49 $** au lieu de 59 $ ("early adopter pricing" — limité dans le temps, crée de l'urgence).
- Posts Reddit + threads Twitter + vidéo YouTube de lancement.

### Phase 3 — Croissance organique (mois 2+)

- Contenu YouTube régulier (1-2 vidéos/semaine : démos, tutoriels, "peut-on recréer le son de [artiste] avec Foundry ?").
- Galerie publique de plugins créés par la communauté (social proof + inspiration).
- Encourager le partage : "Built with Foundry" badge optionnel sur les plugins.

---

## 7. Pourquoi les gens paieront — Résumé

| Ce qu'ils paient | Levier psychologique |
|---|---|
| Ne pas apprendre le C++ | Raccourci (5 min vs. 12 mois) |
| Avoir un plugin que personne d'autre n'a | Unicité — leur son, leur identité |
| Ne pas gérer la technique (CMake, JUCE, builds) | Infrastructure invisible |
| La garantie que ça compile et ça marche | Fiabilité, réduction du risque |
| Créer un outil exactement comme ils l'imaginent | Empowerment créatif |

---

## 8. Métriques clés à suivre

| Métrique | Cible | Pourquoi |
|---|---|---|
| Taux de conversion essai → achat | > 15 % | Valide la proposition de valeur |
| Plugins générés par utilisateur/mois | 3-5 | Indique l'engagement réel |
| Coût API moyen par plugin | < 1,50 $ | Rentabilité du modèle |
| Taux de succès de génération | > 85 % | Fiabilité = confiance = rétention |
| NPS (Net Promoter Score) | > 50 | Bouche-à-oreille organique |
