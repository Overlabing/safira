# Settings: Defaults, Shortcuts, Link rules, Profile and Space editors

Trees read from each window (French).

## Defaults window

| Control | Label | Role | Focusable | Result | By hand |
|---|---|---|---|---|---|
| Title | Choix par défaut | heading | n/a | fixed: was plain text | owed |
| List | Choix par défaut; each row “title, value”, help is the explanation | outline | yes | pass | owed |
| Switch | e.g. Avertir en cas de site web frauduleux; value 0 or 1 | checkbox | Space on the row | pass | owed |
| Search engine, Shortcut preset | “Moteur de recherche, pour Profil”, Préréglage de raccourcis | pop-up | no | pass | owed |

## Shortcuts window

| Control | Label | Role | Focusable | Result | By hand |
|---|---|---|---|---|---|
| Preset | titled by Préréglage; value Aucun (raccourcis de Safira) | pop-up | no | pass | owed |
| List | Raccourcis | outline | yes | fixed: had no label | owed |
| Row | “Nouvel onglet, ⌘T, Modifier”; actions Modifier, Réinitialiser | button | n/a | pass (one element per row, so the Modifier buttons do not repeat) | owed |
| Reset All Overrides | Réinitialiser toutes les modifications | button | no | pass | owed |

## Link rules window

| Control | Label | Role | Focusable | Result | By hand |
|---|---|---|---|---|---|
| List | Règles de lien; value tells an empty list | outline | yes | fixed: the empty-list text was not in the tree | owed |
| Move Up, Move Down, Delete | Monter, Descendre, Supprimer; help with the key; disabled without a selection | button | no (⌥↑, ⌥↓, Delete) | pass | owed |
| Import | Importer | menu button | no | pass | owed |
| Export, Show in Finder | Exporter…, Afficher dans le Finder | button | no | pass | owed |
| Check fields | Lien à vérifier; Identifiant de l’app d’origine, facultatif | text field | yes | pass | owed |
| Check | Vérifier | button | no (Return) | pass | owed |

## Profile and Space editors

| Control | Label | Role | Focusable | Result | By hand |
|---|---|---|---|---|---|
| Title | Nouveau profil, Modifier l’espace | heading | n/a | fixed: was plain text | owed |
| Name, Symbol or Emoji | titled by Nom, Symbole | text field | yes | pass | owed |
| Theme | Thème; swatches named (Indigo et bleu…), selected trait on the chosen one | group of buttons | no | pass | owed |
| Search engine | titled by Moteur de recherche; radio buttons | radio group | no | pass | owed |
| Cancel, Create | Annuler, Créer (disabled until named and an engine is chosen) | button | Escape, Return | pass | owed |

Captures: `settings-defaults-fr.png`, `settings-shortcuts-fr.png`, `settings-link-rules-fr.png` (taken before the
heading and label fixes, which change no pixel).
