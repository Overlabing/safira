# Safira : plan du banc de conformité des extensions Chrome

Statut : cadrage. Rédigé le 2026-11-03 sur macOS 27.0.1 (26A434), Xcode 27.1, Apple M4, 16 Go de RAM.

Ce document est un plan. Il ne contient aucun code produit.

Légende utilisée partout :

- **[É]** établi, avec la source ;
- **[D]** déduit, avec le raisonnement ;
- **[NV]** non vérifié.

---

## 0. En bref

1. Le critère « couverture des ~68 namespaces » est **mal posé** comme critère de décision (§1.2). Le critère principal doit être : **les 6 extensions cibles passent leurs scénarios sur l'architecture choisie**. Viennent en second : une couverture **pondérée par l'usage réel**, puis la matrice brute des API, qui sert de diagnostic.
2. Le WebKit livré avec ce Mac (branche `safari-7625`) n'expose **ni offscreen, ni sidePanel, ni bookmarks**. Offscreen n'existe que sur main, depuis le 2026-08-08. Le cadrage surestime donc ce que donnerait l'option A aujourd'hui (§1.1).
3. L'**API publique WKWebExtension suffit probablement à combler une grande partie de l'écart dans l'app**, sans fork [D] :
   - `WKWebExtensionContext.webViewConfiguration` permet d'ouvrir des pages d'extension (offscreen, side panel) dans des WKWebView gérées par l'app ;
   - `connectNative` / `sendNativeMessage` arrivent au délégué de l'app, qui peut servir de pont pour des namespaces « shim » ;
   - `WKContentWorld` et `WKUserScript` couvrent userScripts ;
   - `WKWebsiteDataStore.proxyConfigurations` couvre proxy, sans PAC.

   C'est **l'hypothèse n° 1 à valider** par un prototype avant toute décision sur B.
4. L'option B, un WebKit embarqué, me paraît **mal avisée comme cible produit** :
   - le projet n'a **aucun précédent** de distribution grand public trouvé ;
   - il faudrait abandonner les entitlements restreints (sandbox affaiblie, délégation TCC caméra et micro) ;
   - les ajouts internes d'Apple (`WebKitAdditions`) sont absents de l'open source ;
   - il faudrait suivre soi-même les correctifs de sécurité, soit une version de Safari toutes les 4 à 8 semaines.

   B reste utile comme **instrument de mesure** : voir ce que main apportera au WebKit système, et chiffrer un patch.
5. **Blocage pratique** : il reste 30 Go libres sur ce disque. Un build de WebKit main n'y tient pas : le dépôt fait déjà ~12,6 Gio [É], et il faut viser ≥ 100 Go [D]. Il faut décider avant la phase B (§9, Q1).

---

## 1. Vérification du cadrage

### 1.1 Affirmations reçues, une par une

**« Chrome documente 85 namespaces, dont 17 ChromeOS-only, soit ~68 desktop »**

**Confirmé [É].** Source : [developer.chrome.com/docs/extensions/reference/api](https://developer.chrome.com/docs/extensions/reference/api), page relevée pour Chrome 151 à 153. Liste des 68 en annexe A.

**« WebKit main implémente ~25 namespaces d'après les IDL »**

**Partiellement infirmé [É].**

- Le dossier `Source/WebKit/WebProcess/Extensions/Interfaces` contient 37 IDL. Plusieurs ne sont pas des namespaces : `Event`, `Port`, `StorageArea`, `WebPage*`, et `Test`, qui est réservé aux tests.
- `sidebarAction` (Firefox) existe aussi.
- Surtout, dans `Source/WTF/wtf/PlatformEnableCocoa.h` sur main :
  - `ENABLE_WK_WEB_EXTENSIONS_SIDEBAR` vaut `0 && …` ;
  - `ENABLE_WK_WEB_EXTENSIONS_BOOKMARKS` vaut `0 && …`.

  **sidePanel et bookmarks sont compilés mais désactivés**, même sur main.

**« Présence ≠ complétude ; main ≠ ce que livre macOS »**

**Confirmé, et l'écart est concret [É].**

- Le WebKit système est en version 22625.1.29.11.28. La branche `safari-7625.1.29.11-branch` correspond très probablement, mais le lien version ↔ branche est [D].
- Cette branche n'a **pas d'IDL Offscreen**. Offscreen est arrivé sur main par le commit « Web Extensions: Add support for the offscreen API » du 2026-08-08.
- Permissions acceptées par cette branche (`WebExtension::supportedPermissions`) : activeTab, alarms, clipboardWrite, contextMenus, cookies, declarativeNetRequest (+Feedback, +WithHostAccess), menus, nativeMessaging, notifications, scripting, storage, tabs, unlimitedStorage, webNavigation, webRequest.
- Main ajoute offscreen. On y trouve aussi `#include <WebKitAdditions/WebExtensionSupportedPermissionsAdditions.h>`, qui ne s'applique que sous `USE(APPLE_INTERNAL_SDK)`.
- **Conséquence : un build open source de main peut avoir moins de fonctions que le WebKit d'Apple.** Neuf fichiers du code d'extensions incluent des `WebKitAdditions` (recherche de code GitHub).

**Classes publiques WKWebExtension*, macOS 15.4+, plusieurs contrôleurs**

**Confirmé [É]** dans les en-têtes du SDK macOS 27 :

- `WKWebExtensionControllerConfiguration configurationWithIdentifier:` permet un stockage persistant par UUID ;
- `defaultWebsiteDataStore` existe par contrôleur.

Deux profils étanches sont donc **plausibles**. L'étanchéité réelle reste à tester (§2.4, test P1).

**« Orion annonce ~70 % des API »**

**Confirmé que Kagi l'annonce [É]**, sur [help.kagi.com/orion/browser-extensions/macos-extensions.html](https://help.kagi.com/orion/browser-extensions/macos-extensions.html). Le dénominateur n'est pas publié, et un fil d'utilisateurs le réclame : [orionfeedback.org/d/1650](https://orionfeedback.org/d/1650-establish-a-separate-dashboard-or-table-for-webextensions-api-support).

Le chiffre est **inexploitable comme référence**. On ne sait pas non plus si Orion s'appuie sur WKWebExtension ou sur sa propre implémentation, antérieure [NV].

**« WKURLSchemeHandler n'intercepte pas http/https »**

**Non revérifié dans ce passage [NV]**, mais c'est cohérent avec la documentation d'Apple (`setURLSchemeHandler` lève une exception pour les schémas gérés par WebKit). La conclusion tient : le blocage réseau passe par DNR ou les content rule lists.

**« Chrome MV3 a retiré le webRequest bloquant »**

**À nuancer [É].** Le webRequest bloquant reste disponible pour les extensions **installées par policy** :

- [webRequest reference](https://developer.chrome.com/docs/extensions/reference/api/webRequest) ;
- dans `_permission_features.json`, `webRequestBlocking` a une entrée `location: "policy"`.

Pour les extensions grand public, c'est bien DNR.

**« Bug WebKit 290922 corrigé sur main le 2026-10-28 »**

**Cohérent [É].** L'API REST de bugs.webkit.org renvoie RESOLVED FIXED, dernière modification 2026-10-29T06:19Z. Le correctif n'est donc pas dans macOS 27.0.1 [D].

**WebKit 271472 (userScripts) et 276833 (sidePanel)**

**[É]** : le premier est NEW et inactif depuis 2025-10 ; le second est ASSIGNED et inactif depuis 2024-07. Il ne faut pas compter sur Apple pour ces deux-là à court terme.

### 1.2 Ce qui contredit le cadrage

**a) « 68 namespaces » n'est pas un bon dénominateur.**

Il mélange des choses de nature différente :

- des namespaces **de types seuls** (`types`, `extensionTypes`, `events`) ;
- des API **liées aux DevTools de Chrome** (`devtools.performance`, `devtools.recorder`), sans équivalent dans Web Inspector ;
- des API **dev-channel** (`dns`, `processes`) et sur **allowlist** (`mimeHandler`) ;
- des API **policy/entreprise** (`enterprise.hardwarePlatform`) ;
- des API **liées à Google** (`gcm`, `instanceID`, `identity.getAuthToken`).

Et il **ignore ce qui casse réellement les extensions** :

- **Clés de manifest** : `externally_connectable`, `sandbox.pages`, `side_panel`, `key` (et donc l'ID d'extension), CSP, `world: "MAIN"`.
- **API web de la plateforme** :
  - WebHID, utilisé par Ready Wallet/Argent X pour Ledger (`"hid"` dans son manifest) ;
  - WebUSB ;
  - WebAuthn dans un navigateur tiers, qui exige l'entitlement `com.apple.developer.web-browser.public-key-credential`.
- **Sémantique** : cycle de vie du service worker, ports, `sender`, promesses ou callbacks.

**Proposition** : trois niveaux de mesure (§5).

**b) Le cadrage oppose « WebKit seul » à « fork ».** Il oublie la troisième voie, la plus probable : **WebKit système + shims dans l'app via l'API publique** (§6).

**c) L'option B présentée comme une alternative de niveau égal.** Elle ne l'est pas : voir §3.3 et §0.4.

**d) « Le WebKit système » n'est pas une cible fixe.** Il dépend de la version de macOS de l'utilisateur. La version minimale de macOS supportée par Safira **fait partie du critère** (§9, Q3).

---

## 2. Source de vérité des API (côté Chrome)

### 2.1 Où sont les schémas aujourd'hui [É]

Décompte via `gh api repos/chromium/chromium/contents/...` le 2026-11-03 :

| Dossier | Contenu |
|---|---|
| `extensions/common/api/` | 58 `.webidl`, 34 `.json` |
| `chrome/common/extensions/api/` | 30 `.webidl`, 48 `.json`, 15 `.idl` (ancien format) |
| `chrome/common/chromeos/extensions/api/` | API ChromeOS |
| `_api_features.json`, `_permission_features.json`, `_manifest_features.json` | Dans chaque dossier. Ils donnent `channel`, `platforms`, `contexts`, `min_manifest_version` et `location`. Documentation : `chrome/common/extensions/api/_features.md` |

Le cadrage parlait de `.json|.idl`. **La migration vers `.webidl` est en cours**, et le format est hétérogène.

### 2.2 Outil d'extraction

Chromium contient déjà un compilateur, `tools/json_schema_compiler/` [É]. On y trouve :

- `json_schema.py`, `idl_schema.py`, `web_idl_schema.py` ;
- `model.py` ;
- `ts_definition_generator.py`, `feature_compiler.py` ;
- `web_idl_diff_tool.py`.

Les dépendances (`tools/idl_parser`, `ppapi/generators`, ply) sont [D] et restent à confirmer à l'exécution.

**Étapes :**

1. Faire un **checkout partiel** de Chromium, sans clone complet. Ne prendre que `tools/json_schema_compiler`, `tools/idl_parser`, `ppapi/generators`, `third_party/ply`, les trois dossiers d'API et `extensions/common/api/_*features*.json` :

   ```sh
   git clone --depth 1 --filter=blob:none --sparse https://chromium.googlesource.com/chromium/src
   git sparse-checkout set <dossiers listés ci-dessus>
   ```

   Taille attendue : quelques centaines de Mo [NV].

2. Écrire un script `extract_chrome_api.py` qui charge chaque schéma via le `model` de Chromium. Il émet `chrome-api.json` avec, pour chaque élément :
   - namespace, fonctions (paramètres, optionnels, valeur de retour ou callback, support des promesses), événements (paramètres du listener, filtres), propriétés, types ;
   - les champs joints depuis les fichiers `_features` : canal, plateformes, contextes (background, content script, page web), permission requise, version minimale de manifest.

3. Prévoir le **plan de repli** si le compilateur n'est pas extractible seul : [GoogleChrome/chrome-types](https://github.com/GoogleChrome/chrome-types). Il est généré chaque jour depuis les schémas et produit des `.d.ts` [É]. On le joint aux fichiers `_features` pour avoir canal et plateformes, que chrome-types n'expose pas [É, d'après son README].

4. **Figer** une révision de Chromium (hash du commit) dans le rapport.

**Recoupement** : [mdn/browser-compat-data `webextensions/api`](https://github.com/mdn/browser-compat-data/tree/main/webextensions/api) a une colonne Safari [É]. Elle couvre moins de namespaces, pas offscreen par exemple. Ses données Safari sur webRequest se contredisent. Elle ne sert que de **contrôle croisé**, jamais de vérité.

### 2.3 Côté WebKit

**Deux sources, qui ne se valent pas :**

- **Statique**, pour B seulement : un parseur des IDL de `Source/WebKit/WebProcess/Extensions/Interfaces/*.idl`. Il tient compte des attributs `Conditional=…` résolus depuis `PlatformEnableCocoa.h` et de `MainWorldOnly` (absent des content scripts), et s'exécute sur main et sur la branche `safari-7625*`. Il donne une liste de membres déclarés, pas implémentés.
- **Dynamique, qui fait foi** : la sonde exécutée dans le WebKit réellement chargé (§3). C'est la seule mesure qui capte les `WebKitAdditions`, les stubs et les membres déclarés mais non câblés.

### 2.4 Comparaison

On fait une jointure `chrome-api.json` × `webkit-probe-<cible>.json` au niveau de chaque membre : fonction, événement, propriété, et paramètre ou type quand c'est testable. Le diff produit la matrice du §5.

---

## 3. Conception du banc

### 3.1 Composants

```
bench/
  schema/            extract_chrome_api.py → chrome-api.json (figé, versionné)
  probe-gen/         génère l'extension de sonde depuis chrome-api.json
  probe-ext/         extension MV3 générée + tests comportementaux écrits à la main
  host/              SafiraBench.app (Swift, AppKit) : charge une extension dans un WKWebExtensionController
  collector/         petit serveur HTTP local (dans l'app hôte) qui reçoit les résultats
  baseline/          lanceur Chrome for Testing avec la même extension
  report/            jointure + rendu (Markdown + JSON)
```

### 3.2 App hôte (SafiraBench.app)

**Mode A** : lien contre le WebKit système. Cible de déploiement macOS 27 (sinon une autre version, voir Q3).

**Ce que l'app implémente :**

- Les protocoles `WKWebExtensionWindow` et `WKWebExtensionTab`, de façon réelle mais minimale : une fenêtre, des onglets dans une WKWebView. Sans cela, `tabs`, `windows`, `scripting.executeScript` et `captureVisibleTab` (via `takeSnapshotUsingConfiguration:`) ne sont pas testables [É, en-têtes du SDK].
- Le délégué `WKWebExtensionControllerDelegate`, avec toutes les méthodes publiques du SDK 27 :
  - `openWindows` / `focusedWindow` ;
  - `openNewWindow` / `openNewTab` / `openOptionsPage` ;
  - `promptForPermissions` / `promptForPermissionToAccessURLs` / `promptForPermissionMatchPatterns` ;
  - `didUpdateAction` / `presentPopupForAction` ;
  - `sendMessage:toApplicationWithIdentifier:` / `connectUsingMessagePort:`.

  Les invites de permission sont **scriptables** : accepter, refuser ou expirer selon le scénario.

- Les **notifications d'état** (`didOpenTab`, `didActivateTab`, `didChangeTabProperties`, …) envoyées au contrôleur pour tester les événements `tabs.on*` et `windows.on*`.
- **Deux contrôleurs** (Pro et Perso), chacun avec son `configurationWithIdentifier:` et son `WKWebsiteDataStore dataStoreForIdentifier:`.
- Un **mode CLI** : `SafiraBench --extension <dir> --profile <p> --scenario <id> --out <json>`. L'exécution est sans intervention, avec une fenêtre visible, car certaines API exigent une fenêtre clé.
- Un **pont de messagerie native compatible Chrome** :
  1. lire `~/Library/Application Support/<…>/NativeMessagingHosts/<name>.json` ;
  2. vérifier `allowed_origins` ;
  3. lancer l'exécutable avec l'origine en argv[1], comme Chrome ;
  4. relayer le framing stdio (longueur sur 4 octets + JSON) vers le `WKWebExtensionMessagePort`.

  Verrou en dépend (§4.1).

**Mode B** : même code, lancé contre `WebKitBuild/Release` (§3.3).

### 3.3 Mode B : build de WebKit main

**Établi** (sources : [webkit.org/building-webkit](https://webkit.org/building-webkit/), [docs.webkit.org BuildOptions](https://docs.webkit.org/Build%20&%20Debug/BuildOptions.html), `Tools/Scripts/webkitdirs.pm`, `Tools/Scripts/run-webkit-app`) :

- `webkitdirs.pm` exige Xcode ≥ 26.2. Xcode 27.1 convient.
- Prérequis : `xcodebuild -downloadComponent MetalToolchain`.
- Build : `Tools/Scripts/build-webkit --release`, avec sortie dans `WebKitBuild/`.
- Lancement : `Tools/Scripts/run-webkit-app <App>`. Il ajoute en tête `DYLD_FRAMEWORK_PATH`, `__XPC_DYLD_FRAMEWORK_PATH` et `DYLD_LIBRARY_PATH`. La variante `__XPC_` permet aux services XPC (WebContent, Networking, GPU) de charger les frameworks construits.
- Les builds avec SDK public sont un cas prévu, via le basculement `USE_INTERNAL_SDK`.
- Il existe un mode `WK_RELOCATABLE_FRAMEWORKS=YES` (`RelocatableFrameworksLinkerFlags.xcconfig`) : `@executable_path/...`, pour embarquer.
- Taille du dépôt GitHub : ~12,6 Gio.

**Non vérifié :**

- durée du build sur M4 : je n'ai pas de source, l'ordre de grandeur est de 1 à 3 h [D] ;
- taille de `WebKitBuild` ;
- **sur 16 Go de RAM, risque de swap pendant l'édition de liens** [D].

**Espace disque : bloquant ici.**

- Il reste 30 Go libres, dont 14 Go occupés par `DerivedData` et récupérables.
- Il faut ≥ 100 Go, ou un SSD externe [D].
- Un clone partiel réduit le `.git` : `git clone --filter=blob:none` ou `--depth 1` [D].

**Différences avec la WKWebView publique** [D, à confirmer au premier lancement] :

- `run-webkit-app` dépend de variables `DYLD_*`. Elles sont ignorées sous hardened runtime sans `com.apple.security.cs.allow-dyld-environment-variables` / `disable-library-validation`. SafiraBench doit donc être signé en ad hoc, **sans hardened runtime**, en mode B.
- Le service WebContent « Development » porte `disable-library-validation` (`Source/WebKit/Scripts/process-entitlements.sh`) [É].
- Risque arm64/arm64e : un commentaire du [bug 236829](https://bugs.webkit.org/show_bug.cgi?id=236829) l'évoque [NV].
- SPI : le banc n'en a pas besoin pour la mesure. En option, `_setTestingMode:` (`WKWebExtensionControllerPrivate.h`) active `browser.test`, mais **aussi des stubs d'API non supportées**, ce qui fausserait la mesure (voir §3.4).

**Raccourci à tester avant tout build** [NV] : Safari Technology Preview, c'est-à-dire main avec les `WebKitAdditions`, signé par Apple.

1. Vérifier si ses frameworks peuvent être chargés par SafiraBench via `DYLD_FRAMEWORK_PATH`.
2. Si oui, on obtient une « préversion du futur WebKit système » sans build. C'est souvent la question réellement utile : « qu'apportera macOS 27.x/28 ? ».

**Faisabilité de la distribution d'un WebKit embarqué :**

| Point | Statut |
|---|---|
| Précédent d'une app tierce **distribuée** embarquant son WebKit sur macOS | **Aucun trouvé**. Playwright embarque un WebKit patché, mais c'est un outil de test lancé via `DYLD_*`, pas une app notariée grand public [É : `browser_patches/webkit/pw_run.sh`]. Un fil Apple, [forum 700648](https://developer.apple.com/forums/thread/700648), décrit la même difficulté. |
| JIT | `com.apple.security.cs.allow-jit` reste disponible sans privilège [É, process-entitlements.sh]. Perdus : `verified-jit` et `jit-write-allowlist`, donc un durcissement moindre. |
| Sandbox | Avec un SDK public, `WK_USE_RESTRICTED_ENTITLEMENTS=NO`. On perd `rootless.storage.WebKitWebContentSandbox`, le filtrage de messages et les entitlements d'état de sandbox [É, Base.xcconfig + process-entitlements.sh ; [bug 218982](https://bugs.webkit.org/show_bug.cgi?id=218982)]. **La sécurité est inférieure à celle du WebKit système.** |
| TCC (caméra, micro, partage d'écran via le processus GPU) | Délégation perdue sans entitlement restreint [É, script]. L'impact réel sur getUserMedia est [NV]. |
| Passkeys / WebAuthn | `com.apple.developer.web-browser.public-key-credential` doit être demandé à Apple, pour A comme pour B [É, doc Apple]. Avec B, le fonctionnement depuis un WebKit non Apple est [NV]. |
| FairPlay / Apple Pay | Pas de voie identifiée pour un tiers [D]. Netflix et autres vidéos DRM risquent de ne pas marcher en B. |
| Notarisation | Techniquement plausible si tout est signé avec le Developer ID et sans entitlement privé [D, NV]. |
| Maintenance | Apple publie une version de Safari toutes les 4 à 8 semaines [É, [support.apple.com/100100](https://support.apple.com/en-us/100100)]. Les branches `safari-*` et `apple-security` existent [É]. Il faudrait rebaser, rebuilder (des heures) et redistribuer à chaque fois. **C'est un poste à temps partiel permanent** [D]. |
| Taille | ~quelques centaines de Mo ajoutés à l'app [NV]. |

**Ce que je n'ai pas pu établir** :

- un exemple concret d'app notariée avec WebKit embarqué ;
- le comportement d'AMFI face aux services XPC re-signés ;
- l'état du mode relocatable en 2026 ;
- la façon dont STP est empaqueté.

**Si B reste envisagé, il faut une preuve de faisabilité dédiée** : une app de démonstration avec WebKit main embarqué, signée Developer ID, notariée, puis lancée sur un compte macOS propre, avec Gatekeeper actif.

### 3.4 Extension de sonde

**Génération** : `probe-gen` lit `chrome-api.json` et génère, pour chaque membre :

| Niveau | Test | Résultat |
|---|---|---|
| L0 existence | `typeof chrome.<ns>?.<membre>` dans **chaque contexte** : service worker, page d'extension, content script ISOLATED, MAIN, offscreen, popup | présent / absent |
| L1 forme | Pour une fonction : arité, retour d'une promesse sans callback (MV3), rejet propre sur des arguments invalides avec un message Chrome-like. Pour un événement : présence de `addListener`, `removeListener`, `hasListener` | conforme / divergent |
| L2 appel minimal | Appel avec des arguments valides générés depuis le schéma, quand l'appel est sûr (lecture seule). La liste d'exclusion des appels dangereux est écrite à la main | résout / rejette « not implemented » / **se bloque** (timeout de 3 s) |
| L3 comportement | Tests écrits à la main pour les namespaces prioritaires : ceux utilisés par les 6 extensions, plus le top du corpus | pass / fail / divergent par assertion |

**Permissions** : le manifest de la sonde déclare toutes les permissions desktop.

- Celles que WebKit ignore sont **relevées** dans `WKWebExtensionContext.errors`, à capturer.
- Une deuxième variante déclare les permissions en `optional_permissions` pour tester `permissions.request`.

**Canal de rapport.** Retenu : **`fetch()` POST vers le collecteur HTTP local de l'app hôte** (`http://127.0.0.1:<port>`, avec `host_permissions`).

Justification :

- c'est le seul canal qui **ne dépend d'aucune API d'extension sous test** ;
- il marche depuis le service worker, les pages et l'offscreen ;
- il marche aussi à l'identique dans Chrome pour la ligne de base.

Les content scripts rapportent via `runtime.sendMessage` vers le service worker, avec un repli sur `fetch` direct si ce canal est lui-même en échec, ce qui est alors noté.

Canaux écartés :

- **`runtime.sendNativeMessage` / `connectNative`** vers le délégué (`sendMessage:toApplicationWithIdentifier:`, public [É]). Sert de **canal secondaire et de test en soi**. Ce n'est pas le canal principal : si nativeMessaging casse, tout le rapport disparaît, et il n'existe pas dans la ligne de base Chrome sans hôte natif.
- **`WKScriptMessageHandler`**. Inutilisable depuis un service worker. Pour les pages d'extension, il faudrait toucher à `context.webViewConfiguration.userContentController`, qui est en lecture seule. Ce canal mesurerait l'app, pas l'extension.
- **`browser.test` via `_setTestingMode:`** (SPI) [É, `WKWebExtensionControllerPrivate.h` sur safari-7625]. Le mode active des **stubs d'API non supportées** et fausse le niveau L0. À n'utiliser qu'en exécution de diagnostic séparée, marquée comme telle.

**Cas non triviaux (tests L3 dédiés) :**

| Sujet | Méthode |
|---|---|
| Content script `world: "MAIN"` à `document_start` | Le manifest est analysé par WebKit (`contentScriptsMainManifestKey`) [É]. Test : le script MAIN pose un marqueur sur `navigator.credentials.get` **avant** l'exécution du premier script inline de la page. La page de test vérifie qu'il est intercepté. Variantes : `all_frames`, iframe cross-origin, `about:blank`, `scripting.registerContentScripts({world:"MAIN"})` et `executeScript({world:"MAIN"})`. |
| Service worker de fond MV3 | `type: "module"` avec import statique, `importScripts` en classique, IndexedDB dans le SW (Verrou l'utilise). Mise en sommeil puis réveil sur un événement (alarm, message, onConnect) : on mesure si l'état est perdu et si l'événement est livré. `runtime.onStartup` et `onInstalled` (raisons). Le délai de mise en sommeil, mesuré et non supposé, se compare à Chrome (30 s d'inactivité). |
| Ports longue durée | `runtime.connect` page ↔ SW, `tabs.connect`, `connectNative`. On vérifie `onDisconnect` des deux côtés, la fermeture d'onglet, le réveil du SW par un port et la survie au-delà de 5 min, ainsi que l'ordre et la taille maximale des messages. |
| Popup | `action.openPopup()` sans geste utilisateur et après un geste. `presentPopupForAction` côté app. `windows.create({type:"popup"})`. La popup est fermée pendant un appel en cours. |
| Permissions optionnelles | `permissions.request` / `contains` / `remove` ; `onAdded` et `onRemoved`. L'invite est scriptée et répond accepter, refuser ou expirer. On vérifie l'exigence d'un geste utilisateur et `activeTab` après clic sur l'action. |
| DNR avec règles réelles | Pages de test servies par le collecteur, vers un sous-domaine local (via `/etc/hosts` ou un serveur `*.localhost`). Règles statiques (rulesets activables), dynamiques, de session, `regexFilter`, `redirect` (URL et extensionPath), `modifyHeaders` (requête et réponse, **en-tête personnalisé**, cf. 290922), `allowAllRequests`, `initiatorDomains`, `resourceTypes`, priorités. On mesure aussi `getMatchedRules` et les limites : nombre de règles, `isRegexSupported`. Vérité terrain : le collecteur journalise ce qu'il reçoit réellement. |
| Offscreen | `offscreen.createDocument` (raisons DOM_PARSER, CLIPBOARD, IFRAME_SCRIPTING), `runtime.getContexts`, messagerie SW ↔ offscreen. En A, la fonction est **absente**, et c'est le premier candidat au shim (§6). |
| `externally_connectable` / `onMessageExternal` | Une page web envoie `chrome.runtime.sendMessage(<id>, …)`, ce que fait MetaMask. Point clé : **quel ID ?** WebKit donne un `uniqueIdentifier` et une `baseURL` en `webkit-extension://` par défaut. On teste si `baseURL` accepte `chrome-extension://<id-dérivé-de-key>` [NV]. |
| `sandbox.pages` + CSP | Page sandboxée avec `unsafe-eval` (MetaMask Snaps). |
| Étanchéité des profils | **Test P1** : même extension chargée dans Pro et Perso. On vérifie que `storage.local`, `session` et `sync`, les cookies, IndexedDB du SW, les règles DNR dynamiques et les permissions accordées ne fuient pas d'un profil à l'autre. Le test se fait aussi après redémarrage de l'app. |

---

## 4. Protocole de test des vraies extensions

**Préparation commune :**

1. Récupérer les **CRX Chrome** de chaque extension, pas les XPI de Zen, à version figée. Retirer l'en-tête CRX3 et garder le ZIP. Archiver avec le SHA-256.
2. Faire un **inventaire statique** : manifest, et grep de `chrome.`/`browser.` dans le bundle. L'inventaire fixe la liste des API attendues et s'arrête au premier écart.
3. Lancer **la ligne de base Chrome for Testing**, avec le même scénario, le même compte de test et la même machine.

**Données** : comptes et portefeuilles **de test uniquement** (testnets Sepolia et Starknet Sepolia). Aucune donnée réelle, aucun coffre Verrou réel.

### 4.1 Verrou (référence interne, modifiable)

**API utilisées**, d'après `extension/*.js` et `manifest.json`, avec l'alias `ext = browser ?? chrome` :

- `runtime` : `connectNative` (port, `onMessage`, `onDisconnect`, `postMessage`, `disconnect`), `sendMessage`, `onMessage`, `getURL`, `getManifest`, `id`, `reload`, `lastError` ;
- `storage` : `local` get/set, `session` get/set/remove, `onChanged` ;
- `tabs` : `query`, `sendMessage`, `onRemoved`, `captureVisibleTab` ;
- `windows.create` (`type: "popup"`, en repli de `action.openPopup`) ;
- `alarms` : `create`, `get`, `onAlarm` ;
- `permissions` : `request` et `contains` (origines) ;
- `i18n` : `getMessage`, `getUILanguage`.

**Manifest** :

- permissions `nativeMessaging`, `storage`, `activeTab`, `alarms` ;
- SW `type: "module"` ;
- 3 content scripts, dont `passkey-codec.js` et `passkey-page.js` en **`world: "MAIN"` à `document_start`** ;
- `key`, qui fixe l'ID Chrome `<ID fixe de l'extension>`.

**Dépendance** : l'hôte natif `app.verrou.bridge` (stdio) n'autorise que `chrome-extension://<ID fixe de l'extension>/` [É, manifeste local de l'hôte natif]. Safira doit donc présenter cette origine à l'hôte (§3.2).

**Scénarios :**

| # | Scénario | Pass si |
|---|---|---|
| V1 | Appairage avec l'app Verrou via la messagerie native | Le port s'ouvre, l'échange d'appairage aboutit, et un `onDisconnect` propre suit la fermeture de l'app |
| V2 | Remplissage automatique d'un formulaire de connexion sur une page de test (iframe incluse, `all_frames`) | Les champs sont remplis et les événements `input` et `change` reçus par la page |
| V3 | Popup : liste, recherche, copie | Idem Chrome |
| V4 | Passkey, création et connexion sur [webauthn.io](https://webauthn.io) ou une page de test locale | L'interception MAIN est active avant le script de la page et l'aller-retour vers Verrou aboutit. Je pense que le remplacement de `navigator.credentials` en MAIN **contourne** le besoin de l'entitlement WebAuthn pour les passkeys de Verrou [D, à vérifier] |
| V5 | QR code (`captureVisibleTab`) | L'image est capturée et décodée |
| V6 | Verrouillage automatique (`alarms` + `storage.session`) après mise en sommeil du SW | Verrou est verrouillé au délai prévu et l'état de session est cohérent |
| V7 | Permission d'origine optionnelle | L'invite apparaît et l'accès est effectif après accord |

Verrou étant à Antonin, on note deux résultats : **sans modification** et **avec adaptations**. Ces adaptations sont acceptables si elles ne cassent pas Chrome.

### 4.2 MetaMask

**Manifest MV3 actuel** [É, `MetaMask/metamask-extension` `app/manifest/v3/_base.json` + `chrome.json`, branche par défaut] :

- permissions `activeTab`, `alarms`, `notifications`, `scripting`, `storage`, `unlimitedStorage`, `webRequest`, **`offscreen`**, **`identity`**, **`sidePanel`**, `cookies` ;
- `clipboardRead` en optionnel ;
- `inpage.js` en **`world: "MAIN"`** à `document_start` + `all_frames` ;
- `externally_connectable` (toutes les URL http/https) ;
- **`sandbox.pages`** (Snaps) ;
- `side_panel` ;
- `wasm-unsafe-eval`.

En A, **offscreen, sidePanel et identity sont absents** [É, §1.1].

| # | Scénario | Pass si |
|---|---|---|
| M1 | Installation, création de wallet et redémarrage de l'app | Le coffre persiste et le déverrouillage marche |
| M2 | Connexion à un dApp de test ([metamask.github.io/test-dapp](https://metamask.github.io/test-dapp/)) | `window.ethereum` et EIP-6963 sont présents et `eth_requestAccounts` aboutit |
| M3 | `personal_sign`, `eth_signTypedData_v4` | Signature vérifiée par le dApp |
| M4 | Transaction Sepolia | La transaction est émise et confirmée |
| M5 | Popup de notification ouverte par le dApp, fermée puis rouverte | Pas de port mort |
| M6 | Side panel | S'ouvre dans la barre latérale de Safira, ou bien la fonction se désactive proprement |
| M7 | Snaps (page sandbox) | Installation d'un snap de test |
| M8 | Matériel (Ledger ou Trezor) | **Hors critère**. On note le résultat ; un échec est attendu sur WebKit (WebHID et WebUSB absents [D]) |

### 4.3 Ready Wallet (ex-Argent X, Starknet)

Le manifest du dépôt public `argentlabs/argent-x` (`packages/extension/manifest/v3.json`, v5.23.0) déclare :

- `alarms`, `tabs`, **`sidePanel`**, `storage`, `unlimitedStorage`, `notifications`, **`hid`**, `webNavigation` ;
- `externally_connectable` ;
- un content script à `document_start` qui injecte un `inpage.js` accessible depuis le web.

Que ce soit bien le manifest de la version actuelle « Ready » est [NV] : le CRX fera foi.

| # | Scénario | Pass si |
|---|---|---|
| R1 | Création ou import d'un compte Starknet Sepolia, puis redémarrage | Le compte persiste |
| R2 | Connexion à un dApp Starknet de test (get-starknet) | `window.starknet_argentX` est présent et la connexion aboutit |
| R3 | Signature de message et transaction Sepolia | La transaction est confirmée |
| R4 | Side panel | Comme M6 |
| R5 | Ledger | **Hors critère**. Échec attendu, WebHID étant absent de WebKit [D] |

### 4.4 uBlock Origin Lite

**Permissions** [É, `uBOL-home` `chromium/manifest.json`] :

- `activeTab`, `alarms`, `declarativeNetRequest`, **`offscreen`**, `scripting`, `storage`, `unlimitedStorage`, **`userScripts`**, `<all_urls>` ;
- appels à `updateDynamicRules`, `updateSessionRules` et `scripting.registerContentScripts`.

uBOL existe déjà pour Safari sur l'App Store depuis août 2025 [É, [apps.apple.com id6745342698](https://apps.apple.com/app/ublock-origin-lite/id6745342698)]. Il faut donc **tester aussi le build Safari d'uBOL**, son code étant adapté à WebKit. Ce qu'il a dû retirer est [NV].

| # | Scénario | Pass si |
|---|---|---|
| U1 | Liste de 50 URL figées (presse, vidéo, pages de test d'adblock). On compte les requêtes bloquées par le collecteur HAR, ou par `getMatchedRules` | ≥ 95 % des requêtes bloquées dans Chrome le sont aussi dans Safira. **Seuil arbitraire** |
| U2 | Filtrage cosmétique (éléments masqués) sur 10 pages | Mêmes éléments masqués que Chrome, à ±5 % |
| U3 | Modes de filtrage (aucun / basique / optimal / complet) par site, avec la permission d'hôte | Le changement de mode est effectif sans rechargement manuel |
| U4 | Coût : RSS et CPU de WebContent avec et sans uBOL | Mesure informative, sans seuil |

### 4.5 BetterTTV

Manifest non lu (pas trouvé dans `night/betterttv` par l'API) [NV]. C'est probablement un content script qui injecte du code dans twitch.tv.

| # | Scénario | Pass si |
|---|---|---|
| B1 | Chat Twitch : emotes BTTV, 7TV et FFZ visibles | Identique à Chrome |
| B2 | Panneau de réglages BTTV | S'ouvre et persiste |

### 4.6 Open Graph Preview

Manifest non lu [NV].

| # | Scénario | Pass si |
|---|---|---|
| O1 | Aperçu des balises OG et Twitter Cards sur 5 pages | Identique à Chrome |

**Proton VPN** : hors périmètre, à remplacer par l'app système (Q6). Si on le garde, il dépend de l'API **proxy**, voir §6 : partiel en A.

---

## 5. Scoring, rapport, go/no-go

### 5.1 Statuts au niveau de chaque membre

| Statut | Définition |
|---|---|
| `absent` | `undefined` dans tous les contextes attendus |
| `stub` | Présent, mais rejette « not implemented/unsupported », ou se bloque (timeout) |
| `partiel` | L0 et L1 OK, mais des paramètres, options ou événements manquent, ou L3 passe en partie |
| `divergent` | Présent et fonctionnel, mais un résultat L3 diffère de la ligne de base Chrome (forme, ordre des événements, erreurs, limites) |
| `complet` | L0 à L3 passent et sont identiques à Chrome |
| `n/a` | Hors périmètre déclaré (ChromeOS, dev-channel, allowlist, policy) |

Un namespace prend le **pire statut pondéré** de ses membres. On publie aussi le pourcentage de membres complets.

### 5.2 Sorties

- `report/matrix.json` : `{namespace, membre, contexte, statut[A], statut[A+shim], statut[B], statut[Chrome], preuve}`.
- `report/matrix.md` : un tableau namespace × {A, A+shim, B, Chrome}, plus le détail par membre en sections repliables.
- `report/extensions.md` : chaque scénario des §4.1 à 4.6 en pass/fail × architecture, avec capture et journal.
- Les révisions figées sont en tête : commit Chromium, build macOS, branche ou commit WebKit, versions des CRX.

### 5.3 Trois niveaux de couverture

1. **C1, les extensions cibles** : scénarios « must » du §4. C'est le critère **décisionnel**.
2. **C2, la couverture pondérée par l'usage** sur un corpus d'environ 200 extensions MV3 populaires du Chrome Web Store, plus les 6 cibles. Chaque namespace et chaque membre est pondéré par sa fréquence d'usage statique dans le corpus. Le corpus reste à construire : liste figée, CRX archivés [NV pour la faisabilité du téléchargement en masse]. C2 sert à juger si Safira tiendra **au-delà** des 6 extensions.
3. **C3, la matrice brute** sur les ~55 namespaces desktop « réels » : les 68, moins les namespaces de types, les API dev-channel et allowlist, et les API DevTools propres à Chrome. C'est un **diagnostic**, pas un seuil.

### 5.4 Critères go/no-go

**G1, éliminatoire** : tous les scénarios « must » des 6 extensions passent sur l'architecture retenue, **shims compris**.

- Must : V1 à V7, M1 à M5, R1 à R3, U1 à U3, B1, O1.
- Hors critère : M6 et R4 (side panel), à condition qu'un repli existe et qu'il soit propre ; M7 (Snaps) ; M8 et R5 (matériel).

Justification : c'est la définition opérationnelle de « le support des extensions doit être très bon » pour Antonin. Ce critère **n'est pas arbitraire**.

**G2, uBOL** : U1 ≥ 95 % et U2 ≥ 95 %. **Seuils arbitraires**, à confirmer par Antonin (Q5). Le principe est qu'un écart sous 5 % ne se voit pas à l'usage.

**G3** : C2 ≥ 85 % de la masse d'usage en statut `complet` ou `divergent` mineur sur A+shim.

- **Seuil arbitraire.** Il a été choisi pour être plus exigeant que les ~70 % annoncés par Orion, chiffre qui ne se compare pas directement.
- On mesure aussi la part de la masse classée « hook moteur ». Si elle dépasse 10 %, l'écart restant n'est pas comblable sans fork. **Seuil arbitraire.**

**G4, coût** : les shims nécessaires pour satisfaire G1 et G3 tiennent en **≤ 8 semaines** de développement estimé, avec incertitude affichée, et **sans SPI** dans le produit. **Seuil arbitraire**, à fixer par Antonin.

**G5, B seulement** : la preuve de distribution du §3.3 réussit, ET un must de G1 échoue sur A+shim mais passe, ou passerait, sur B.

**Décision :**

- **GO-A** : G1, G2, G3 et G4 sont tenus sur A+shim.
- **GO-A-attendre** : G1 échoue uniquement sur des fonctions déjà sur main, ou dans STP, et absentes du système, comme offscreen ou le correctif 290922. On attend la prochaine version de macOS, avec une date estimée. **C'est un risque, pas un plan** : Apple ne s'engage sur aucune date.
- **GO-B** : G5 est tenu. **Je le déconseille, sauf fonction must irremplaçable** (§0.4).
- **NO-GO** : G1 échoue sur A+shim **et** (G5 échoue **ou** le coût de B est jugé inacceptable).

---

## 6. Classification de l'écart

**Mécanismes de shim en A**, tous issus de l'API publique du SDK macOS 27 [É pour l'existence, D pour l'usage] :

- **S1, réécriture du bundle à l'installation.** Safira contrôle les fichiers de l'extension. Elle peut :
  - ajouter un module shim en tête du service worker, des pages et des content scripts ;
  - ajouter `nativeMessaging` au manifest ;
  - mapper les clés inconnues, comme `side_panel`.

  À valider : `runtime.getManifest()` renverrait alors le manifest modifié, ce qui peut gêner les extensions qui l'inspectent.
- **S2, pont app.** Le shim JS appelle `runtime.connectNative("safira.internal")`, qui arrive dans `connectUsingMessagePort:`. L'app implémente la logique en Swift et pousse les événements par le même port.
- **S3, pages d'extension hébergées par l'app.** On crée une WKWebView avec `context.webViewConfiguration`, qui est publique, sur `context.baseURL/<page>`. Cela sert pour offscreen (vue cachée) et sidePanel (vue dans la barre latérale de Safira). À vérifier : que la page reçoive bien `chrome.*`, et que `runtime.getContexts` et `sender` soient cohérents.
- **S4, `WKUserContentController` + `WKContentWorld`** dans les configurations d'onglet de Safira, pour userScripts et declarativeContent.
- **S5, API WebKit publiques au niveau du data store** : `WKWebsiteDataStore` (`removeData`, `proxyConfigurations`, `httpCookieStore`), `WKDownload` et `WKWebView.createWebArchiveData`.

### (i) État du navigateur, implémentable dans l'app (S1 + S2)

| Namespace | Piste | Remarque |
|---|---|---|
| history | Historique tenu par Safira | Facile |
| sessions | Onglets et fenêtres fermés récemment, gérés par Safira | Facile |
| tabGroups | Les Spaces et groupes de Safira | Le mapping Space ↔ tabGroup est à concevoir. `tabs.group/ungroup` manquent dans l'IDL Tabs de WebKit [É] et doivent être shimmés dans `tabs` |
| topSites, readingList, search, omnibox | UI de Safira | omnibox touche la barre d'adresse |
| bookmarks | Signets de Safira | Le WebKit système a une SPI `_webExtensionController:bookmarksForExtensionContext:` (safari-7625) [É], mais elle n'est pas activée (flag à 0). En shim |
| downloads | `WKDownload` | Moyen. `downloads.onDeterminingFilename` est réalisable |
| management | Liste des contextes du contrôleur | Facile |
| idle | `CGEventSourceSecondsSinceLastEventType` / IOKit | Facile |
| power | `IOPMAssertionCreateWithName` | Facile |
| system.cpu, system.memory, system.storage, system.display | `host_statistics`, `NSScreen`, `statfs` | Facile |
| tts | `AVSpeechSynthesizer` | Facile. ttsEngine est niche |
| browsingData | `WKWebsiteDataStore removeData…` | Facile, granularité par type |
| notifications | Déjà dans le WebKit système (permission supportée [É]) | Le rendu UI est à vérifier |
| identity.launchWebAuthFlow | `ASWebAuthenticationSession` ou fenêtre Safira | Moyen. `getAuthToken` exige un compte Google : niche |
| offscreen | S3, WKWebView cachée | **Prioritaire** (MetaMask, uBOL). Faisabilité [D], à prototyper en premier |
| sidePanel | S3 dans la barre latérale | **Prioritaire** (MetaMask, Ready). Bon atout UX dans une interface de type Arc |
| runtime.getContexts, onSuspend, onUpdateAvailable, requestUpdateCheck | Absents de l'IDL Runtime de safari-7625 [É] | `getContexts` est nécessaire à l'usage d'offscreen. Shim partiel : impossible de connaître les contextes créés par WebKit lui-même, sauf ceux de l'app [D] |
| publicSuffix, dns | Liste PSL embarquée, `getaddrinfo` | Facile |
| fontSettings | Peu d'API publiques (`WKPreferences`) | Partiel |
| contentSettings | `WKWebpagePreferences.allowsContentJavaScript` (par navigation), décisions de permission caméra et micro via `WKUIDelegate` | Partiel : pas de réglage public pour images ou plugins [D] |

### (ii) Hook moteur ou réseau

| Namespace | Piste | Fork ? |
|---|---|---|
| userScripts | S4 : `WKUserScript` dans un `WKContentWorld` dédié, avec `onUserScriptMessage` via `WKScriptMessageHandler` → S2 | **Pas de fork** [D]. Limites : contournement de CSP et `world_id` multiples à vérifier |
| declarativeContent | Content script shim (correspondance CSS et URL) → S2 → `action` | Pas de fork [D] |
| proxy | `WKWebsiteDataStore.proxyConfigurations` par profil : HTTP CONNECT, SOCKSv5, relay, OHTTP [É, en-têtes SDK]. **Pas de PAC** dans `nw_proxy_config_create_*` [É] | Partiel sans fork. Le PAC exigerait un proxy local dans l'app [D] |
| privacy | webRTCIPHandlingPolicy, prédiction réseau : pas de contrôle public identifié | Fork ou SPI [D] |
| debugger (CDP) | WebKit parle le Web Inspector Protocol, pas CDP. L'accès programmatique est en SPI (`_WKInspector`, remote inspector) | SPI au minimum, plus une traduction CDP → WIP. **Lourd**, faible usage hors outils de dev |
| tabCapture, desktopCapture | ScreenCaptureKit côté app est facile. Le difficile est de livrer un `MediaStream` à une page d'extension (`chromeMediaSourceId`) | Fork probable [D] |
| pageCapture | `createWebArchiveData` produit un webarchive, pas du MHTML | Partiel. La conversion MHTML est à écrire |
| webRequest (observation) | Présent dans WebKit | Couverture des événements et de `extraInfoSpec` à mesurer. Le blocage n'est pas requis en MV3 grand public |
| DNR (lacunes) | Absents de l'IDL safari-7625 [É] : `getAvailableStaticRuleCount`, `getDisabledRuleIds`, `updateStaticRules`, `testMatchOutcome`. 290922 est corrigé sur main seulement | Attendre macOS ou fork. Pas de shim possible pour la sémantique réseau |
| webAuthenticationProxy | Remplacement de `navigator.credentials` en MAIN (méthode Verrou) | Pas de fork pour l'essentiel [D]. Il manque l'intégration UI native |
| Hors API : WebHID, WebUSB | Absents de WebKit | Fork lourd, ou repli natif via messagerie native. Hors critère |

### (iii) Niche, entreprise, non pertinent

- **Niche ou entreprise** : `gcm`, `instanceID` (Google), `enterprise.hardwarePlatform`, `printerProvider`, `processes` (dev), `mimeHandler` (allowlist), `accessibilityFeatures`, `ttsEngine`.
- **DevTools Chrome** : `devtools.performance`, `devtools.recorder`. `devtools.inspectedWindow`, `network` et `panels` existent dans WebKit sous `INSPECTOR_EXTENSIONS` [É].
- **Types seuls** : `types`, `extensionTypes`, `events`.

À vérifier au moment de l'implémentation, je ne l'ai pas fait : l'usage réel de ces namespaces dans le corpus C2. Si l'un d'eux pèse plus de 1 %, il remonte dans la catégorie (i) ou (ii).

---

## 7. Étapes, effort, parallélisation

Les estimations sont en jours de travail pour une personne, sous forme d'intervalle, avec le principal facteur d'incertitude.

| Étape | Contenu | Effort | Incertitude | Dépend de |
|---|---|---|---|---|
| E0 | Libérer ≥ 100 Go ou brancher un SSD (si B). Installer Chrome for Testing. Récupérer et archiver les 6 CRX. Inventaire statique (manifest et grep) | 1 j | Faible | Rien |
| E1 | Extracteur de schéma Chromium → `chrome-api.json`, avec les fichiers `_features` | 2–4 j | Moyenne : outillage extractible ou repli chrome-types | E0 |
| E2 | SafiraBench.app : contrôleur, onglets et fenêtres minimaux, délégué complet, collecteur HTTP, CLI, 2 profils | 4–7 j | Moyenne : la surface des protocoles Tab et Window est large | Rien |
| E3 | `probe-gen` L0 à L2 + rapport | 3–5 j | Faible | E1 |
| E4 | Tests L3 manuels sur ~20 namespaces prioritaires + cas non triviaux du §3.4 | 8–15 j | **Forte** : c'est l'essentiel du travail | E2, E3 |
| E5 | Ligne de base Chrome (même extension, même collecteur) | 1–2 j | Faible | E3 |
| E6 | Pont de messagerie native compatible Chrome + scénarios des 6 extensions sur A | 4–7 j | Moyenne : comptes de test, testnets, flakiness | E2 |
| E7 | **Prototypes de shims** S1, S2 et S3 : offscreen, sidePanel, `runtime.getContexts`, plus un namespace de la catégorie (i) (history). On rejoue M1 à M5 et U1 | 5–8 j | **Forte**, c'est la question centrale | E2, E6 |
| E8a | Test du raccourci STP (§3.3) | 0,5–1 j | Moyenne : faisable ou pas | E2 |
| E8b | Build de WebKit main + exécution du banc en B | 3–6 j, build en arrière-plan | Forte : disque, RAM, cassures d'API de main | E0, E2 |
| E8c | Preuve de distribution B (notarisation, Mac propre) | 3–5 j | **Très forte**, sans précédent connu | E8b. **Seulement si G1 échoue en A+shim** |
| E9 | Corpus C2 : ~200 CRX + analyse statique pondérée | 2–4 j | Moyenne : téléchargement en masse depuis le Web Store | E1 |
| E10 | Rapport final + décision | 1–2 j | Faible | Tout |

**Total sans E8c : ~35–65 j**, soit environ 7 à 13 semaines pour une personne seule.

**Version réduite décisionnelle, ~4–6 semaines** : E0, E1 en version légère, E2, E6, E7 et E10. E4 se limite alors aux API des 6 extensions, et E9 est remplacé par la liste « top 50 ». Cette version suffit à trancher G1. G3 vient ensuite.

**Parallélisable :**

- **Dès le jour 1** : E1, E2 et E9. Ce sont des personnes ou agents indépendants.
- E8b peut **compiler en arrière-plan** pendant E4 et E6, si le disque le permet.
- Dans E4, chaque namespace est indépendant : on peut répartir le travail par namespace.
- E5 et E6 peuvent avancer en parallèle de E4.

**Ordre conseillé** : E2 et E6 d'abord, avec Verrou et MetaMask sur A tels quels, puis E7. Si les shims S3 et S2 échouent, le projet s'arrête au bout d'environ 3 semaines, sans avoir payé E4, E8 ni E9.

### Risques

1. **Shim impossible pour offscreen et sidePanel** (S3 refusé par WebKit, ou APIs non injectées dans une WKWebView créée par l'app). La conséquence est le passage à B ou un NO-GO. **On le teste en premier.**
2. **ID d'extension et origine** : si `baseURL` ne peut pas être `chrome-extension://<id>`, il faut adapter l'hôte natif de Verrou et vérifier `externally_connectable` pour les wallets.
3. **Divergences de cycle de vie du SW** : mise en sommeil, perte d'état et réveil. Elles sont invisibles au niveau L0. Ce sont typiquement des bugs intermittents.
4. **Le WebKit système change à chaque version de macOS**, ce qui peut aussi améliorer les choses (offscreen). Il faut ré-exécuter le banc à chaque version bêta de macOS. Prévoir de le garder en CI locale.
5. **WebKitAdditions** : le comportement Apple ≠ l'open source. Toute conclusion tirée de B est une borne basse pour la future version système, pas une prévision.
6. **Ressources de la machine** : 16 Go de RAM et 30 Go de disque, qui suffisent pour A mais pas pour B.
7. **Entitlement passkeys** : il doit être demandé à Apple pour Safira, quel que soit A ou B. Le délai est long d'après les forums [É, forum 852550, rapporté]. Verrou pourrait contourner pour ses propres passkeys [D].
8. **Politique des Stores** : chargement de CRX depuis le Chrome Web Store et conditions d'utilisation de Google [NV]. Point juridique à regarder avant la distribution, pas avant le banc.

---

## 8. Ce que je n'ai pas pu établir

- Durée et taille réelles d'un build de WebKit main sur M4 avec 16 Go de RAM.
- Existence d'une app tierce notariée et distribuée qui embarque son propre WebKit sur macOS.
- Empaquetage de Safari Technology Preview, et possibilité de charger ses frameworks depuis une app tierce.
- Acceptation par `WKWebExtensionContext.baseURL` d'un schéma `chrome-extension`.
- Injection de `chrome.*` dans une WKWebView créée par l'app avec `context.webViewConfiguration` (base du shim S3). Point le plus important.
- Manifests de BetterTTV, d'Open Graph Preview et de la version actuelle de Ready Wallet.
- Ce qu'uBOL a retiré dans sa version Safari.
- Si Orion utilise WKWebExtension.
- Mise en œuvre de `world: "MAIN"` à `document_start` avant les scripts inline de la page dans le WebKit système. Le manifest est analysé [É], le reste est à tester.

---

## 9. Questions ouvertes pour Antonin

1. **Disque** : acceptes-tu un SSD externe ou un ménage d'environ 100 Go pour la phase B ? Sinon, B se limite au raccourci STP (E8a).
2. **Ordre** : valides-tu la version réduite décisionnelle (E2 → E6 → E7, ~4–6 semaines) avant la matrice complète ?
3. **macOS minimal** : quelle version minimale de macOS pour Safira ? Le WebKit système, donc A, en dépend. Je suggère macOS 27 ou plus.
4. **Option B** : es-tu prêt à assumer un fork de WebKit, avec ce que cela implique : suivi de sécurité toutes les 4 à 8 semaines, sandbox affaiblie, pas de DRM ni d'Apple Pay probables ? Si la réponse est non, on retire B du critère et on garde seulement « A+shim ou arrêt ».
5. **Seuils** : les seuils arbitraires te conviennent-ils ? U1/U2 ≥ 95 %, C2 ≥ 85 %, masse « hook moteur » ≤ 10 %, budget de shims ≤ 8 semaines.
6. **Proton VPN** : est-il remplacé par l'app système, donc hors critère ?
7. **Portefeuilles matériels** : Ledger et Trezor (WebHID/WebUSB) sont-ils hors critère ? Sinon c'est un NO-GO quasi certain sur WebKit, quelle que soit l'architecture.
8. **Fonctions secondaires des wallets** : MetaMask Snaps et le side panel des wallets sont-ils des must, ou un repli propre suffit-il ?
9. **Verrou** : acceptes-tu d'adapter Verrou (origine native, ID d'extension) si c'est le seul écart ?
10. **Corpus C2** : veux-tu la couverture pondérée sur environ 200 extensions, ou les 6 cibles plus un top 50 te suffisent-ils ?
11. **Passkeys** : veux-tu demander l'entitlement `web-browser.public-key-credential` à Apple dès maintenant ? Le délai est long et la demande ne dépend pas du banc.

---

## Annexe A — 68 namespaces non-ChromeOS (developer.chrome.com, 2026-11)

accessibilityFeatures, action, alarms, bookmarks, browsingData, commands, contentSettings, contextMenus, cookies, debugger, declarativeContent, declarativeNetRequest, desktopCapture, devtools.inspectedWindow, devtools.network, devtools.panels, devtools.performance, devtools.recorder, dns, dom, downloads, enterprise.hardwarePlatform, events, extension, extensionTypes, fontSettings, gcm, history, i18n, identity, idle, instanceID, management, mimeHandler, notifications, offscreen, omnibox, pageCapture, permissions, power, printerProvider, privacy, processes, proxy, publicSuffix, readingList, runtime, scripting, search, sessions, sidePanel, storage, system.cpu, system.display, system.memory, system.storage, tabCapture, tabGroups, tabs, topSites, tts, ttsEngine, types, userScripts, webAuthenticationProxy, webNavigation, webRequest, windows.

## Annexe B — Namespaces exposés par WebKit (`WebExtensionAPINamespace.idl`)

| | Namespaces |
|---|---|
| **Système (safari-7625)** | action, browserAction et pageAction (alias), alarms, commands, contextMenus et menus, cookies, declarativeNetRequest, devtools (si `INSPECTOR_EXTENSIONS`), dom, extension, i18n, notifications, permissions, runtime, scripting, storage, tabs, webNavigation, webRequest, windows |
| **Désactivés à la compilation** | bookmarks, sidePanel, sidebarAction |
| **Main uniquement** | offscreen (depuis le 2026-08-08) |
| **Interne** | test (mode test, SPI) |
