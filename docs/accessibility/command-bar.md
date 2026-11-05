# Command bar

Tree read with the Command bar open over an empty page, right after onboarding.

| Control | Label | Role | Focusable | Result | By hand |
|---|---|---|---|---|---|
| Panel | none (it only contains the field) | group | n/a | fixed: the panel and the field both said “Barre de commande” | owed |
| Field | Barre de commande; placeholder Rechercher ou saisir une adresse | text field | yes | pass | owed |
| Placeholder in a new Tab | Rechercher ou saisir une adresse à ouvrir dans un nouvel onglet | text | n/a | code | owed |
| Suggestion count | “3 suggestions” announced (plural variations, was an inflection rule) | announcement | n/a | code | owed |
| Suggestion row | title; value: Onglet ouvert or Historique, then the address; selected trait on the highlighted row | button | n/a (arrows move) | code | owed |
| Tab, ⇧Tab | move from the field to the Tab list and back | keys | n/a | code | owed |

Submitting the field in the background works with the Peekaboo sequence of standing order 29; the HTTPS-first warning it
led to is WebKit’s own page, already in French (`https-warning-fr.png`). Capture: `commandbar-fr.png`. The French
placeholder fits the bar.
