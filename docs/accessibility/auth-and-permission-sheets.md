# Sign-in panel and permission sheets

| Control | Label | Role | Focusable | Result | By hand |
|---|---|---|---|---|---|
| App link sheet | alert; « localhost » veut ouvrir un lien « mailto: »… | sheet | n/a | pass (tree read) | owed |
| Remember checkbox | Mémoriser mon choix pour les liens « mailto: » dans ce profil | checkbox | yes | pass | owed |
| Open, Don’t Open | Ouvrir, Ne pas ouvrir (Escape) | button | yes | pass | owed |
| Camera, microphone, location sheet | question naming the site; Autoriser, Refuser; remember checkbox | sheet | yes | code: WebKit holds the request until the page’s window is focused | owed |
| System prompt text | Info.plist usage descriptions in French (InfoPlist.xcstrings) | system | n/a | code | owed |
| Sign-in panel | Fenêtre de connexion; title is the site’s host, Chargement… before | panel | n/a | code: the panel comes forward when it opens | owed |
| Clear history sheet | heading Effacer l’historique… de « Profil »; Période picker with a hint; keys 1, 2, 3; Effacer names the range | sheet | yes | fixed: heading trait | owed |
| Site permissions sheet | heading; Révoquer buttons name the site and the permission; Tout révoquer, Terminé | sheet | no | fixed: heading trait | owed |
| Search engine sheet | heading Choisissez un moteur de recherche | sheet | no | fixed: heading trait | owed |

Capture: `permission-sheet-app-link-fr.png`. The HTTPS-first warning is WebKit’s page (`https-warning-fr.png`).
