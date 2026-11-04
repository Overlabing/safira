# Shared code lives in public kits, one owner each

Safira and Oisillon share as much code as possible and copy none of it. Shared code lives in public MIT repositories under the Overlabing organisation, each with one owner that alone pushes and tags; the other app opens issues or pull requests and pins an exact version. Every kit builds for macOS 26 and iOS 26, uses Swift 6 strict concurrency, and depends on other kits only in one direction.

ThemeKit is the design kit: themes, palettes, one set of design tokens taken from Oisillon, named motions, colour roles from its legibility solver, and the small views of a themed window. Safira follows Oisillon's design rather than having its own. Larger shared windows and sheets (settings, onboarding, Space editor, command panel) live in AppShellKit, which depends on ThemeKit and the non-UI kits so that ThemeKit keeps no dependencies. The non-UI kits (AppSupportKit, CommandKit, DiagnosticsKit) and the AppTooling scripts are extracted from Oisillon first, with Oisillon switching to them in the same change, and Safira adopts them after its v1 acceptance.

Nothing private enters a kit: mail, credentials, agent access, team identifiers and machine details stay in the apps. Kits use English string keys with their own English and French catalogues.
