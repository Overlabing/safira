# Safira

A native macOS web browser with an Arc/Zen-style interface, built around strictly separated profiles (for example Work and Personal), each holding several Spaces of tabs.

## Language

### Structure

**Profile**:
A security boundary with its own logins, history, downloads and search settings. Nothing is shared between profiles except appearance.
_Avoid_: Account, container, identity

**Space**:
A named, themed group of tabs inside one Profile. Spaces of the same Profile share that Profile's logins.
_Avoid_: Workspace, container, group

**Tab**:
One open web page, belonging to one Space. Closing a Tab that is not pinned discards it, but the Tabs closed during the current session can be reopened; nothing about them is kept after a relaunch.
_Avoid_: Page, session

**Pinned tab**:
A Tab fixed to its Space that persists across sessions, shown in a pinned area above the Space's other Tabs. Unpinning it turns it back into a plain Tab. There is no pinned area shared across a Profile's Spaces.
_Avoid_: Favorite, essential, bookmark

**Folder**:
A container inside a Space that holds only Pinned tabs and other Folders.
_Avoid_: Group, bookmark folder, collection

**Active profile**:
The Profile currently shown in the Main window. The Command bar and search never reach beyond it.
_Avoid_: Current account, selected profile

### Windows

**Main window**:
The single window that shows every Profile and Space, switching between them from the sidebar.
_Avoid_: Browser window, normal window

**Private window**:
A separate window attached to one Profile, with no Spaces, no saved history, and everything erased when it closes.
_Avoid_: Incognito, private tab, private session

**Compact mode**:
A state of the Main window where the sidebar hides itself and reappears on demand.
_Avoid_: Fullscreen sidebar, collapsed sidebar

### Navigation

**Command bar**:
The keyboard-first field for typing an address, a search, or the name of a tab to jump to.
_Avoid_: Omnibox, address bar, command palette

**Shortcut preset**:
A named set of keyboard shortcuts (Zen, Arc or Safari) chosen at onboarding and editable afterwards.
_Avoid_: Keymap, keybindings profile

### External links

**Opener**:
The app from which an external link was clicked.
_Avoid_: Source app, sender

**Link picker**:
The panel that asks which Profile should receive an external link when no Link rule decides it. It is the default browser's front door. An option makes it ask for the Space as well; by default it does not. Nothing is preselected: the user always chooses explicitly. When a link is already open in one or both Profiles, the Link picker marks them but never chooses for the user. It can also create a Link rule from the user's choice.
_Avoid_: Browser chooser, selector

**Link rule**:
A user-defined match on host, path or Opener that sends a link to a given Profile, and optionally to a given Space, without asking. A Link rule can also force a link to open in a new Tab instead of focusing a Matching tab.
_Avoid_: Filter, route

**Normalized address**:
The form of a link's address used to compare it with open Tabs: scheme and host without letter case, trailing slash, fragment and known tracking parameters ignored, other parameters kept.
_Avoid_: Canonical URL, clean URL

**Matching tab**:
A Tab in the Target profile whose current address has the same Normalized address as an incoming link, including a Tab not yet loaded since launch (its last saved address). Safira focuses it instead of opening a new Tab, and a discreet banner offers to open the link in a new Tab anyway. Private windows are never searched.
_Avoid_: Duplicate, existing tab

**Target**:
The Profile (and optionally the Space) that receives an external link. With no Space named by a Link rule or chosen in the Link picker, the link opens as a new Tab in that Profile's last active Space.
_Avoid_: Destination

### Appearance

**Theme**:
A gradient and tint attached to a Space, chosen from a Palette. The shared color module speaks only of Themes and never of Spaces.
_Avoid_: Skin, color scheme

**Palette**:
The named set of preset Themes a user picks from.
_Avoid_: Color picker, swatches

### Privacy

**Browsing data**:
The history and website data (logins, cookies and site storage) kept by one Profile. It stays until the user clears it, by time range, and it is never cleared automatically.
_Avoid_: Cache, cookies and history

**Debug mode**:
An opt-in state in which Safira keeps local, masked logs; they leave the machine only through a manual export. Nothing is ever sent automatically.
_Avoid_: Telemetry, analytics, crash reporting
