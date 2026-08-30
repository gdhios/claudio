# Protocole de test

Ce que Claudio ne doit jamais casser : le texte capturé part dans une requête
bien formée, le flux revient entier, le résultat se colle à la place de la
sélection, le presse-papiers ressort intact, la dépense est comptée juste et la
mise à jour arrive. Le protocole étage les vérifications en trois niveaux, du
moins cher au plus complet : chaque niveau attrape ce que le précédent ne peut
pas voir, et ne se paie qu'à la fréquence qui le justifie. Une petite
modification ne coûte que le niveau 1 ; la publication paie les trois.

## Les trois niveaux

| Niveau | Commande | Durée | Quand |
|---|---|---|---|
| 1 · Unitaires | `swift test` (ou `Scripts/test.sh`) | secondes | à chaque modification, et en CI sur chaque push et PR |
| 2 · Aperçus UI | `Scripts/test.sh --smoke` | ~2 min | en CI sur chaque push et PR, avec les PNG en artefacts |
| 3 · Bout en bout | `Scripts/test.sh --release` | + ~30 s et quelques millièmes de $ | à la publication (`Scripts/release.sh` l'exécute) |

- **Niveau 1** : toute la logique critique, sans réseau, sans permission, sans
  UI. Le flux SSE se teste sur des transcriptions, le temps s'injecte, les
  UserDefaults de test sont des suites jetables.
- **Niveau 2** : l'app compilée démarre et rend chaque écran critique en PNG
  (`--preview … --shot`, aucun réseau ni clé requis) : panneau en résultat, en
  flux, en erreur et en saisie de consigne ; palette nue et filtrée ; Réglages
  (clé API) et onglet Raccourcis. Un écran qui ne se construit plus — le genre
  de casse que les tests unitaires ne voient pas — sort en code d'erreur ou en
  PNG vide.
- **Niveau 3** : `--selftest` appelle la vraie API avec la vraie clé, sur les
  deux chemins de requête (action du catalogue, puis action libre avec
  consigne). C'est le seul niveau qui vérifie le contrat réel : authentification,
  en-têtes, IDs de modèles acceptés, flux SSE de production, jetons facturés.
  Il échoue par son code de sortie, donc il bloque la release.

## Ce qui protège chaque action critique

| Action critique | Risque si ça casse | Filet |
|---|---|---|
| Construction de la requête (prompt système, balisage `<texte_source>`, budget de tokens, modèle, température) | le modèle « répond » à la sélection au lieu de la transformer, ou l'API refuse (400) | `ClaudioRequestTests`, `ClaudioCatalogTests`, `AnthropicClientTests` (corps de requête) — niveau 1 |
| Lecture du flux SSE (texte, jetons facturés, troncature, erreurs en flux) | texte incomplet, dépense fausse, erreur muette | `AnthropicClientTests` sur transcriptions — niveau 1 ; conditions réelles au niveau 3 |
| Affichage en streaming (tampon de fragments) | texte perdu à l'écran, panneau saccadé | `StreamBufferTests` — niveau 1 |
| Collage : jamais un résultat partiel ou vide | on écrase la sélection avec un demi-résultat | `StreamBufferTests` (`canPaste`) — niveau 1 |
| Palette (filtrage, rangs 1–9, ligne libre toujours présente) | une action devient introuvable au clavier | `PaletteCatalogTests`, `PaletteDigitTests`, `ClaudioCatalogTests` — niveau 1 |
| Compteur de dépense (tarifs, cumul, remise à zéro quotidienne) | dépense affichée fausse | `CostLedgerTests` — niveau 1 |
| Clés de stockage et IDs (rawValue des actions, modèles, tailles de texte) | réglages perdus à la mise à jour, appels API en erreur | `ClaudioCatalogTests`, `PanelTextSizeTests` — niveau 1 |
| Mise à jour automatique (comparaison de versions, format de `version.json`) | mise à jour proposée en boucle, ou plus jamais | `UpdateCheckerTests` — niveau 1 ; `release.sh` vérifie en ligne ce qui est réellement servi |
| Les écrans se construisent (panneau, palette, Réglages) | l'app plante à l'ouverture d'un écran | niveau 2 (aperçus rendus et vérifiés) |
| Contrat vivant avec l'API Anthropic | tout ce qui précède, mais en production | niveau 3 (`--selftest`, deux chemins) |
| Capture de la sélection, collage simulé, restauration du presse-papiers, raccourcis globaux | le cœur du geste | non automatisable (permission Accessibilité + vraie session) → checklist ci-dessous |

## Ce que la machine ne peut pas tester — checklist de publication (2 min)

À dérouler à la main avant `Scripts/release.sh`, sur le build local du travail
commité (`Scripts/build_app.sh`) :

1. Sélection dans une app native (Notes) + ⌃⌥⌘I : le résultat colle **à la
   place** de la sélection.
2. La même chose dans Chrome ou une app Electron : c'est le chemin du ⌘C
   simulé, pas celui de l'Accessibilité.
3. Copier une **image**, lancer une action, coller le résultat : l'image est
   revenue dans le presse-papiers juste après (restauration multi-types).
4. ⌃⌥⌘K puis un chiffre : la ligne de ce rang se lance ; Échap ne laisse
   aucune trace.
5. Réglages → À propos → « Vérifier maintenant » répond (à jour ou mise à
   jour proposée).

## En CI

`.github/workflows/ci.yml` déroule `Scripts/test.sh --smoke` (niveaux 1+2) sur
un runner macOS à chaque push sur `main` ou sur une branche `claude/**`, et à
chaque pull request, avec cache SwiftPM. Les PNG rendus sont publiés en artefacts : une régression visuelle se
juge d'un œil depuis la page du run. Le niveau 3 n'est volontairement pas en
CI : il exige une clé et facture des jetons ; il vit dans `release.sh`, là où
il gate réellement quelque chose.

## Ajouter une fonctionnalité, c'est étendre le filet

- **De la logique nouvelle** (parsing, calcul, filtrage, état) → un test
  unitaire dans `Tests/ClaudioTests`. Sans réseau : le flux se rejoue en
  transcription, la date et les UserDefaults s'injectent.
- **Un nouvel écran ou une nouvelle phase du panneau** → un mode `--preview`
  dans `PreviewMode.swift`, ajouté à la liste de `Scripts/test.sh`.
- **Un champ de plus dans le contrat API ou `version.json`** → le verrouiller
  dans `AnthropicClientTests` / `UpdateCheckerTests`.
- **Un nouveau rawValue** (action, modèle, réglage) → l'ajouter à la liste
  fixée par `ClaudioCatalogTests` : c'est une clé de stockage, il ne changera
  plus.
- **Ce qui exige l'Accessibilité** → une ligne dans la checklist manuelle.

Conventions : XCTest, noms de tests en français qui énoncent le comportement
(« testLaTroncatureEstDetectee »), un commentaire de tête qui dit l'enjeu —
pourquoi ce test existe, pas ce qu'il fait.
