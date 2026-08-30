# Claudio

Mini-app macOS (barre de menus) qui capture la sélection courante dans n'importe quelle app, la transforme via Claude, affiche le résultat en streaming dans un panneau flottant, puis le colle à la place de la sélection.

## Usage

1. Sélectionner du texte dans n'importe quelle app.
2. Déclencher une action (raccourcis reconfigurables dans les Réglages) :
   - **⌃⌥⌘K** *Palette d'actions* : ouvre le panneau sur la liste complète plutôt que sur une action. On lance une ligne avec son chiffre, **1** à **9**, ou avec **↑↓** puis **⏎**. On filtre à la frappe (accents et casse ignorés) : dès qu'une saisie commence, les chiffres s'y écrivent — c'est ce qui permet une consigne comme « résume en 3 phrases » — et **⌘1**–**⌘9** prend le relais pour lancer. La dernière ligne est toujours l'action libre : si rien ne correspond, ce qui est tapé devient la consigne. Le seul raccourci à retenir.
   - **⌃⌥⌘I** *Corriger la sélection* : orthographe, grammaire, formulation légèrement améliorée, langue et ton préservés.
   - **⌃⌥⌘P** *Structurer en prompt* : reformule une idée brute en demande claire et directe, compacte, sans y répondre.
   - **⌃⌥⌘^** *Structurer en prompt expert* : produit un prompt complet selon les bonnes pratiques Anthropic (rôle, contexte, tâche, contraintes, format de sortie, balises pour les données, espaces réservés `[préciser : …]` si une info manque).
   - **⌃⌥⌘F** *Traduire en français* : traduction naturelle et idiomatique, ton et mise en forme préservés.
   - **⌃⌥⌘E** *Traduire en anglais* : idem vers l'anglais (dicter en français, envoyer en anglais).
   - **⌃⌥⌘T** *Ton professionnel* : réécrit la sélection en message courtois et professionnel prêt à envoyer, sans en changer le fond.
   - **⌃⌥⌘R** *Résumer* : condense le texte en quelques phrases ou puces fidèles (résultat plutôt à copier qu'à coller).
   - **⌃⌥⌘L** *Lapacompris* : réexplique un texte dense ou jargonneux beaucoup plus simplement, comme à un ami, en gardant les faits exacts (chemins, commandes, nombres, décisions).
   - **⌃⌥⌘D** *Action libre* : le panneau demande d'abord la consigne (« traduis en espagnol », « mets en puces »…), puis l'applique à la sélection. Tout ce que le catalogue ne couvre pas.
3. Le panneau apparaît près du pointeur et le résultat s'écrit en streaming.
4. **Entrée** (ou bouton « Coller ») → colle le résultat à la place de la sélection, puis restaure le presse-papiers d'origine. **Échap** → annule sans rien toucher. **⌘C / « Copier »** → copie seulement.

L'app source garde le focus pendant tout le cycle : le panneau ne « vole » jamais la fenêtre active.

## Installation

```bash
Scripts/build_app.sh
open /Applications/Claudio.app
```

Au premier lancement :

1. **Clé API** : la fenêtre Réglages s'ouvre si aucune clé n'est configurée. Créer une clé sur [console.anthropic.com](https://console.anthropic.com/settings/keys) et la coller dans le champ (stockée dans le Trousseau). En dev, la variable d'environnement `ANTHROPIC_API_KEY` prime sur le Trousseau.
2. **Accessibilité** : au premier raccourci, macOS demande l'autorisation (Réglages Système → Confidentialité et sécurité → Accessibilité). Nécessaire pour lire la sélection et simuler ⌘C/⌘V.

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

→ signe avec le certificat Developer ID (hardened runtime), soumet à Apple (~2 à 5 min), agrafe le ticket et produit `dist/Claudio-1.0.0.zip`. Le destinataire dézippe dans /Applications et double-clique, sans aucun avertissement. Il lui reste à créer sa clé API Anthropic (le champ « Espace de travail » ne concerne que les clés liées à l'identité) et à accorder Accessibilité.

Note : Developer ID étant une identité différente de « Plume Local Dev », macOS redemande une fois Accessibilité/Trousseau sur ta machine quand tu alternes entre build local et build notarisé.

### Publier une version

Une version n'est pas « faite » quand elle compile : elle l'est quand elle est notarisée, poussée, publiée en release GitHub, déployée sur le site, annoncée par `version.json` et vérifiée en ligne. Toute cette chaîne tient dans un script, dans cet ordre, avec arrêt à la première étape qui échoue :

```bash
Scripts/release.sh 1.4.0 "palette d'actions"
```

Le travail lui-même doit être commité avant : le script ne publie que le changement de version. Il enchaîne vérifications (branche `main`, arbre propre, tag libre, `gh` authentifié, VPS joignable) → numéro de version dans `build_app.sh` et sur les deux landings → `swift test` → build notarisé → commit + tag + push → release GitHub (notes reprises de `dist/release_notes_X.Y.Z.md` s'il existe) → `rsync` du site, envoi du zip en `Claudio.zip`, réécriture de `version.json` → vérification de ce qui est réellement servi : le flux annonce la bonne version, le zip téléchargé a le même SHA-256 que le zip notarisé, les quatre pages répondent et affichent le bon numéro, la release GitHub porte son asset.

## Détails

- **Modèle** : choix par action dans Réglages → Prompts (Haiku 4.5 par défaut, Sonnet 5 ou Opus 5 au choix), streaming SSE. Tarifs Anthropic par million de jetons, entrée / sortie : Haiku 4.5 1 $ / 5 $, Sonnet 5 2 $ / 10 $, Opus 5 5 $ / 25 $ — soit ≈ 0,12 $ pour cent actions courtes avec Haiku.
- **Dépense** : `AnthropicClient` relève les jetons que l'API facture (`message_start` pour l'entrée, `message_delta` pour la sortie) ; `CostLedger` cumule le total de la journée dans UserDefaults et le remet à zéro au changement de date. Affiché dans Réglages → Général, désactivable (`AppSettings.costCounterEnabled`). Rien n'est envoyé nulle part : le calcul est local et le décompte qui fait foi reste celui de console.anthropic.com.
- **Capture** : API Accessibilité (`AXSelectedText`) d'abord, repli sur un ⌘C simulé (Chrome/Electron) avec restauration du presse-papiers.
- **Collage** : réactive l'app d'origine, colle via ⌘V simulé, puis restaure le presse-papiers multi-types (images/RTF compris) après 500 ms (`Constants.clipboardRestoreDelayNs`, désactivable via `restoreClipboardAfterPaste`).
- **Actions** : chaque action (prompt système, budget de tokens, libellés) est définie dans `Sources/Claudio/AI/ClaudioAction.swift` ; en ajouter une nouvelle = un cas d'enum + un raccourci. Ce qui est réellement envoyé à l'API est un `ClaudioRequest` (`AI/ClaudioRequest.swift`), construit depuis une entrée du catalogue ou depuis une consigne libre — c'est ce découplage qui rend l'action libre et la palette possibles.
- **Palette** : `AI/PaletteCatalog.swift` (filtrage, lignes) et `UI/PaletteView.swift` (rendu). Le panneau est le même objet que pour un résultat : la phase `.choosingAction` affiche la liste, la ligne retenue remplace la requête de la session et le stream démarre. Le filtre retient une action si chaque mot tapé commence un mot de son titre ou de son sous-titre.
- **Panneau** : la hauteur de la fenêtre suit le contenu, interpolée côté SwiftUI (`ResultPanelView`) pour qu'elle glisse au lieu de sauter d'une ligne à l'autre. Les fragments du flux SSE sont regroupés dans `CorrectionSession` (`appendStreamed` / `flushStreamed`, une publication toutes les 60 ms) au lieu d'être republiés un par un : republier le texte entier à chaque fragment relançait une mise en page complète, de plus en plus coûteuse à mesure que la réponse s'allongeait.
- **Taille du texte** : Réglages → Général → Panneau (`UI/PanelTextSize.swift`, `AppSettings.panelTextSize`). Le corps du résultat, de la consigne libre et des lignes de la palette suit le réglage, la largeur du panneau avec ; les repères (rangs, icônes, raccourcis, indices) gardent leur taille. Les `rawValue` de `PanelTextSize` sont des clés de stockage : ils ne changent pas.
- **Prompts éditables** : l'onglet Prompts des Réglages affiche le prompt système de chaque action et permet de le modifier (stocké dans UserDefaults ; « Réinitialiser » revient au prompt du code, qui suit alors les mises à jour de l'app).
- **Prompt** : toutes les instructions vivent dans le message `system`. Pour les actions de structuration, le texte sélectionné est balisé `<texte_source>` dans le message `user`. Sans cela, une sélection du type « résume mes mails » se lit comme un ordre et le modèle y répond au lieu de la transformer. La langue du texte est préservée.
- **Icône** : `icon/AppIcon.icns`, embarquée par `build_app.sh`. Les sources de l'icône ne sont pas versionnées (`Scripts/make_icon.sh` sert à la régénérer en local).
- **Mises à jour** : vérification automatique une fois par jour (simple lecture de `version.json` sur claudio.okonoma.com, aucune donnée envoyée) + bouton « Vérifier maintenant » dans Réglages → À propos. Une mise à jour disponible apparaît en tête du menu de la barre.
- **Troncature** : si la réponse atteint `max_tokens`, badge « Réponse tronquée » + bouton « Réessayer + » avec budget doublé.
- **Aperçus UI sans réseau** : `.build/release/Claudio --preview <mode> [--shot fichier.png]`, avec mode ∈ `panel`, `panel-streaming`, `panel-long`, `panel-error`, `panel-noselection`, `panel-free`, `panel-free-filled`, `palette`, `palette-filtre`, `palette-libre`, `settings`, `settings-prompts`, `settings-shortcuts`, `settings-about`. `--size small|normal|large|extraLarge` force la taille du texte du panneau. Aucun raccourci global ni item de barre de menus n'est installé, aucune clé n'est requise.
- **Test CLI sans UI** :

```bash
ANTHROPIC_API_KEY=sk-ant-… .build/release/Claudio --selftest "un texte avec des faute"
```

  Avec un second argument, c'est le chemin de l'action libre qui est exercé, consigne comprise :

```bash
ANTHROPIC_API_KEY=sk-ant-… .build/release/Claudio --selftest "Le chat dort." "Traduis en espagnol"
```

  Les deux impriment les jetons facturés et le coût correspondant.

## Limites connues

- Raccourcis simulés via keycodes physiques (positions C/V) : OK en QWERTY et AZERTY, pas en Dvorak/Bépo.
- « Lancer à l'ouverture de session » exige l'app packagée dans /Applications (pas `swift run`).

## Licence et soutien

Claudio est open source sous licence [MIT](LICENSE). Projet indépendant, non affilié à Anthropic. Claude est une marque d'Anthropic, PBC.

Si l'app vous rend service : [offrez-moi un café](https://buymeacoffee.com/gdhios) ☕
