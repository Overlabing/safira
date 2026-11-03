# Safira : libération des onglets inactifs, recherche et règle par onglet

Statut : recherche, lecture seule. Rédigé le 2026-11-03 sur macOS 27.0.1 (26A434), Xcode 27.1 (SDK 27.0), Apple M4, 16 Go de RAM.

Ce document est une recherche suivie d'une recommandation. Il ne contient aucun code produit (le script de l'annexe A est un outil de mesure).

Légende :

- **[É]** établi, avec la source ;
- **[D]** déduit, avec le raisonnement ;
- **[NV]** non vérifié.

Conventions de sources :

- « SDK 27 » = en-têtes de `WebKit.framework` du SDK macOS 27.0 installé avec Xcode 27.1, lus en local (`/Applications/Xcode.app/.../MacOSX.sdk/System/Library/Frameworks/WebKit.framework/Headers/`).
- « WebKit main » = code lu sur `github.com/WebKit/WebKit`, branche `main`, le 2026-11-03. **Ce n'est pas forcément le WebKit livré avec macOS 27.0.1** (cf. le même écart relevé dans `conformance-bench-plan.md` §1.1). Toute valeur tirée de `main` est donc [É] pour `main` et [D] pour le système.

---

## 0. En bref

1. **Aucune API publique ne « libère un onglet ».** Le schéma est : sérialiser (`interactionState`), prendre une image (`takeSnapshot`), détruire la `WKWebView`, puis en recréer une et réinjecter l'état. Tout est faisable en API publique, mais l'état sérialisé a des limites (§1.1).
2. **Le cadrage « WebKit ne fait rien seul » est faux.** WebKit expose en public, depuis macOS 14, `WKPreferences.inactiveSchedulingPolicy` (`suspend` / `throttle` / `none`). Pour une app liée à un SDK ≥ macOS 15, le défaut sur `main` est `suspend` : un WebContent détaché ou caché est mis en veille complète après **4 min** (10 s sous pression mémoire) (§1.6). Safira l'obtient sans rien faire.
3. **Suspendre n'est pas libérer.** Un process suspendu garde sa mémoire résidente ; seule la compression/le swap de macOS la réduit, et seulement sous pression [D]. La valeur propre de la destruction est donc la mémoire **au-delà** de la suspension. Cette valeur n'est pas mesurée par quiconque, à ma connaissance [NV] : c'est la première chose à mesurer (§5, bras A0).
4. **Détruire la `WKWebView` ne rend pas forcément la mémoire tout de suite.** Si Safira est reconnue comme « navigateur complet » par WebKit (app capable d'ouvrir `http` et `https`), WebKit garde les processus de pages fermées dans un `WebProcessCache` jusqu'à **30 min**, sauf sous pression mémoire (§1.5). C'est un point qui **contredit** le cadrage (« WKWebView détruite = RAM rendue »).
5. **Les délais publiés par les autres navigateurs sont longs** : Edge 15 min par défaut ; Firefox impose ≥ 10 min d'inactivité et n'agit que sous pression mémoire (désactivé en version release sur Mac) ; Chrome 2 h / 4 h / 6 h ; Arc archive à 12 h ; Zen expose un réglage à 10 min (§2). **Aucun ne descend à quelques minutes.** Or le protocole « 20 onglets, 10 minutes » ne laisse agir aucune règle à 15 min ou plus : il mesure donc la suspension WebKit, pas la libération (§4.4, §5).
6. **Des signaux manquent en API publique** : pas d'« onglet audible » (seulement « lit un média »), pas de détection de WebSocket, de formulaire modifié, de `beforeunload`, ni de PID/mémoire par `WKWebView`. Il faut soit du JavaScript injecté, soit une règle prudente (§1.3, §4.2).
7. **`interactionState` ne garantit pas les valeurs de formulaire en cours de saisie** : WebKit écrit l'état de formulaire dans l'élément d'historique à la navigation, pas en continu (§1.1). Une protection « formulaire modifié » est donc indispensable, comme chez Chrome.
8. **Recommandation** (§4) : machine à états par onglet (actif → caché/suspendu par WebKit → libéré), règle d'éligibilité par exclusions, délai de base **30 min** de non-visibilité (horloge hors veille), raccourci sous pression (`.warning` : 10 min ; `.critical` : un onglet toutes les 10 s, LRU), priorité décroissante par seaux. Valeurs par défaut = [D], à valider par mesure.

---

## 1. API publiques WebKit

### 1.1 `WKWebView.interactionState`

- **Disponibilité** : macOS 12.0, iOS 15.0, visionOS 1.0 [É] ([doc Apple](https://developer.apple.com/documentation/webkit/wkwebview/interactionstate)). Propriété `id` `copy`, lecture/écriture [É] (SDK 27, `WKWebView.h`).
- **Ce que dit l'en-tête** [É] : « The interaction state (back-forward list, currently loaded page, scroll position, form data...) […] can be retrieved and set on another WKWebView to restore state. » (SDK 27, `WKWebView.h`). La page de doc Apple n'ajoute aucune précision ni limite.
- **Ce que le code encode** [É, WebKit main] :
  - `-[WKWebView interactionState]` renvoie `encodeSessionState(_page->sessionState())` ; le setter décode et appelle `restoreFromSessionState(sessionState, true)`, donc **navigue immédiatement** ([`WKWebView.mm`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebView.mm)).
  - `sessionState()` contient la liste d'historique (`backForwardListState`), l'URL provisoire en cours de chargement, la taille de l'arbre de rendu et un drapeau `isAppInitiated` ([`WebPageProxy.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/WebPageProxy.cpp), `WebPageProxy::sessionState`).
  - Chaque entrée (`FrameState`) porte : URL, référent, `documentState` (état des contrôles de formulaire), `scrollPosition`, `pageScaleFactor`, corps HTTP (POST), `stateObject` (`history.pushState`), titre ([`FrameState.h`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Shared/FrameState.h)).
- **Limite 1, fraîcheur** [É pour le code, D pour la conséquence] : `sessionState()` lit l'état déjà présent côté processus UI. `documentState` est écrit dans l'élément d'historique par `HistoryController::saveDocumentState()`, appelé au commit/à la navigation ([`HistoryController.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/loader/HistoryController.cpp), l. 215-258, 685-745), pas à chaque frappe. **Un texte tapé dans un champ sans navigation ensuite peut ne pas figurer dans `interactionState`** [D]. Même doute pour la position de défilement en cours [NV : à tester].
- **Limite 2, ce qui n'est pas capturé** [D] : état JavaScript en mémoire (SPA, éditeurs riches, canvas, jeux), connexions WebSocket/WebRTC, position de lecture d'un média, contenu de `<input type=file>`, état des Service Workers en cours.
- **Limite 3, format** : opaque (`NSData` dans l'implémentation, mais le type public est `id`). Stabilité d'un format persisté entre versions de macOS : non documentée [NV]. Persister l'état sur disque est donc risqué ; prévoir un repli sur la seule URL.
- **Restauration** : crée un chargement réseau normal ; le cache HTTP peut aider, pas de garantie [D].

### 1.2 `takeSnapshot` et `createWebArchive`

- `takeSnapshot(configuration:)` : macOS 10.13 [É] (SDK 27). Rect en coordonnées de vue ; `snapshotWidth` en points ; `afterScreenUpdates` (macOS 10.15). Si le rect ou la largeur est vide, le handler reçoit une image 0×0 sans erreur ([`WKWebView.mm`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebView.mm), l. 1642-1652) [É main]. Comportement sur une vue **cachée** ou **hors fenêtre** : [NV].
- **Coût mémoire de « l'image conservée »** [D] : un instantané de 1280×800 px en BGRA fait ≈ 4 Mo décodé. 20 onglets conservés décodés = ≈ 80 Mo, soit potentiellement plus que ce que le discard économise sur des pages légères. Recommandation : encoder en JPEG/HEIC à largeur réduite, stocker sur disque, décoder à la demande (§4.5).
- `createWebArchiveData(completionHandler:)` : macOS 11.0 [É] (SDK 27). Représente le contenu courant de la page, rechargeable dans une `WKWebView`. **Non retenu pour la restauration** [D] : il fige le DOM et perd le JavaScript vivant ; c'est un outil de sauvegarde, pas de reprise d'onglet. Le coût de génération sur une grosse page est [NV].

### 1.3 Médias, capture, chargement, téléchargements

| API | Dispo | Ce qu'elle donne | Limite | Source |
| --- | --- | --- | --- | --- |
| `requestMediaPlaybackState(completionHandler:)` | macOS 12 | `.none`, `.playing`, `.paused`, `.suspended` | **Asynchrone, pas une propriété** (le nom `mediaPlaybackState` du cadrage n'existe pas). Ne distingue pas « son audible » de « vidéo muette en lecture ». | [É] SDK 27 |
| `cameraCaptureState`, `microphoneCaptureState` | macOS 12 | `.none`, `.active`, `.muted`, KVO | Couvre getUserMedia, pas les canaux de données WebRTC. | [É] SDK 27 |
| `pauseAllMediaPlayback`, `setAllMediaPlaybackSuspended(_:)` | macOS 12 | Pause ; ou suspension qui **bloque** la reprise par la page ou l'utilisateur jusqu'au contre-appel | Appairer suspendre/reprendre. Inutile pour décider de libérer. | [É] SDK 27 |
| `closeAllMediaPresentations` | macOS 12 | Ferme PiP et plein écran | Action, pas détection. Pas d'API publique « est en PiP » [NV]. | [É] SDK 27 |
| `fullscreenState` | macOS 13 | Plein écran de l'élément | — | [É] SDK 27 |
| `isLoading` | macOS 10.10 | Chargement en cours | — | [É] |
| `WKDownload` | macOS 11.3 | `webView` en référence **faible** ; `cancel` renvoie des `resumeData` | Si un téléchargement survit à la destruction de sa `WKWebView` : [NV]. Règle prudente : onglet protégé tant que l'app tient un `WKDownload` actif pour lui. | [É] SDK 27, `WKDownload.h` |
| `webViewWebContentProcessDidTerminate` | macOS 10.11 | Notification de mort du process (jetsam, crash) | C'est le seul signal public qu'un process a été tué ; prévoir un rechargement avec `interactionState`. | [É] SDK 27 |

Signaux **sans API publique** [D, vérifié par l'absence dans les en-têtes SDK 27] : onglet audible, WebSocket ouvert, peer connection WebRTC, formulaire modifié, `beforeunload`, PID du WebContent, mémoire par vue. Pistes en JS injecté dans un `WKContentWorld` isolé : écoute des événements `input`/`change` en phase de capture (formulaire modifié). Le hook de `RTCPeerConnection`/`WebSocket` ou de `beforeunload` exige le monde de la page, ce qui modifie l'environnement de la page (empreinte, compatibilité) : **non recommandé par défaut** [D].

### 1.4 Processus : un par `WKWebView` ?

- Le commentaire de l'en-tête dit : chaque web view reçoit **son propre** processus WebContent, jusqu'à une limite d'implémentation ; au-delà, les vues d'un même pool partagent des processus [É] (SDK 27, `WKProcessPool.h`).
- Cette limite vaut **400** (512 avec Site Isolation) sur `main` ([`WebProcessProxy.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/WebProcessProxy.cpp), `defaultMaxProcessCount`) [É main]. À 20 onglets, elle est hors sujet. Au-delà, WebKit décharge lui-même la page la moins récemment visible (`leastRecentlyVisiblePageToUnload`) [É main].
- **`WKProcessPool` est déprécié** depuis macOS 12 : « Creating and using multiple instances of WKProcessPool no longer has any effect. » [É] (SDK 27, `WKProcessPool.h` et `WKWebViewConfiguration.h`). Il est donc impossible d'isoler les onglets par pool ; les processus sont rattachés à un `WKWebsiteDataStore` [D, d'après `WebProcessProxy` qui porte un `m_websiteDataStore`]. Deux profils ne partagent donc pas de processus [D].
- WebKit garde en plus **1 processus WebContent préchauffé** (2 avec Site Isolation) ([`WebProcessPool.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/WebProcessPool.cpp), `prewarmedProcessCountLimit`) [É main] : à compter dans la ligne de base mesurée.

### 1.5 Coût réel de la destruction d'une `WKWebView`

- Quand la dernière page d'un process disparaît, `WebProcessProxy::maybeShutDown()` tente d'abord `WebProcessCache::addProcessIfPossible`, sinon `shutDown()` [É main].
- Le cache est **actif seulement si le modèle de cache est « PrimaryWebBrowser »**, c'est-à-dire si `isFullWebBrowserOrRunningTest()` est vrai ([`LegacyGlobalSettings.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/LegacyGlobalSettings.cpp)) [É main]. Sur macOS (hors `APP_BOUND_DOMAINS`), est « navigateur complet » toute app qui figure dans les apps capables d'ouvrir `http:` **et** `https:` ([`DefaultWebBrowserChecks.mm`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Shared/Cocoa/DefaultWebBrowserChecks.mm), l. 274-292) [É main]. Safira, déclarée comme navigateur, **sera donc dans ce cas** [D].
- Paramètres du cache [É main] ([`WebProcessCache.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/WebProcessCache.cpp)) :
  - durée de vie d'un process en cache : **30 min** (Cocoa), 5 min après perte du premier plan de l'app ;
  - capacité : `min(RAM / 256 Mo, 32)`, soit 32 sur 16 Go ;
  - un process en cache est suspendu après 30 s ;
  - **pas de mise en cache sous pression mémoire** (`isUnderMemoryPressure`) ni à l'approche de la limite de processus.
- **Conséquence** [D] : sans pression, la destruction d'un onglet peut laisser un process résident jusqu'à 30 min. Le gain de RAM « immédiat » dépend donc de ce cache, que Safira ne contrôle pas en API publique (la configuration `usesWebProcessCache` est dans `_WKProcessPoolConfiguration`, SPI [É main]). À mesurer (bras A3, §5). Si le cache annule l'effet, il reste le levier : détruire sous pression (le cache est alors désactivé).
- Le modèle « PrimaryWebBrowser » **augmente aussi** la capacité du cache d'objets : 128 Mo contre 96 Mo pour 2 Go de RAM ou plus ([`CacheModel.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Shared/CacheModel.cpp)) [É main]. Safari a le même modèle ; la parité de RAM ne sera donc pas obtenue en évitant cet état [D].
- **Fuites côté app** [D, d'après des fils de forum, pas d'ingénieur Apple] : un `WKScriptMessageHandler` ajouté à un `WKUserContentController` crée un cycle de rétention qui garde la vue vivante ([fil Apple Developer 22795](https://developer.apple.com/forums/thread/22795), cause suggérée par un utilisateur, non confirmée). Avant de relâcher une vue : la retirer de la hiérarchie, `removeAllScriptMessageHandlers()`, mettre `navigationDelegate`/`uiDelegate` à `nil`. Vérifier par mesure que le process disparaît (bras A3).
- **Temps de restauration** : aucune mesure publiée trouvée [NV]. Protocole en §5.4.
- **Mesures publiées de la mémoire d'une vue** : aucune trouvée ; une recherche ciblée ne renvoie que des fils de forum (mémoire hors app, limite dynamique non relevable : [fil 133449](https://developer.apple.com/forums/thread/133449), réponse d'un ingénieur Apple) [NV].

### 1.6 Ce que WebKit fait seul

- **Visibilité sur macOS** [É main] ([`PageClientImplMac.mm`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/mac/PageClientImplMac.mm), `isViewVisible`) : la vue est « non visible » si elle n'a pas de fenêtre, si `isHiddenOrHasHiddenAncestor`, si la fenêtre n'est pas visible, ou si elle est occultée (suivi d'occlusion `NSWindowOcclusionState`). **Une `WKWebView` avec `isHidden = true` est donc traitée comme un onglet d'arrière-plan**, sans qu'il faille la retirer de la hiérarchie [D].
- **`WKPreferences.inactiveSchedulingPolicy`** : macOS 14.0, iOS 17.0 [É] (SDK 27, `WKPreferences.h`). Doc de l'en-tête : « scheduling policy for the web view when it is inactive and detached from the view hierarchy. Web views are not considered idle when playing media or loading web pages. A suspended web view will pause JavaScript execution and page layout. » Trois valeurs : `suspend`, `throttle`, `none`.
- **Défauts** [É main] ([`WebPreferencesDefaultValues.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Shared/WebPreferencesDefaultValues.cpp), [`RuntimeApplicationChecksCocoa.mm`](https://github.com/WebKit/WebKit/blob/main/Source/WTF/wtf/cocoa/RuntimeApplicationChecksCocoa.mm)) : l'étranglement via RunningBoard et la suppression de l'assertion « near-suspended » sont **activés pour les apps liées à un SDK ≥ macOS 14 / 15**. Safira (SDK 27) obtient donc le comportement `suspend` sans configuration [D]. Le setter public mappe `suspend` sur : pas d'assertion near-suspended, throttling RunningBoard actif, abandon de l'assertion après délai ([`WKPreferences.mm`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKPreferences.mm), l. 182-208).
- **Délais** [É main] : assertion near-suspended abandonnée après `removeAllAssertionsTimeout` = **4 min** ([`ProcessThrottler.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/ProcessThrottler.cpp)) ; `defaultWebProcessSuspensionDelay` = **4 min**, **10 s** après un événement de pression mémoire (« fast suspension ») ([`WebProcessPool.cpp`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/WebProcessPool.cpp), `webProcessSuspensionDelay`). Cette dernière logique vient du bug [281702](https://bugs.webkit.org/show_bug.cgi?id=281702) (« Suspend processes aggressively on critical memory pressure », corrigé en 2024) [É]. Les délais ne sont pas réglables en API publique [D].
- **Process cache et pression** : voir §1.5.
- **Pression mémoire dans WebKit** [É main] : `WebProcessPool` surveille la pression système (`DISPATCH_MEMORYPRESSURE_WARN`/`CRITICAL`) et propage un événement de pression à tous les WebContent, qui vident leurs caches. Ce n'est **pas** un déchargement d'onglet.
- **Jetsam** : un WebContent peut être tué par le système ; l'app l'apprend par `webViewWebContentProcessDidTerminate` [É] (SDK 27). Le bug [252189](https://bugs.webkit.org/show_bug.cgi?id=252189) (2023, corrigé) montrait des WebContent d'arrière-plan tués agressivement par le gestionnaire de mémoire basse quand la suspension était activée [É, sur la foi du titre et du résumé]. Il faut donc attendre des rechargements spontanés.
- **Back/forward cache** : `willUseInstantBack` dans `WKNavigationDelegate` indique des pages **suspendues en mémoire** pour les retours rapides [É] (SDK 27). Elles pèsent dans la RAM mesurée ; capacité 2 pages pour ≥ 512 Mo en modèle navigateur (§1.5) [É main].
- **App Nap** : concerne le process de l'app elle-même (minuteries regroupées si fenêtre occultée). Les minuteries de décision de Safira peuvent donc être retardées ; utiliser une tolérance explicite et réévaluer au réveil (§3) [D].

### 1.7 Ce que Safari fait que Safira n'obtient pas automatiquement

- **Documenté par Apple** : rien trouvé sur une politique de déchargement d'onglets Safari (recherche sur support.apple.com et webkit.org) [NV]. Un article tiers de 2021 (Eclectic Light) affirme qu'un onglet ouvert garde son process jusqu'à la fermeture de Safari [NV, tiers, ancien].
- **Safira peut obtenir** : la suspension (§1.6), le cache de processus et le modèle de cache « navigateur » (§1.5, si enregistrée pour `http`/`https`) [D].
- **Safira ne peut pas obtenir** [D] : tout ce qui passe par des SPI/entitlements privés d'Apple (par exemple `_WKProcessPoolConfiguration`, l'identifiant de process d'une vue, les API de gestion des onglets du système). Le cadrage interdit les SPI. L'écart exact avec Safari ne peut pas être listé sans mesure : c'est le but du bras S (§5) [NV].

---

## 2. Pratiques des autres navigateurs

| | Chrome (Memory Saver) | Edge (onglets en veille) | Firefox (TabUnloader) | Arc | Zen |
| --- | --- | --- | --- | --- | --- |
| **Déclencheur** | Minuteur d'inactivité ; en plus, déchargement « urgent » sous pression mémoire | Minuteur d'inactivité ; sous pression modérée, gel avant rejet | **Pression mémoire seulement** (niveau critique macOS) | Minuteur (archivage) | Réglage de minuteur exposé (voir ci-contre) ; algorithme hérité de Firefox |
| **Délai par défaut** | 2 h / 4 h / 6 h selon le mode (code) | **15 min** (doc de politique) ; 5 min en économie d'énergie maximale, 30 min ou 15 min (< 6 Go) sinon | ≥ **10 min** depuis le dernier accès (préférence) | **12 h**, non désactivable | Préférence `zen.tab-unloader.timeout-minutes`, défaut **10** |
| **Exclusions** | Audio/vidéo/appel, partage d'écran, notifications, téléchargement, formulaire partiellement rempli, périphérique USB/Bluetooth, onglet épinglé, liste de sites à garder actifs | « Heuristiques » : notifications, son, vidéo en flux ; liste de sites bloqués | Onglet sélectionné, média, PiP, WebRTC, onglets privés ; épinglé = priorité basse | Onglets épinglés/favoris exclus | Liste `zen.tab-unloader.excluded-urls` ; onglet « mode Zen actif » exclu |
| **Perte de données** | Ne décharge pas si formulaire/édition utilisateur | non documenté [NV] | `beforeunload` respecté ; état vidé vers la session avant le déchargement | n/a (archivage) | hérité de Firefox |

Sources et détail :

**Chrome** :
- Aide officielle : onglets exclus = « audio ou vidéo, appels, partage d'écran, pages avec notifications, téléchargements actifs, formulaires partiellement remplis, onglets épinglés, périphériques USB ou Bluetooth connectés » ; liste « Always keep these sites active » avec hôtes et chemins ; les modes ne précisent aucune durée ([support.google.com/chrome/answer/12929150](https://support.google.com/chrome/answer/12929150)) [É].
- Code (Chromium main) : délais `Hours(6)` (conservateur), `Hours(4)` (moyen), `Hours(2)` (agressif) ([`memory_saver_mode_policy.cc`](https://github.com/chromium/chromium/blob/main/chrome/browser/performance_manager/policies/memory_saver_mode_policy.cc)) ; **un onglet revisité plus de 5 fois (mode conservateur) ou 15 fois (autres) n'est jamais programmé** pour le discard ; le minuteur ne compte pas le temps de veille de la machine (`elapsed_not_suspended`) [É].
- Règles d'éligibilité : visible, vu dans les **10 min** (hors ChromeOS/Android), audible ou audible dans la **minute**, PiP, PDF, notifications, capture caméra/micro/écran, USB/Bluetooth, **onglet actif de n'importe quelle fenêtre**, épinglé, DevTools ouvert, activité de titre/favicon en arrière-plan (proactif), **interaction de formulaire**, **modifications utilisateur** ([`discard_eligibility_policy.cc`](https://github.com/chromium/chromium/blob/main/chrome/browser/performance_manager/policies/discard_eligibility_policy.cc), [`.h`](https://github.com/chromium/chromium/blob/main/chrome/browser/performance_manager/policies/discard_eligibility_policy.h)) [É]. Le discard « urgent » (pression mémoire) applique les mêmes exclusions que le proactif, sauf « activité en arrière-plan ».
- La page `developer.chrome.com/docs/performance/memory-saver` n'existe pas (404) ; l'article de 2015 sur le tab discarding ne décrit pas la fonction actuelle.

**Edge** :
- Politique `SleepingTabsTimeout` : défaut 900 s, choix de 30 s à 12 h ; en économie d'énergie, le plus court de ce délai et du délai d'économie d'énergie ([doc Microsoft](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/sleepingtabstimeout)) [É].
- Politique `SleepingTabsEnabled` : « heuristics to avoid putting tabs to sleep that do useful work in the background, such as display notifications, play sound, and stream video » ; sites bloqués par `SleepingTabsBlockedForUrls` ; si désactivé, le système peut quand même geler des onglets sous pression modérée ([doc Microsoft](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/sleepingtabsenabled)) [É].
- Une source secondaire indiquait 2 h : la doc Microsoft du jour (mise à jour 2026-10-07) dit 15 min. **Retenir 15 min.**

**Firefox** :
- Code ([`TabUnloader.sys.mjs`](https://github.com/mozilla-firefox/firefox/blob/main/browser/components/tabbrowser/TabUnloader.sys.mjs)) [É] :
  - critères et poids : non déchargeable (onglet sélectionné ou marqué), PiP, média, WebRTC, privé = `NEVER_DISCARD` ; chargement en cours = 8 ; épinglé = 2 ;
  - tri par poids puis par ordre d'accès ; pour plus de 10 onglets (`MIN_TABS_COUNT`), les 10 plus récents sont écartés du recalcul ; puis repondération par **nombre de process propres à l'onglet** et par **mémoire** ;
  - un onglet accédé dans les `min_inactive_duration_before_unload` ms **n'est pas déchargé**.
- Préférences ([`firefox.js`](https://github.com/mozilla-firefox/firefox/blob/main/browser/app/profile/firefox.js)) [É] : `browser.tabs.unloadOnLowMemory` = vrai sur Mac et Windows ; `min_inactive_duration_before_unload` = **600000 ms** ; sur Mac, `browser.lowMemoryResponseMask` = **0 en release** (3 en Nightly seulement), niveau « critical » par défaut, sondage toutes les 10 s pendant le niveau bas ([`AvailableMemoryWatcherMac.cpp`](https://github.com/mozilla-firefox/firefox/blob/main/xpcom/base/AvailableMemoryWatcherMac.cpp)). **En release sur Mac, Firefox ne décharge donc rien automatiquement** (lecture du fichier de préférences ; comportement réel non testé [NV]).
- Préservation des données ([`Tabbrowser.sys.mjs`](https://github.com/mozilla-firefox/firefox/blob/main/browser/components/tabbrowser/Tabbrowser.sys.mjs), `#mayDiscardBrowser`, `prepareDiscardBrowser`) [É] : `permitUnload("dontUnload")` (un `beforeunload` qui demanderait confirmation **bloque** le déchargement), refus s'il y a une boîte de dialogue ouverte, et `TabStateFlusher.flush` avant le déchargement pour que la restauration ait l'état le plus récent.

**Safari** : aucune documentation Apple trouvée sur le déchargement ou la mise en veille d'onglets [NV].

**Arc** :
- Archivage automatique des onglets non épinglés après **12 h** par défaut, non désactivable, réglable dans les réglages ; épingler ou mettre en favori évite l'archivage ([centre d'aide Arc](https://resources.arc.net/hc/en-us/articles/19228855311127)). Le fetch direct de cette page a renvoyé 403 : le contenu repose sur le résumé d'une recherche web [É partiel].
- L'archivage retire l'onglet de la barre (≠ mise en veille). Une éventuelle « mise en veille » d'onglets Arc distincte : aucune documentation officielle trouvée [NV].

**Zen** :
- Zen applique un correctif sur `TabUnloader` de Firefox : exclut les onglets en « mode Zen actif » et itère sur `gZenWorkspaces.allStoredTabs` ([`TabUnloader-sys-mjs.patch`](https://github.com/zen-browser/desktop/blob/main/src/browser/components/tabbrowser/TabUnloader-sys-mjs.patch)) [É].
- Préférence `zen.tab-unloader.timeout-minutes`, valeur par défaut 10 dans `zen-settings.js` ([source](https://github.com/zen-browser/desktop/blob/main/src/browser/components/preferences/zen-settings.js)) [É]. Le code qui consomme ce réglage n'a pas été localisé : le sens exact (délai d'inactivité minuteur ou plancher avant déchargement) est [NV].
- Doc officielle : `zen.tab-unloader.excluded-urls` (liste d'URL exemptées), `zen.tabs.dim-pending` (grise les onglets déchargés) ([about-config-flags](https://github.com/zen-browser/docs/blob/main/content/docs/guides/about-config-flags.mdx)) [É].

**Enseignements** :
- [D] Tous les navigateurs sérieux exigent (a) **jamais** l'onglet actif, (b) un son/une capture = protégé, (c) un état utilisateur non sauvegardé = protégé ou vidé avant de décharger.
- [D] Le déchargement **minuté** va de 10 min (Zen, plancher Firefox) à 12 h (Arc) ; 15 min est le plus agressif documenté par un grand éditeur (Edge).
- [D] La priorité sous pression est : exclusions dures → LRU → pondération par ressources (Firefox) ; épinglé = dernier à partir, pas intouchable (Firefox) ou intouchable (Chrome, Arc).

---

## 3. Signaux macOS publics

| Signal | API | Dispo | Valeurs | Remarques |
| --- | --- | --- | --- | --- |
| Pression mémoire | `DispatchSource.makeMemoryPressureSource(eventMask:queue:)` ; `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` | macOS 10.9 | `.normal`, `.warning`, `.critical` | L'en-tête GCD avertit : ne **pas** parcourir et jeter les caches existants à l'entrée en pression élevée, car cela peut aggraver la pression par opérations VM [É] (`dispatch/source.h`, SDK 27). **À concilier avec le discard** [D] : détruire une vue libère un process entier, mais sérialiser et capturer des images consomme de la mémoire ; faire ces opérations **avant** la pression (à la perte de focus), pas pendant. |
| Niveau courant | `sysctl kern.memorystatus_vm_pressure_level` (non documenté Apple) | — | 1, 2, 4 | Observé : valeur **2** sur ce Mac au moment de la recherche [É local]. Correspondance 1/2/4 = normal/warn/critical : [D] d'après les constantes GCD. Utile en script de mesure. |
| État thermique | `ProcessInfo.thermalState` + `thermalStateDidChangeNotification` | macOS 10.10.3 | `.nominal`…`.critical` | Notification publiée sur la file globale [É] (`NSProcessInfo.h`). |
| Mode économie d'énergie | `ProcessInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChangeNotification` | **macOS 12** | booléen | [É] (`NSProcessInfo.h`). |
| Batterie / secteur | IOKit : `IOPSCopyPowerSourcesInfo`, `IOPSNotificationCreateRunLoopSource`, clés `kIOPSPowerSourceStateKey` | macOS | secteur/batterie, pourcentage | Pas d'API Foundation équivalente [D]. |
| Activité / App Nap | `ProcessInfo.beginActivity(options:reason:)` | macOS 10.9 | options `NSActivity…` | Sert à empêcher l'App Nap du process de Safira pendant un travail de bascule ; **ne pas** le tenir en continu (coût énergétique, avertissement de l'en-tête) [É]. |
| Horloge | `SuspendingClock` (macOS 13) | — | s'arrête pendant la veille | Pour mesurer « temps d'inactivité » sans compter la veille de la machine, comme le fait Chrome [É] ([doc Swift](https://developer.apple.com/documentation/swift/suspendingclock)). `ContinuousClock` compte la veille. |

**Combinaison recommandée** [D, valeurs à régler par mesure] :

- Calculer un **multiplicateur de délai** à partir d'un état unique, avec hystérésis (un état dure au moins 30 s) :
  - `normal`, secteur, `nominal`/`fair` : ×1 ;
  - économie d'énergie, ou batterie < 20 % hors secteur, ou thermique `.serious` : ×(1/3) ;
  - `.warning` : délai plafonné à 10 min ;
  - `.critical` ou thermique `.critical` : décharger le meilleur candidat éligible maintenant, puis un toutes les 10 s tant que le niveau reste `.critical` (schéma de sondage de Firefox, 10 s).
- Edge applique déjà ce principe : en économie d'énergie, le délai effectif est le plus court des deux délais [É] (doc Microsoft ci-dessus). Les facteurs numériques ci-dessus sont des choix de départ, pas des mesures.
- Le minuteur de décision tourne sur `DispatchSourceTimer` avec tolérance explicite, et la décision se **réévalue au réveil** de la machine et au retour du premier plan, car App Nap peut regrouper ou retarder les minuteries [D].

---

## 4. Recommandation : règle par onglet

### 4.1 Machine à états

```
Actif ──(désélectionné)──▶ Caché ──(éligible depuis ≥ D)──▶ Libéré ──(sélectionné)──▶ Actif
         snapshot (disque)   isHidden = true,                 WKWebView détruite,
         interactionState    WebKit suspend le WebContent      snapshot affiché,
         mis en cache        (≈ 4 min, §1.6)                   état en mémoire/disque
```

- **Caché** : la vue reste vivante, `isHidden = true`, `inactiveSchedulingPolicy = .suspend` (explicite, pour ne pas dépendre du défaut lié au SDK) [D].
- **Libéré** : après sérialisation de l'état, retrait de la hiérarchie, nettoyage des handlers et délégués, destruction.
- Le **snapshot est pris à la désélection**, pas à la libération (vue encore visible, `afterScreenUpdates` : comportement hors écran [NV]), encodé sur disque (§1.2).

### 4.2 Éligibilité : exclusions

Un onglet est **protégé** (jamais libéré par le minuteur, et dernier recours sous pression sauf mention) si l'une des conditions est vraie :

| # | Condition | Détection en API publique | Pratique de référence | Statut |
| --- | --- | --- | --- | --- |
| 1 | Onglet sélectionné d'une fenêtre, ou visible | état de l'app | tous | [É] |
| 2 | Lit un média (`.playing`) ou en a lu un depuis < 60 s | `requestMediaPlaybackState` interrogé à la perte de focus puis périodiquement ; `.paused`/`.suspended` : voir ci-dessous | Chrome (audible + 1 min) ; Firefox ; Edge | [D] (ne distingue pas muet/audible : surprotège un peu) |
| 3 | Capture caméra ou micro active ou en pause | `cameraCaptureState`, `microphoneCaptureState` ≠ `.none` (KVO) | Chrome ; Firefox (WebRTC) | [D] |
| 4 | Plein écran ou PiP | `fullscreenState` ≠ `notInFullscreen` ; PiP : pas d'API [NV] | Chrome ; Firefox | [D] partiel |
| 5 | Téléchargement actif lié à l'onglet | suivi par l'app des `WKDownload` | Chrome | [D] |
| 6 | Chargement en cours | `isLoading` | Firefox (poids bas) | [D] |
| 7 | Formulaire modifié / édition utilisateur | script utilisateur en monde isolé : écoute `input`/`change` en capture, remise à zéro sur `submit`/navigation | Chrome (`kFormInteractions`, `kUserEdits`) | [D] |
| 8 | Boîte de dialogue JS en attente | l'app tient le `completionHandler` du `WKUIDelegate` | Firefox (dialogue ouvert = refus) | [D] |
| 9 | Activité en arrière-plan | changements de `title` (KVO) ou du favicon pendant le masquage | Chrome (`kBackgroundActivity`, minuteur seulement) | [D] |
| 10 | Épinglé | état Safira | Chrome, Arc : protégé ; Firefox : poids 2 | choix produit, voir 4.3 |
| 11 | Règle de site « garder actif » ou onglet « ne jamais dormir » | table utilisateur | Chrome (liste de sites), Edge (liste), Zen (`excluded-urls`) | [É] pratique |
| 12 | Onglet lié par `window.opener` à un autre onglet | suivi de l'app via `createWebViewWith` | non documenté chez les autres | [D] : détruire casse le lien |
| 13 | Revisité plus de N fois récemment | compteur app | Chrome (5 ou 15 visites) | [É] pratique ; N = 5 par défaut [D] |
| 14 | `beforeunload` actif | **non détectable** en API publique sans hook du monde de la page | Firefox le respecte | [NV] : limite assumée (§4.6) |

Média en pause (`.paused`) ou `.suspended` : l'onglet n'est pas protégé, mais son délai est **doublé** (une vidéo en pause garde une position de lecture que `interactionState` ne capture pas) [D].

### 4.3 Délai, priorité, valeurs par défaut

Valeurs par défaut proposées, **à valider par la mesure** (tous [D]) :

| Paramètre | Défaut | Justification |
| --- | --- | --- |
| Délai de base `D` (non-visibilité continue, horloge hors veille) | **30 min** | Plus long que le plus agressif documenté (Edge 15 min, Zen 10, Firefox ≥ 10) : moins de rechargements surprenants ; plus court que Chrome (2 h minimum). La suspension WebKit (4 min) couvre déjà l'essentiel du coût CPU. |
| Épinglés | exclus du minuteur (délai `∞`), libérables sous `.critical` en dernier | Chrome, Arc ; Firefox les libère en dernier recours. |
| `.warning` | `D` plafonné à 10 min | WebKit lui-même passe à 10 s de suspension sous pression (§1.6). |
| `.critical` | libérer 1 onglet éligible LRU toutes les 10 s jusqu'à retour à `.normal` | Firefox : sondage 10 s, niveau critique. |
| Économie d'énergie / batterie faible / thermique `.serious` | `D` ÷ 3 | Edge : délais courts en économie d'énergie. |
| Délai sous protection « récemment audible » | 60 s après la fin du son | Chrome. |
| Onglet visité > 5 fois | exclu du minuteur | Chrome. |

**Surcharge par onglet** (demande d'Antonin) :

```
enum TabSleepPolicy { case automatic            // règle ci-dessus
                      case neverSleep           // exclusion 11
                      case sleepAfter(Duration) } // remplace D (bornes : 1 min à 24 h)
```

Résolution : réglage de l'onglet > règle de site (motif d'hôte, comme Chrome/Zen) > réglage de l'Espace > réglage global. Les exclusions dures 1 à 9 et 12 s'appliquent **quelle que soit** la surcharge, sauf `sleepAfter` explicite de l'utilisateur sur 6 à 9 (l'utilisateur assume).

**Ordre de priorité** (qui part en premier) quand il faut libérer, sous pression ou pour tenir un plafond :

1. Seau A : onglets éligibles non épinglés, non sélectionnés dans leur Espace ;
2. Seau B : onglets éligibles qui sont l'onglet sélectionné d'un autre Espace (l'utilisateur retrouverait une image au changement d'Espace) ;
3. Seau C : épinglés éligibles ;
4. Dans un seau : le moins récemment visité d'abord ; départage éventuel par poids de la page (impossible en API publique : **pas de mémoire par `WKWebView`**, donc pas de repondération façon Firefox) [D].

### 4.4 Ce que le protocole « 20 onglets, 10 minutes » peut et ne peut pas mesurer

- À `D` = 30 min, **aucune libération n'a lieu en 10 min**. Le résultat mesuré = suspension WebKit seule [D].
- Pour juger la cible (« ≤ Safari + 15 % ») il faut donc **deux** questions séparées : (1) la suspension seule atteint-elle déjà la cible ? (bras A0) ; (2) un déchargement forcé à 5 min l'améliore-t-il, et de combien ? (bras A1, valeur 5 min = **réglage de banc**, pas un défaut produit).
- Si A0 respecte déjà la cible, la libération n'est pas nécessaire pour le critère, et sa valeur se justifie par la pression mémoire, pas par ce benchmark [D].

### 4.5 Restauration

- Recréer la `WKWebView` avec la même configuration (même `WKWebsiteDataStore`), appliquer `interactionState`, afficher le snapshot jusqu'à la première peinture (`didFinish` + un `requestAnimationFrame` signalé par message), puis le retirer.
- Les cookies et le stockage restent dans le `WKWebsiteDataStore` [D] : la session de connexion survit.
- Garder en mémoire uniquement l'`interactionState` (petit) et un chemin de snapshot ; l'image décodée est libérée (§1.2).

### 4.6 Risques

| Risque | Mécanisme | Mitigation |
| --- | --- | --- |
| Perte de formulaire | `documentState` non rafraîchi en continu (§1.1) ; JS non capturé | Exclusion 7 ; option : vider les champs vers un stockage de session par script avant libération (v2) ; ne pas libérer sans réponse du script (échec de `evaluateJavaScript` = onglet protégé) |
| Rechargement des SPA | état JS perdu ; scroll virtuel ; `Cache-Control: no-store` | Délai long par défaut ; règle de site ; indicateur visuel « onglet endormi » (comme `zen.tabs.dim-pending`) |
| Son coupé | média détecté par `requestMediaPlaybackState` | Exclusion 2 ; marge de 60 s ; muet-en-lecture protège à tort : acceptable |
| WebSocket / appels / WebRTC data channels | non détectables en API publique | Exclusions 3, 9 ; liste de sites (11) pour messageries et visioconférences ; hook du monde de la page rejeté par défaut |
| `beforeunload` ignoré | non détectable | Documenter ; liste de sites ; accepter pour la v1 [NV] |
| Mémoire non rendue (cache de process 30 min, cycle de rétention) | §1.5 | Mesure A3 ; nettoyage des handlers ; destruction sous pression, où le cache est désactivé |
| Aggravation de la pression | sérialisation et snapshot au pire moment | Les faire à la désélection ; sous `.critical`, ne détruire que (pas de nouveau snapshot) |
| Valeur de `interactionState` ancienne après mise à jour de macOS | format opaque | Garder l'URL en repli (§1.1) |
| Process tué par le système | `webViewWebContentProcessDidTerminate` | Même chemin de restauration que pour un onglet libéré |
| Boucle de rechargement | page qui plante à la restauration | Après 2 échecs, restaurer l'URL seule et marquer l'onglet `neverSleep` |

---

## 5. Mesure : protocole « 20 onglets, 10 minutes »

### 5.1 Contrôles

- Même Mac (M4, 16 Go), macOS 27.0.1, session fraîche, toutes les autres apps quittées, extensions désactivées partout, même réseau.
- **Pression mémoire initiale = normale** : `sysctl kern.memorystatus_vm_pressure_level` doit valoir **1**. (Au moment de cette recherche, la valeur locale était 2 : un banc lancé dans cet état serait faussé [É local].)
- Liste figée de **20 URL** : 10 documents/articles, 6 applications monopage publiques sans connexion, 2 pages avec vidéo non lancée, 2 pages lourdes (à choisir et geler dans le dépôt). Pour éliminer la variance réseau, servir une copie rejouée (proxy d'enregistrement/rejeu) [NV : outil à choisir].
- 5 passages par bras ; reporter médiane, min, max.

### 5.2 Bras

| Bras | Description |
| --- | --- |
| **S** | Safari, 20 onglets dans une fenêtre |
| **Z** | Zen par défaut (aucun déchargement manuel) |
| **A0** | Safira, vues cachées + `.suspend`, **aucune libération** |
| **A1** | Safira, libération à 5 min (réglage de banc) |
| **A2** | Safira, `D` = 30 min (mêmes résultats que A0 sur 10 min ; suivi à +40 min pour voir l'effet) |
| **A3** | Variantes de A1 : (a) vues retirées de la hiérarchie vs cachées ; (b) Safira déclarée `http`/`https` vs non (cache de process) ; (c) avec/sans nettoyage des handlers |

### 5.3 Procédure et mesures

1. Relever la liste des PID `com.apple.WebKit.*` existants (fichier de base).
2. Lancer le navigateur, ouvrir les 20 URL séquentiellement (5 s d'écart), laisser charger, sélectionner l'onglet n° 1, ne plus toucher. T0 = fin du dernier chargement.
3. Échantillonner toutes les 30 s pendant 10 min (et jusqu'à 40 min pour A2) : empreinte (`phys_footprint`, qui inclut la mémoire compressée) de chaque process, temps CPU, nombre de process.
4. Comparer la **somme des empreintes** (process principal + enfants + WebKit apparus après la base) à T0+10 min.
5. Critère proposé : médiane(Safira) ≤ 1,15 × médiane(Safari) **et** médiane(Safira) < médiane(Zen) d'au moins 15 % [seuils arbitraires, issus du cadrage].

L'attribution des process `com.apple.WebKit.*` à l'app est une heuristique (process apparus après la base, machine calme) : leur parent est `launchd` (PID 1), pas l'app, donc `ps` ne les rattache pas [É local] ; `launchctl procinfo` exige root [É local]. Un rattachement par « process responsable » n'a pas été trouvé en API publique [NV].

### 5.4 Autres mesures

- **Mémoire rendue** : somme avant / après la libération d'un onglet, relevée à +5 s, +60 s, +5 min (pour voir le cache de process, §1.5).
- **Latence de restauration** : du clic sur l'onglet à `didFinish` et à la première peinture ; médiane et p95 ; froid (cache HTTP vidé) et chaud ; par catégorie d'URL.
- **Matrice de perte de données** (par onglet de test) : champ texte, `textarea`, `contenteditable`, case à cocher, `<input type=file>`, position de défilement, position vidéo, état d'une SPA, session WebSocket, page de résultat POST. Pour chacun : conservé / perdu / indéterminé après libération puis restauration.
- **Coût du snapshot** : temps et taille pour largeur 640 px et pleine largeur.

### Annexe A : script d'échantillonnage

`footprint --all` exige root ; l'échantillonnage par PID fonctionne sans privilèges pour les process de l'utilisateur (testé en local). Le script a été exécuté 4 s sur Zen pour vérifier la forme du CSV.

```bash
#!/bin/bash
# Usage: bench-ram.sh <label> <main_pid> <duration_s> <interval_s> [baseline_webkit_pids_file]
# Écrit <label>.csv : t_s,pid,role,footprint_bytes,cpu_time_s
# Rôles : main | child (descendant du pid principal, ex. Zen/Firefox) | webkit (com.apple.WebKit.* apparu APRÈS la baseline)
# Baseline : ps -axo pid=,command= | awk '/com\.apple\.WebKit\./ && !/awk/ {print $1}' > base.txt   (avant de lancer le navigateur)
set -u
label=$1; main=$2; dur=$3; step=$4; base=${5:-}
out="$label.csv"; echo "t_s,pid,role,footprint_bytes,cpu_time_s" > "$out"
tmp=$(mktemp -d)
descendants() {
  ps -axo pid=,ppid= | awk -v root="$1" '{p[$1]=$2} END{print root; for(i=0;i<20;i++){n=0; for(k in p) if(!(k in seen) && (p[k]==root || (p[k] in seen))){seen[k]=1; print k; n++} if(!n)break}}'
}
cputime_s() { ps -o time= -p "$1" 2>/dev/null | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print 0 }'; }
t0=$(date +%s)
while :; do
  now=$(( $(date +%s) - t0 ))
  { descendants "$main" | awk -v m="$main" '{print $1, ($1==m?"main":"child")}'
    ps -axo pid=,command= | awk '/com\.apple\.WebKit\.(WebContent|Networking|GPU)/ && !/awk/ {print $1, "webkit"}' |
      { if [ -n "$base" ] && [ -f "$base" ]; then grep -v -F -w -f "$base" ; else cat; fi; }
  } | sort -u -k1,1n | while read -r pid role; do
      footprint -p "$pid" -j "$tmp/f.json" >/dev/null 2>&1 || continue
      fp=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['total footprint'])" "$tmp/f.json" 2>/dev/null) || continue
      echo "$now,$pid,$role,$fp,$(cputime_s "$pid")" >> "$out"
    done
  [ "$now" -ge "$dur" ] && break
  sleep "$step"
done
rm -rf "$tmp"
awk -F, 'NR>1{s[$1]+=$4} END{for(t in s) printf "%s %.1f MiB\n", t, s[t]/1048576}' "$out" | sort -n | tail -1
```

Notes sur le script :
- Pour Safari et Safira, passer en `main_pid` le PID de l'app ; les process WebKit sont repris par la base de comparaison.
- Pour Zen/Firefox, les process enfants sont retrouvés par l'arbre `ppid` (rôle `child`).
- Le temps CPU mesuré (`ps time`) est cumulé ; le CPU au repos = différence entre deux instants / durée.

---

## 6. Points ouverts

1. **Le discard est-il nécessaire ?** Mesurer A0 contre S avant tout développement : si la suspension seule respecte la cible, la libération ne se justifie que par la pression mémoire [NV].
2. **Cache de process** : Safira déclarée navigateur garde-t-elle effectivement 30 min les processus des onglets détruits sur macOS 27.0.1 ? Le code lu est `main`, pas la branche livrée [NV].
3. **Fraîcheur de `interactionState`** : tester sur une page de test la présence du texte saisi, de la position de défilement et de la position vidéo, sans navigation intermédiaire [NV].
4. **Comportement de `takeSnapshot`** sur vue cachée ou hors fenêtre [NV].
5. **Un `WKDownload` survit-il à la destruction de sa `WKWebView` ?** [NV].
6. **Détection de PiP, `beforeunload`, WebSocket** : aucune API publique ; décider si le hook du monde de la page est acceptable (compatibilité et empreinte) ou si la liste de sites suffit [NV].
7. **Zen** : retrouver le code qui consomme `zen.tab-unloader.timeout-minutes` pour confirmer sa sémantique [NV].
8. **Arc** : page d'aide en 403 au fetch direct ; vérifier le texte intégral, et l'existence d'une mise en veille distincte de l'archivage [NV].
9. **Safari** : aucune politique documentée ; l'écart réel de RAM ne se connaîtra que par le bras S [NV].
10. **Stabilité du format d'`interactionState`** entre versions de macOS [NV].
11. **Rattachement des process WebKit à l'app** pour la mesure : l'heuristique « apparus après la base » suffit-elle, ou faut-il un outil avec privilèges ? [NV].
12. **Valeurs par défaut** (30 min, ÷3, 10 min, 5 visites, 60 s) : tous [D], à ajuster après les bras A0 à A3.
