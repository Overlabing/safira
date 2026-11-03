# Safira : périmètre de la v1

Document de cadrage issu de la séance de questions du 2026-11-03. Il fixe ce que la v1 contient, ce qu'elle exclut et les risques acceptés. Aucun code n'existe encore. Les numéros Q renvoient aux questions posées à Antonin.

Documents liés : `conformance-bench-plan.md` (extensions), `research-tab-discarding.md` (libération d'onglets).

## 1. But

Un navigateur macOS natif, en Swift sur `WKWebView`, avec l'UX d'Arc et de Zen. Priorités : vie privée, rapidité, RAM et CPU, UX. Le nom est **Safira** (Q15).

## 2. Contraintes fixées

| Sujet | Décision |
|---|---|
| Plateforme | macOS 27 et plus (Q3), Apple Silicon |
| API | **API publique uniquement** : pas de SPI, pas de WebKit embarqué ni de fork (Q21) |
| Distribution | DMG notarisé avec le certificat Developer ID existant, pas de Mac App Store (Q19) |
| Mises à jour | Sparkle, vérification **désactivée par défaut**, opt-in (Q23) |
| Licence | **GPL-3.0-only**, copyright Antonin Carlin (Q13) ; open source dès le début (Q1, Q14) |
| Hébergement | Organisation GitHub Overlabing, dépôts publics (question d'hébergement) |
| Sandbox | **App Sandbox activée dès la coquille** (Q9). Conséquence : la recherche de l'équipe Slack par le picker passe par un dossier accordé par l'utilisateur ou disparaît ; le Native Messaging des extensions demandera plus tard des exceptions de fichiers. |
| Identifiant de bundle | `com.overlabing.safira` (Q11), choix d'Antonin. Oisillon utilise `com.overglass.oisillon`. |
| Langues et accessibilité | Français et anglais dès la v1, entièrement utilisable au clavier et avec VoiceOver (Q41). **Clés de localisation en anglais**, le français est une traduction (Q14) ; le glossaire est en anglais. |
| Public | Antonin d'abord ; la v1 n'est **pas** utilisable au quotidien tant que les extensions manquent |

## 3. Modèle

- **Profil** (Pro, Perso) : frontière de sécurité. Un `WKWebsiteDataStore` identifié par profil ; historique, téléchargements et réglages de recherche propres. Rien n'est partagé entre profils, sauf l'apparence (Q4).
- **Space** : plusieurs par profil. Les Spaces d'un même profil partagent les cookies et les logins (Q17).
- **Une seule fenêtre** avec bascule de profil dans la sidebar (Q2). Le profil se reconnaît à la teinte de la sidebar et à l'icône du Dock, le Space à un emoji et une légère teinte (Q27).
- **Cloisonnement strict** : command bar et recherche limitées au profil actif, aucun onglet déplaçable d'un profil à l'autre, un lien cliqué dans une page reste dans le profil actif (Q8, Q10).
- Onglets **épinglés par Space** (pas d'Essentials) et **dossiers** par Space ; pas de favoris classiques (Q18, Q42).
- **Fenêtre privée** par profil : data store non persistant, sans historique, sans Spaces (Q26).
- Le modèle de profil réserve un emplacement pour une **configuration réseau**, appliquée avant la création du data store (voir §8).
- **Fenêtres** : une fenêtre principale pour tous les profils et Spaces, plus des fenêtres privées à la demande, chacune rattachée à un profil (voir `GLOSSARY.md`). Les popups d'authentification (OAuth, connexion Google) s'affichent dans un **panneau flottant** rattaché à la fenêtre principale, qui se ferme à la fin de la connexion : autre exception à « une seule fenêtre » (Q15).
- Un **Folder** ne contient que des onglets épinglés et d'autres dossiers ; les onglets ouverts vivent hors des dossiers.
- **Profil inactif** : ses onglets continuent de tourner (son, notifications web), WebKit décide seul de les suspendre (Q6).
- **Suppression** : supprimer un Space ferme ses onglets et dossiers mais garde les logins et l'historique du profil ; supprimer un Profile efface tout (logins, historique, Spaces) après une confirmation qui nomme le profil, sans retour possible (Q7).

## 4. Fonctions de la v1

- Sidebar verticale et **mode compact** (apparition au bord gauche ou par raccourci) (Q16, Q35).
- Command bar (⌘T / ⌘L) limitée au profil actif.
- **Web Inspector** : avec l'API publique, il s'ouvre dans le menu Développement de **Safari** (`isInspectable`), pas dans une fenêtre de Safira (Q10). Et **gestionnaire de téléchargements** par profil (Q16).
- Restauration paresseuse de la session : profils, Spaces et onglets sont restaurés, seul l'onglet visible et les épinglés **du profil visible** se rechargent au lancement (Q31, Q12) ; ceux d'un autre profil se chargent à la première bascule. Ces rechargements sont des requêtes réseau, donc « aucune requête au lancement » ne vaut pas pour les onglets épinglés.
- **Picker de liens** : Safira est le navigateur par défaut. Port générique de `ZenPicker` (règles par host, chemin et app d'origine dans un fichier JSON, ouverture directe dans Slack, Linear, Notion et Figma, panneau qui sort du notch). Les heuristiques propres au setup d'Antonin (artifacts Claude, projets `macadam-*`) restent hors du dépôt, en règles utilisateur (Q25). Un lien externe s'ouvre en nouvel onglet dans le **dernier Space actif** du profil cible, et la sidebar bascule vers ce profil ; une règle peut nommer un Space précis, et **une option** (désactivée par défaut) fait demander aussi le Space par le picker (Q4).
- **Pas de doublons** : si le lien (adresse normalisée) correspond à l'adresse actuelle d'un onglet du profil cible, onglets non chargés compris, Safira bascule vers cet onglet au lieu d'en ouvrir un nouveau ; un bandeau discret propose de l'ouvrir quand même dans un nouvel onglet. Le picker ne devine jamais le profil : il met en avant ceux où le lien est déjà ouvert. Réglage activé par défaut (visible à l'onboarding), et une règle peut forcer un nouvel onglet. Les fenêtres privées ne sont jamais cherchées (Q17 à Q20).
- **Presets de raccourcis** Zen, Arc et Safari choisis à l'onboarding, modifiables (Q35, Q37).
- **Couleurs par Space** : palette de dégradés, teinte propagée (Q46, voir §7).
- **Onboarding** : premier profil, preset de raccourcis, moteur de recherche, navigateur par défaut avec le picker, rappel que rien n'est envoyé sans action. **Tout ce qui a été accepté « par défaut » dans cette séance y figure et reste modifiable** (Q37).

## 5. Vie privée

- **Zéro télémétrie.**
- **Mode debug opt-in** sur le modèle d'Oisillon (`DiagnosticsExport`) : journaux locaux, hôte des sites seulement (sans chemin ni paramètres), erreurs, temps de chargement, état mémoire ; jamais de contenu de page, de cookies ni de titres d'onglets ; export manuel via un zip, jamais envoyé automatiquement (Q6, Q32).
- **HTTPS d'abord** : pour toute adresse saisie sans schéma, avertissement avant tout repli en HTTP (Q34).
- **Suggestions de recherche distantes désactivées** par défaut ; les suggestions locales (historique, onglets du profil actif) restent actives (Q30).
- **Moteur de recherche** : aucun moteur imposé, choix au premier lancement (Q29).
- **Pas de blocage de pubs dans la v1** : il viendra d'une extension, ou du routeur de l'utilisateur (Q38).
- **Mots de passe** : pas de gestionnaire intégré. Ils passent par une extension (Verrou, 1Password) (Q12).

## 6. Performance

- Cible RAM : environ 20 onglets au repos après 10 minutes, empreinte proche de Safari (à 15 % près, seuil arbitraire) et nettement sous Zen (Q5).
- **Pas de libération d'onglets en v1** : on s'appuie sur la suspension de WebKit (`inactiveSchedulingPolicy`) (Q40). La recherche montre que suspendre ne libère pas la RAM, donc la libération pourra revenir si la mesure l'exige.
- Protocole : mesure de Safira sans libération (bras A0), Safari et Zen. Le Mac doit être au repos : au moment de la recherche, sa pression mémoire était à « warn ».
- Q7 et Q24 sont remplacées par Q40 : pas de règle de libération des profils ou Spaces inactifs en v1.

## 7. Module de couleurs (dépôt séparé)

- **Dépôt séparé sous licence MIT** (Q43), dont dépendent Safira (GPL-3.0) et Oisillon (fermé, App Store). Safira ne pourrait pas l'héberger lui-même sans empêcher Oisillon de l'utiliser.
- **Extrait d'Oisillon** : dégradés fixes (qui deviennent les préréglages), résolution clair/sombre (`SpaceColorResolution` et jumeaux AppKit/UIKit), lisibilité (`SpaceLegibility`), fond dégradé et propagation de la teinte. Le code d'Oisillon ne permet **pas** de personnalisation (Q44).
- **Nouveau** : modèle de couleurs libres et **sélecteur façon Arc/Zen** (Q45).
- **Calendrier** : la v1 de Safira utilise la palette de préréglages ; le sélecteur complet (couleurs libres, grain) vient après la v1 (Q46). Oisillon adopte le module plus tard, sans bloquer Safira.
- Cibles de plateforme du module : **macOS 26 et iOS 26**, car `OisillonKit` déclare `.macOS(.v26), .iOS(.v26)` (l'architecture l'a relevé). Safira, elle, vise macOS 27.

## 8. Après la v1

| Sujet | État |
|---|---|
| **Extensions** | Hors de la coquille. Elles sont **sur le chemin critique de l'usage quotidien** (mots de passe). Le go/no-go sur le support des extensions Chrome n'est que reporté (Q22), voir §9 et `conformance-bench-plan.md`. Portée : extensions manifest via `WKWebExtension`, sans SPI ; pas de `.appex` Safari (Q20). |
| **Proxy par profil** (WireGuard intégré, en proxy local, `proxyConfigurations`) | Ne sort que si un **test de fuite** passe (DNS, WebTransport, WebAuthn d'origines liées, WebRTC). Trois fuites WebKit documentées en août 2026 contournent `proxyConfigurations` ; s'appelle « proxy par profil » tant que le test n'est pas validé. OpenVPN écarté. |
| **Sélecteur de couleurs complet** | Voir §7. |
| **Libération d'onglets** | Seulement si la mesure A0 l'exige ; `research-tab-discarding.md` donne la machine à états. |
| Hors périmètre à ce stade | Split view, synchronisation, import depuis Zen ou Arc, favoris classiques, Mac App Store |

## 9. Risques acceptés

1. **Les extensions sont testées après la coquille** (Q22, décision d'Antonin contre la recommandation du test rapide d'abord). Si elles échouent, la coquille construite ne sera pas utilisable au quotidien. Le go/no-go d'origine (« sans extensions Chrome, on abandonne ») n'est pas levé.
2. `WKWebExtension` du macOS actuel n'a ni `offscreen`, ni `sidePanel`, ni `bookmarks` d'après le banc (voir son plan) ; MetaMask et uBlock Origin Lite en ont besoin.
3. Pas de blocage de pubs intégré : tant que les extensions ne sont pas là, Safira protège moins que Zen avec uBlock Origin.
4. Passkeys : l'entitlement `com.apple.developer.web-browser.public-key-credential` exige un formulaire réservé à l'Account Holder, hors périmètre de la v1.

## 10. Définition de « v1 terminée » (Q36)

Profils étanches vérifiés par test (cookies, historique, onglets) ; Spaces et épinglés ; command bar ; picker en navigateur par défaut ; HTTPS d'abord ; mode privé ; mode debug ; onboarding avec les choix par défaut ; couleurs par Space (palette) ; cible RAM mesurée contre Safari et Zen. Les extensions et les mots de passe sont hors v1.

## 11. Confié à l'architecture (Q39)

Pile technique, stockage par profil, découpage en modules, tests, CI, pipeline DMG et notarisation, intégration de Sparkle, structure du module de couleurs. Livrable : `architecture-v1.md`, que valide Antonin.

## 12. Choix « par défaut » exposés à l'onboarding

Tout ce qui a été accepté « par défaut » pendant la séance doit être visible et modifiable à l'onboarding (Q37). Liste compilée depuis les décisions :

| Réglage | Valeur par défaut | Origine |
|---|---|---|
| Vérification des mises à jour (Sparkle) | **Désactivée**, opt-in ; bouton « Rechercher les mises à jour » | Q23 |
| Suggestions de recherche distantes | **Désactivées** ; les suggestions locales (historique, onglets du profil actif) restent actives | Q30 |
| Moteur de recherche | **Aucun imposé**, choisi au premier lancement | Q29 |
| HTTPS d'abord | **Activé**, avertissement avant tout repli en HTTP | Q34 |
| Mode debug (journaux locaux masqués) | **Désactivé** ; export manuel, hôte seulement | Q6, Q32 |
| Navigation sécurisée de WebKit (avertissement de sites frauduleux) | **Activée** ; elle peut consulter un service tiers, à expliquer | Q16 |
| Son en lecture automatique | **Bloqué** | Q16 |
| Doublons de liens externes (onglet correspondant) | **Activé** ; une Link rule peut forcer un nouvel onglet | Q20 |
| Le picker demande aussi le Space | **Désactivé** | Q4 |
| Preset de raccourcis | **Choisi** parmi Zen, Arc, Safari | Q35 |
| Safira navigateur par défaut (avec le picker) | **Proposé** | Q37 |
| Restauration de session | **Paresseuse** (profil visible et épinglés) | Q31, Q12 |

Informations affichées sans réglage : aucune télémétrie ; la fenêtre privée n'enregistre rien ; aucun blocage de pubs ni gestionnaire de mots de passe intégré.

### Exceptions à « rien n'est partagé entre profils » et à « aucune requête au lancement »

- Le **picker** et les **journaux de diagnostic** couvrent tous les profils.
- Recharger les **onglets épinglés du profil visible** au lancement fait des requêtes réseau (Q12).
- Les **popups d'authentification** et les **fenêtres privées** sont des fenêtres en plus de la principale (Q3, Q15).

## 13. Décisions de la relecture de l'architecture (2026-11-03)

Elles complètent ou corrigent les sections ci-dessus ; le détail et les références sont dans `architecture-v1.md` §13.

- **Ajouts à la v1** : commande par Profile « Effacer l'historique et les données de sites » avec plage (D2) ; création des Link rules depuis le Link picker, liste dans les réglages, import et export JSON (D11) ; confirmation avant d'ouvrir un lien non web (`mailto:`, `slack:`…), mémorisée par Profile et par schéma (D12) ; ⇧⌘T pour rouvrir un onglet fermé de la session, en mémoire seulement (D5) ; mesure de mémoire précoce dès la liste d'onglets (D8).
- **Vie privée** : l'état de navigation d'un onglet est enregistré en entier seulement si la page n'a ni champ mot de passe ni corps POST, sinon adresse seule (D1) ; l'historique reste jusqu'à effacement (D2) ; le journal du picker est opt-in, limité à l'hôte et au Profile (D6) ; chaque Profile exige le choix d'un moteur de recherche à sa création (D10).
- **Link picker** : aucune présélection, choix explicite par chiffre ou flèches puis Entrée, repère sur les Profiles où le lien est déjà ouvert (D9) ; l'heuristique des artifacts Claude est abandonnée en v1 (D3) ; Slack passe par un dossier accordé une fois dans les réglages (D7).
- **Performance** : la libération d'onglets reste hors v1 **sauf** si la mesure sans libération dépasse 15 % d'écart avec Safari ; elle devient alors un ticket qui bloque la recette (D4).
- **Localisation** : clés anglaises, français traduit (remplace la convention d'Oisillon du §9.6 de l'architecture).
- **CI** : le critère « CI verte » vaut seulement si une image GitHub gratuite avec Xcode 27 existe ; sinon le script de vérification local est la porte.
