# Sidebar: rail, Tabs, Pinned tabs, Folders

Tree read from the Main window with three Tabs (French copy, then English copy). Reading order: address and page buttons,
the Tabs list, the Space rail; then the page.

| Control | Label | Role | Focusable | Result | By hand |
|---|---|---|---|---|---|
| Address field | Adresse; value: the page address; help: Ouvre la barre de commande | button | no (⌘L) | pass | owed |
| Address field placeholder | Rechercher (was “Rechercher ou s…”, truncated) | text | n/a | fixed: own short placeholder, full text in the help tag | owed |
| Back, Forward, Reload | Précédent, Suivant, Recharger | button, disabled without a page | no (⌘[, ⌘], ⌘R) | pass | owed |
| Tabs list | Onglets | group | n/a | pass | owed |
| New Tab row | Nouvel onglet | button | yes | pass | owed |
| Tab row | page title; value: host, “2 sur 3”; selected trait on the shown Tab | button | yes | pass | owed |
| Tab row actions | Fermer l’onglet (named action); context menu (AXShowMenu) with Pin, Move, Close | actions | n/a | pass | owed |
| Space rail | Espaces et profils; no menu of its own (each item has one, below) | group | n/a | pass | owed |
| Space glyph | “Espace Accueil, 1 sur 1”; selected trait; context menu for that Space, then its Profile | button | yes | pass; menu per Space since ThemeKit 0.2.8 (#109) | owed |
| Other Profile dot | “Profil Personal, 3 espaces”; hint “Ouvre Reading.”; context menu for that Profile | button | yes | fixed: ThemeKit 0.2.6 (#99), read again in #98; menu per Profile since ThemeKit 0.2.8 (#109) | owed |
| Rail + button | Ajouter ou modifier un espace ou un profil | button | yes | fixed: ThemeKit 0.2.6 (#99), read again in #98 | owed |
| Rail popover | Nouvel espace dans …, Nouveau profil…, Modifier l’espace …, Modifier le profil … | buttons | n/a | pass | owed |
| First Space name | “Home” in a French Profile | text | n/a | fixed: a new Profile names its first Space in the user’s language (Accueil) | owed |
| Pinned tab row | same row as a Tab, value adds “Épinglé” | button | yes | code | owed |
| Folder row | “Docs, 2”; value Déplié or Replié; actions Déplier/Replier, Renommer le dossier, Supprimer le dossier | button | yes | pass (value read in #98) | owed |
| Sidebar button (toolbar) | Barre latérale; help Masquer la barre latérale | button | no (⌃⌘S) | pass | owed |
| Empty page text | Saisissez une adresse ou une recherche; Appuyez sur ⌘L… | text | n/a | pass | owed |

No empty or duplicate label in the tree. Captures: `sidebar-fr.png`, `sidebar-en-light.png`, `sidebar-en-dark.png`.
