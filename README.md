# Plume

Mini-app macOS (barre de menus) qui reproduit la fonctionnalité « AI Command sur sélection » de Raycast Pro : un raccourci global capture la sélection courante dans n'importe quelle app, la transforme via Claude, affiche le résultat en streaming dans un panneau flottant, puis le colle à la place de la sélection.

## Usage

1. Sélectionner du texte dans n'importe quelle app.
2. Déclencher une action (raccourcis reconfigurables dans les Réglages) :
   - **⌃⌥C** — *Corriger la sélection* : orthographe, grammaire, formulation légèrement améliorée, langue et ton préservés.
   - **⌃⌥P** — *Structurer en prompt* : transforme une idée brute en prompt clair et efficace, prêt à envoyer à un assistant IA (objectif, contexte, contraintes, format explicités ; espaces réservés `[préciser…]` si une info manque).
3. Le panneau apparaît près du pointeur et le résultat s'écrit en streaming.
4. **Entrée** (ou bouton « Coller ») → colle le résultat à la place de la sélection, puis restaure le presse-papiers d'origine. **Échap** → annule sans rien toucher. **⌘C / « Copier »** → copie seulement.

L'app source garde le focus pendant tout le cycle : le panneau ne « vole » jamais la fenêtre active.

## Installation

```bash
Scripts/build_app.sh
open /Applications/Plume.app
```

Au premier lancement :

1. **Clé API** — la fenêtre Réglages s'ouvre si aucune clé n'est configurée. Créer une clé sur [console.anthropic.com](https://console.anthropic.com/settings/keys) et la coller dans le champ (stockée dans le Trousseau). En dev, la variable d'environnement `ANTHROPIC_API_KEY` prime sur le Trousseau.
2. **Accessibilité** — au premier raccourci, macOS demande l'autorisation (Réglages Système → Confidentialité et sécurité → Accessibilité). Nécessaire pour lire la sélection et simuler ⌘C/⌘V.

### Certificat de signature stable (recommandé)

Une signature ad-hoc change à chaque build → macOS redemande Accessibilité et l'accès Trousseau après chaque recompilation. Pour éviter ça, créer une fois un certificat auto-signé :

Trousseau d'accès → menu Trousseau d'accès → Assistant de certification → **Créer un certificat…** → nom `Plume Local Dev`, type de certificat « Signature de code », racine auto-signée.

Le script l'utilise automatiquement (sinon il se replie sur ad-hoc avec un avertissement).

## Détails

- **Modèle** : `claude-haiku-4-5` (constante dans `Sources/Plume/Support/Constants.swift`), streaming SSE. Coût ≈ 0,2 centime par correction courte.
- **Capture** : API Accessibilité (`AXSelectedText`) d'abord, repli sur un ⌘C simulé (Chrome/Electron) avec restauration du presse-papiers.
- **Collage** : réactive l'app d'origine, colle via ⌘V simulé, puis restaure le presse-papiers multi-types (images/RTF compris) après 500 ms (`Constants.clipboardRestoreDelayNs`, désactivable via `restoreClipboardAfterPaste`).
- **Actions** : chaque action (prompt système, budget de tokens, libellés) est définie dans `Sources/Plume/AI/PlumeAction.swift` — en ajouter une nouvelle = un cas d'enum + un raccourci.
- **Prompt** : toutes les instructions vivent dans le message `system` ; le texte sélectionné part tel quel en `user` (limite l'injection de prompt). La langue du texte est préservée.
- **Icône** : régénérable via `Scripts/make_icon.sh` (dessin AppKit → `icon/AppIcon.icns`, embarquée par `build_app.sh`).
- **Troncature** : si la réponse atteint `max_tokens`, badge « Réponse tronquée » + bouton « Réessayer + » avec budget doublé.
- **Test CLI sans UI** :

```bash
ANTHROPIC_API_KEY=sk-ant-… .build/release/Plume --selftest "un texte avec des faute"
```

## Limites connues

- Raccourcis simulés via keycodes physiques (positions C/V) : OK en QWERTY et AZERTY, pas en Dvorak/Bépo.
- « Lancer à l'ouverture de session » exige l'app packagée dans /Applications (pas `swift run`).
