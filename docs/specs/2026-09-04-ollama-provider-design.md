# Claudio — Support d'un moteur local (Ollama), moteur par action

- **Statut** : à implémenter (design validé le 2026-09-04)
- **Module** : `CLAUDIO`
- **Type** : nouveau sous-système (abstraction de fournisseur LLM)
- **Prérequis pour tester** : [Ollama](https://ollama.com) installé et lancé, avec au moins un modèle tiré (`ollama pull qwen2.5:14b`)

Ce document est autonome : il contient tout ce qu'il faut pour implémenter sans autre contexte.
Suivre les conventions du dépôt (voir §10). **Ne rien commiter sans revue** : livrer la branche, laisser Guillaume relire.

---

## 1. But & périmètre

Aujourd'hui Claudio ne parle qu'à l'API Anthropic. On ajoute la possibilité de faire exécuter
**chaque action** par un modèle **local Ollama** au lieu de Claude — pour les tâches à volume ou
sensibles à la confidentialité, sans rien envoyer sur le réseau, et gratuitement.

**Dans le périmètre**
- Un modèle par action peut être Claude **ou** Ollama (le système « modèle par action » existe déjà).
- Ollama joignable en **local et sur le réseau local** (URL configurable, défaut `localhost:11434`,
  éditable vers un autre Mac : `http://192.168.x.x:11434`). **Pas d'authentification.**
- Découverte des modèles installés via l'API Ollama, et un volet de réglages dédié.

**Hors périmètre (YAGNI — ne pas implémenter)**
- Authentification, Ollama Cloud, OpenRouter (la couture est conçue pour les accueillir plus tard,
  mais on ne les code pas).
- `ollama pull` automatique, modèle-par-app, changement du cycle capture/streaming/panneau/collage/historique.

---

## 2. Décisions arrêtées (ne pas rediscuter)

1. **Approche « moteur par action »** (pas de mode global, pas de repli automatique).
2. **Type de modèle : enum `ModelChoice`** (union typée `claude` / `ollama`). On **ne touche pas**
   à l'enum `ClaudioModel` (ses `rawValue` servent d'ID API et de clé de stockage, ses tarifs et sa
   gestion de température restent).
3. **Endpoint Ollama : API native `/api/chat` en NDJSON** (pas l'endpoint OpenAI-compatible). Raison :
   le natif renvoie `prompt_eval_count` / `eval_count` (le compteur de jetons continue de marcher) et
   `done_reason` (troncature), sans shim, en un appel.
4. **Réglages par action rétro-compatibles** : encodage préfixé `claude:` / `ollama:`, mais **lecture
   tolérante** des anciennes valeurs nues → `.claude(...)`. Les réglages existants ne doivent pas casser.
5. **Découverte des modèles** via `GET /api/tags`, avec repli champ libre + bouton « Tester la connexion ».
6. **Portée réseau : local + LAN, sans auth.**

---

## 3. Contrat de l'API Ollama (référence)

### 3.1 Chat en streaming — `POST {baseURL}/api/chat`

Requête :
```json
{
  "model": "qwen2.5:14b",
  "stream": true,
  "messages": [
    { "role": "system", "content": "<prompt système>" },
    { "role": "user",   "content": "<texte utilisateur, déjà balisé par ClaudioRequest>" }
  ],
  "options": { "num_predict": 512, "temperature": 0.2 }
}
```
- `num_predict` = budget de sortie (réutiliser `ClaudioRequest.maxTokens(...)` tel quel).
- `temperature` = `Constants.temperature` (0.2), toujours envoyée en local.

Réponse : **NDJSON** (un objet JSON par ligne, séparés par `\n`), pas du SSE :
```
{"model":"...","message":{"role":"assistant","content":"Bon"},"done":false}
{"model":"...","message":{"role":"assistant","content":"jour"},"done":false}
{"model":"...","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":26,"eval_count":298}
```
- **Texte** : concaténer `message.content` de chaque ligne `done:false`.
- **Ligne finale** `done:true` : porte `done_reason`, `prompt_eval_count` (jetons d'entrée),
  `eval_count` (jetons de sortie).
- **Troncature** : `done_reason == "length"`.
- **Erreur en flux** : une ligne `{"error":"..."}` peut apparaître → lever une erreur.

### 3.2 Erreurs HTTP
- Non-200 renvoie un JSON `{"error":"..."}`. Modèle absent → 404 `{"error":"model '…' not found, try pulling it first"}`.
- Ollama pas lancé → `URLError` (`.cannotConnectToHost` / connexion refusée) : à traduire en message clair.

### 3.3 Liste des modèles — `GET {baseURL}/api/tags`
```json
{ "models": [ { "name": "qwen2.5:14b", "model": "qwen2.5:14b", "size": 9000000000, "details": { } } ] }
```
Utiliser `models[].name` pour peupler le sélecteur.

---

## 4. Plan fichier par fichier

### Nouveaux fichiers

**`Sources/Claudio/AI/TextStreamClient.swift`**
```swift
/// Contrat commun à tous les fournisseurs de complétion en streaming.
/// Le modèle et la config (clé, URL) sont portés par l'init du client concret :
/// un client = un fournisseur + un modèle donné.
protocol TextStreamClient: Sendable {
    func streamCompletion(
        of text: String,
        system: String,
        maxTokens: Int,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> StreamResult
}
```
Y **déplacer** `StreamResult` (aujourd'hui imbriqué dans `AnthropicClient`) pour qu'il soit partagé.
Garder les champs : `text`, `truncated`, `inputTokens`, `outputTokens`.

**`Sources/Claudio/AI/ModelChoice.swift`**
```swift
/// Le modèle effectif d'une action : Claude (tarifé) ou un modèle local Ollama (gratuit).
enum ModelChoice: Sendable, Equatable {
    case claude(ClaudioModel)
    case ollama(model: String)   // ex. "qwen2.5:14b"

    func cost(inputTokens: Int, outputTokens: Int) -> Double  // 0 pour ollama ; délègue à ClaudioModel pour Claude
    var displayName: String
    var isLocal: Bool { if case .ollama = self { true } else { false } }

    // Encodage réglages (voir §5) :
    var storageValue: String                 // "claude:<id>" | "ollama:<id>"
    init?(storageValue: String)              // tolère les anciennes valeurs nues → .claude(...)
}
```

**`Sources/Claudio/AI/OllamaClient.swift`**
- `struct OllamaClient: TextStreamClient { let baseURL: URL; let model: String }`.
- `streamCompletion` : POST `baseURL/api/chat`, corps de §3.1, lecture ligne à ligne (`bytes.lines`),
  déléguée à un `OllamaStreamParser` interne (voir ci-dessous), même architecture que `AnthropicClient`.
- `static func makeBody(text:system:model:maxTokens:) -> [String: Any]` (verrouillable en test comme
  l'équivalent Anthropic).
- `struct OllamaStreamParser` (analogue à `AnthropicClient.StreamParser`) : `mutating func consume(line:)
  -> String?`, accumule le texte, lit `done`/`done_reason`/`prompt_eval_count`/`eval_count`, expose `result`.
- Erreurs : `enum OllamaError: LocalizedError` avec au minimum `notReachable(url:)`,
  `http(status:message:)`, `stream(String)`. `notReachable` →
  `loc("Ollama ne répond pas sur \(url) — est-il lancé ?", en: "Ollama isn't responding at \(url) — is it running?")`.
- Découverte : `func availableModels() async -> [String]` (GET `/api/tags`, renvoie `[]` si injoignable).

### Fichiers édités

**`AI/AnthropicClient.swift`**
- Conformer à `TextStreamClient`. Ajouter `let model: ClaudioModel` à l'init.
- `streamCompletion` **perd le paramètre `model`** (lit `self.model`).
- **Ne pas** changer la signature de `static func makeBody(text:system:model:maxTokens:)` : elle est
  verrouillée par `AnthropicClientTests` (lignes 146/164). `streamCompletion` l'appelle avec `self.model`.
- `StreamResult` n'est plus déclaré ici (il vient de `TextStreamClient.swift`).

**`AI/ClaudioModel.swift`** (extension `ClaudioAction`)
- `defaultModel` reste `ClaudioModel` (défauts Claude inchangés).
- `var model: ModelChoice` (effectif) : lit le `ModelChoice` stocké, sinon `.claude(defaultModel)`.

**`AI/ClaudioRequest.swift`**
- `let model: ClaudioModel` → `let model: ModelChoice`. Tous les constructeurs suivent
  (l'action libre `free(...)` : `model: ModelChoice = .claude(.haiku45)`).
- Le reste (`system`, `userMessage`, `budget`, `maxTokens`) est **fournisseur-agnostique et réutilisé tel quel**.

**`Coordinator/CorrectionCoordinator.swift`** — méthode `stream()`
- Remplacer la construction en dur d'`AnthropicClient` par une sélection selon `request.model` ;
  le garde `.missingKey` ne concerne **que** Claude :
```swift
let client: TextStreamClient
switch request.model {
case .claude(let m):
    guard let key = KeychainStore.currentAPIKey() else { session.phase = .missingKey; return }
    client = AnthropicClient(apiKey: key, workspaceID: AppSettings.currentWorkspaceID(), model: m)
case .ollama(let id):
    client = OllamaClient(baseURL: AppSettings.ollamaBaseURL, model: id)
}
session.beginStreaming()
let result = try await client.streamCompletion(
    of: request.userMessage(forText: session.originalText),
    system: request.system,
    maxTokens: request.maxTokens(forText: session.originalText, multiplier: session.maxTokensMultiplier)
) { @MainActor piece in session.appendStreamed(piece) }
```
- `CostLedger.shared.record(model: request.model, …)` prend désormais un `ModelChoice` (voir plus bas).

**`Storage/AppSettings.swift`**
- Nouveau : `static var ollamaBaseURL: URL` (défaut `Constants.ollamaDefaultURL`, stocké en `String`
  dans `UserDefaults`, validé, repli sur le défaut si vide/invalide).
- `customModel(for:)` / `setCustomModel(_:for:)` : type `ModelChoice?` au lieu de `ClaudioModel?`.
  - Lecture : décoder via `ModelChoice(storageValue:)` (tolère l'ancien format nu, cf. §5).
  - Écriture : si le choix vaut `.claude(action.defaultModel)` → **supprimer la clé** (retour au défaut,
    comportement actuel préservé) ; sinon stocker `choice.storageValue`.

**`Storage/CostLedger.swift`**
- `record(model: ModelChoice, inputTokens:outputTokens:at:)`. Un appel **local n'est pas une dépense** :
  retour anticipé pour `.ollama` (ni montant, ni incrément du compteur d'actions facturées). Pour `.claude`,
  comportement identique à aujourd'hui.

**`UI/SettingsView.swift`**
- Nouveau volet **« Local (Ollama) »** (nouvelle valeur de `SettingsSection`) : champ URL (lié à
  `AppSettings.ollamaBaseURL`), bouton « Tester la connexion » (appelle `OllamaClient.availableModels()`),
  affichage « connexion OK — N modèles détectés » / message d'échec, et la liste des modèles détectés.
- `PromptsPane` — sélecteur par action (aujourd'hui `Picker` sur `ClaudioModel.allCases`, ~l.295-306) :
  devient un menu **groupé** « Claude » (les 3 modèles) + « Local (Ollama) » (modèles détectés).
  Le `@State` passe de `ClaudioModel` à `ModelChoice`. Si Ollama est injoignable / aucun modèle : groupe
  vide avec un renvoi « Configure Ollama dans l'onglet Local ». Le repère de coût affiche
  **« Gratuit (local) »** quand l'action pointe sur un modèle Ollama.
- La section « Modèle » informative de `GeneralPane` (~l.137) : mentionner que le local est gratuit.

**`Support/Constants.swift`**
- `static let ollamaDefaultURL = URL(string: "http://localhost:11434")!`.

---

## 5. Rétro-compatibilité de l'encodage (critique)

`ModelChoice.storageValue` et `init?(storageValue:)` :

- **Écriture** : `.claude(m)` → `"claude:" + m.rawValue` ; `.ollama(id)` → `"ollama:" + id`.
- **Lecture** — découper sur le **premier `:` seulement** (un ID Ollama contient des `:`, ex.
  `qwen2.5:14b`) :
  - préfixe `claude:` → `ClaudioModel(rawValue: reste)` mappé en `.claude(...)` ;
  - préfixe `ollama:` → `.ollama(model: reste)` ;
  - **sinon** (aucun préfixe reconnu) : tenter `ClaudioModel(rawValue: valeur entière)` → `.claude(...)`.
    C'est le **cas hérité** : les réglages actuels stockent `"claude-haiku-4-5"` nu. Les IDs Claude
    contiennent des `-` mais jamais de `:`, donc aucune ambiguïté avec le schéma `ollama:`.

Un test doit verrouiller les trois cas (préfixé Claude, préfixé Ollama avec `:` dans l'ID, hérité nu).

---

## 6. Tests exigés (aucun réseau)

**Nouveaux**
- `OllamaClientTests` :
  - `OllamaStreamParser` sur une transcription NDJSON figée : accumulation du texte, troncature via
    `done_reason == "length"`, jetons in/out lus sur la ligne finale, ligne `{"error":…}` → throw.
    (Miroir de `AnthropicClientTests` pour le `StreamParser`.)
  - `OllamaClient.makeBody` : présence de `num_predict`, `stream:true`, messages system+user, `options.temperature`.
- `ModelChoiceTests` : `cost` (ollama = 0, claude délègue à `ClaudioModel`) ; aller-retour
  `storageValue` / `init?(storageValue:)` pour les 3 cas de §5.

**À mettre à jour (sinon compilation cassée)**
- `CostLedgerTests` : les appels `record(model:)` passent maintenant un `ModelChoice` → envelopper
  l'existant en `.claude(...)`, et ajouter un cas `.ollama` qui **n'incrémente pas** le compteur.
- `ClaudioRequestTests` (l.55, `XCTAssertEqual(request.model, action.model)`) : reste valide dès lors
  que `ModelChoice: Equatable` — vérifier la compilation.

**Doivent rester verts sans modification**
- `AnthropicClientTests` (`StreamParser` + `makeBody`) : c'est pourquoi `makeBody` ne change pas de signature.

---

## 7. Build & vérification

```bash
Scripts/build_app.sh          # build de l'app
swift test                    # suite de tests
```
Voir `TESTING.md` pour le détail. Vérification manuelle (Ollama lancé, un modèle tiré) :
1. Régler une action (ex. *Corriger*) sur le modèle local dans Réglages → Prompts.
2. Sélectionner du texte, déclencher l'action : le résultat s'écrit en streaming puis se colle.
3. Le compteur de dépense du jour **ne bouge pas** pour cet appel.
4. Arrêter Ollama, re-déclencher : message d'erreur clair « Ollama ne répond pas… ».
5. Vérifier qu'un réglage d'action **antérieur** (valeur nue) se charge toujours en Claude.

---

## 8. Definition of Done

- [ ] Une action peut être réglée sur un modèle Claude **ou** Ollama, indépendamment des autres.
- [ ] `localhost` par défaut, URL éditable pour viser un autre Mac du LAN ; « Tester la connexion » liste les modèles.
- [ ] Streaming, panneau, collage, historique **identiques** quel que soit le moteur.
- [ ] Appels locaux exclus du compteur de dépense ; repère « Gratuit (local) » à la sélection.
- [ ] Réglages hérités (valeurs nues) chargés sans erreur.
- [ ] Erreur claire si Ollama est injoignable ou le modèle absent.
- [ ] `swift test` vert ; `AnthropicClientTests` inchangé ; nouveaux tests présents.
- [ ] Aucun secret, aucune donnée envoyée ailleurs que vers l'URL Ollama configurée.

---

## 9. Ordre d'implémentation suggéré

1. `TextStreamClient.swift` (+ déplacer `StreamResult`), conformer `AnthropicClient` (model → init).
2. `ModelChoice.swift` (+ encodage §5) et ses tests.
3. Propager `ModelChoice` : `ClaudioRequest`, `ClaudioAction.model`, `AppSettings`, `CostLedger` (+ MAJ tests).
4. `OllamaClient.swift` (+ `OllamaStreamParser`, `availableModels`) et ses tests.
5. Câbler `CorrectionCoordinator.stream()`.
6. UI : `Constants.ollamaDefaultURL`, volet « Local (Ollama) », sélecteur groupé de `PromptsPane`.
7. Vérification manuelle §7, revue.

Chaque étape doit compiler et garder la suite verte (commits atomiques, mais **pas de push/merge sans revue**).

---

## 10. Conventions du dépôt à respecter

- Identifiants en anglais ; **commentaires et chaînes UI en français**, voix factuelle et concise du dépôt
  (regarder les fichiers existants comme modèle).
- **Toute chaîne visible par l'utilisateur** passe par `loc("…", en: "…")` (bilingue FR/EN).
- Petits fichiers à responsabilité unique, un `enum`/`struct` par sujet, comme l'existant
  (`ClaudioAction`, `ClaudioModel`, `Budget`, `Origin`).
- Séparer transport réseau et parsing (le parseur est un type valeur testable, comme `StreamParser`).
- Ne rien envoyer sur le réseau hors de l'URL Ollama configurée et de l'API Anthropic existante.
