# Link picker

The picker is a panel that takes the keyboard as it drops out of the notch. Showing it would bring a window forward
and take keys from the app in use, so its tree was not read in the background (standing order 39). Rows below are
from `LinkPickerView` and `LinkPickerPresenter`.

| Control | Label | Role | Focusable | Result | By hand |
|---|---|---|---|---|---|
| Panel | Sélecteur de liens; announcement on appearance: question, Opener, keys, “Échap l’ignore.” | panel | takes the keyboard | code | owed |
| Summary | “Lien vers %@, depuis %@” | text | n/a | code | owed |
| Profile or Space tile | name; value “Touche 1”, “Le lien est déjà ouvert ici”; hint; selected trait on the highlighted tile | button | keys 1–9, arrows, Return | code | owed |
| Always checkbox | “Toujours envoyer les liens de %@ ici”; key A; announcement on change | checkbox | key A | code | owed |
| Close | Ignorer le lien; help “Ignorer le lien (Échap)” | button | Escape | code | owed |

No preselection: the highlighted tile carries the selected trait only after an arrow key (D9). Capture owed with the
by-hand pass.
