# Claudio

Mini-app macOS (barre de menus) qui reproduit la fonctionnalité « AI Command sur sélection » de Raycast Pro : un raccourci global capture la sélection courante dans n'importe quelle app, la transforme via Claude, affiche le résultat en streaming dans un panneau flottant, puis le colle à la place de la sélection.

## Usage

1. Sélectionner du texte dans n'importe quelle app.
2. Déclencher une action (raccourcis reconfigurables dans les Réglages) :
   - **⌃⌥C** — *Corriger la sélection* : orthographe, grammaire, formulation légèrement améliorée, langue et ton préservés.
   - **⌃⌥P** — *Structurer en prompt* : reformule une idée brute en demande claire et directe, compacte, sans y répondre.
   - **⌃⌥S** — *Structurer en prompt expert* : produit un prompt complet selon les bonnes pratiques Anthropic (rôle, contexte, tâche, contraintes, format de sortie, balises pour les données, espaces réservés `[préciser : …]` si une info manque).
   - **⌃⌥F** — *Traduire en français* : traduction naturelle et idiomatique, ton et mise en forme préservés.
   - **⌃⌥E** — *Traduire en anglais* : idem vers l'anglais (dicter en français, envoyer en anglais).
   - **⌃⌥T** — *Ton professionnel* : réécrit la sélection en message courtois et professionnel prêt à envoyer, sans en changer le fond.
   - **⌃⌥R** — *Résumer* : condense le texte en quelques phrases ou puces fidèles (résultat plutôt à copier qu'à coller).
3. Le panneau apparaît près du pointeur et le résultat s'écrit en streaming.
4. **Entrée** (ou bouton « Coller ») → colle le résultat à la place de la sélection, puis restaure le presse-papiers d'origine. **Échap** → annule sans rien toucher. **⌘C / « Copier »** → copie seulement.

L'app source garde le focus pendant tout le cycle : le panneau ne « vole » jamais la fenêtre active.

## Installation

```bash
Scripts/build_app.sh
open /Applications/Claudio.app
```

Au premier lancement :

1. **Clé API** — la fenêtre Réglages s'ouvre si aucune clé n'est configurée. Créer une clé sur [console.anthropic.com](https://console.anthropic.com/settings/keys) et la coller dans le champ (stockée dans le Trousseau). En dev, la variable d'environnement `ANTHROPIC_API_KEY` prime sur le Trousseau.
2. **Accessibilité** — au premier raccourci, macOS demande l'autorisation (Réglages Système → Confidentialité et sécurité → Accessibilité). Nécessaire pour lire la sélection et simuler ⌘C/⌘V.

### Certificat de signature stable (recommandé)

Une signature ad-hoc change à chaque build → macOS redemande Accessibilité et l'accès Trousseau après chaque recompilation. Pour éviter ça, créer une fois un certificat auto-signé :

Trousseau d'accès → menu Trousseau d'accès → Assistant de certification → **Créer un certificat…** → nom `Plume Local Dev`, type de certificat « Signature de code », racine auto-signée.

Le script l'utilise automatiquement (sinon il se replie sur ad-hoc avec un avertissement).

### Partager l'app (notarisation Apple)

Pour donner l'app à quelqu'un sans avertissement Gatekeeper. Prérequis, une seule fois (compte Apple Developer requis) :

1. **Certificat « Developer ID Application »** : Xcode → Settings… → Accounts → sélectionner le compte → Manage Certificates… → **+** → « Developer ID Application ».
2. **Identifiants notarytool** : créer un mot de passe d'application sur [account.apple.com](https://account.apple.com) (Connexion et sécurité → Mots de passe d'app), puis l'enregistrer dans le Trousseau (le `TEAMID` est entre parenthèses dans le nom du certificat, visible via `security find-identity -v -p codesigning`) :

```bash
xcrun notarytool store-credentials claudio-notary --apple-id guillaume.dhios@gmail.com --team-id TEAMID --password xxxx-xxxx-xxxx-xxxx
```

Ensuite, à chaque version à partager :

```bash
NOTARIZE=1 Scripts/build_app.sh
```

→ signe avec le certificat Developer ID (hardened runtime), soumet à Apple (~2 à 5 min), agrafe le ticket et produit `dist/Claudio-1.0.0.zip`. Le destinataire dézippe dans /Applications et double-clique — aucun avertissement. Il lui reste à créer sa clé API Anthropic (le champ « Espace de travail » ne concerne que les clés liées à l'identité) et à accorder Accessibilité.

Note : Developer ID étant une identité différente de « Plume Local Dev », macOS redemande une fois Accessibilité/Trousseau sur ta machine quand tu alternes entre build local et build notarisé.

## Détails

- **Modèle** : `claude-haiku-4-5` (constante dans `Sources/Claudio/Support/Constants.swift`), streaming SSE. Coût ≈ 0,2 centime par correction courte.
- **Capture** : API Accessibilité (`AXSelectedText`) d'abord, repli sur un ⌘C simulé (Chrome/Electron) avec restauration du presse-papiers.
- **Collage** : réactive l'app d'origine, colle via ⌘V simulé, puis restaure le presse-papiers multi-types (images/RTF compris) après 500 ms (`Constants.clipboardRestoreDelayNs`, désactivable via `restoreClipboardAfterPaste`).
- **Actions** : chaque action (prompt système, budget de tokens, libellés) est définie dans `Sources/Claudio/AI/ClaudioAction.swift` — en ajouter une nouvelle = un cas d'enum + un raccourci.
- **Prompts éditables** : l'onglet Prompts des Réglages affiche le prompt système de chaque action et permet de le modifier (stocké dans UserDefaults ; « Réinitialiser » revient au prompt du code, qui suit alors les mises à jour de l'app).
- **Prompt** : toutes les instructions vivent dans le message `system`. Pour les actions de structuration, le texte sélectionné est balisé `<texte_source>` dans le message `user` — sans cela, une sélection du type « résume mes mails » se lit comme un ordre et le modèle y répond au lieu de la transformer. La langue du texte est préservée.
- **Icône** : régénérable via `Scripts/make_icon.sh` (dessin AppKit → `icon/AppIcon.icns`, embarquée par `build_app.sh`).
- **Troncature** : si la réponse atteint `max_tokens`, badge « Réponse tronquée » + bouton « Réessayer + » avec budget doublé.
- **Test CLI sans UI** :

```bash
ANTHROPIC_API_KEY=sk-ant-… .build/release/Claudio --selftest "un texte avec des faute"
```

## Limites connues

- Raccourcis simulés via keycodes physiques (positions C/V) : OK en QWERTY et AZERTY, pas en Dvorak/Bépo.
- « Lancer à l'ouverture de session » exige l'app packagée dans /Applications (pas `swift run`).

## Licence et soutien

Claudio est open source sous licence [MIT](LICENSE). Projet indépendant, non affilié à Anthropic — Claude est une marque d'Anthropic, PBC.

Si l'app vous rend service : [offrez-moi un café](https://buymeacoffee.com/gdhios) ☕
