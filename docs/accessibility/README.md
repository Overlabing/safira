# Accessibility checklists

One checklist per screen, from the accessibility tree of a background copy of the app (issue #25, part 1). Each row is a
control: its label as the tree reads it, its role, whether it takes the keyboard focus, and the result.

How the trees were read: a Debug build re-signed under a throwaway bundle identifier, launched in the background with
`-AppleLanguages "(fr)"` (labels below are the French ones; the English keys are in the String Catalogs), read with the
public AX API (`AXUIElementCopyAttributeValue`: role, description, value, help, selected, `AXFocused` settable, actions,
title element). No window was made key, so:

- **Focusable** is what the tree reports with the Mac's Keyboard navigation setting off: text fields, lists and the
  Tab rows take the focus; plain buttons do not until Keyboard navigation (full keyboard access) is turned on. A
  button that has a menu command and a shortcut is reachable by the keyboard in principle either way.
- Screens that only open from a key window (the Link picker, the download manager, the Clear history and Site
  permissions sheets, the sign-in panel, camera and location prompts, Command bar suggestions, Pinned tabs and Folders)
  were checked from their code; their tree is **owed** with the by-hand pass.

**By hand: owed** (part 2): a real VoiceOver listen and a keyboard traversal need a focused window. Every row keeps that
column until it is done.

| Screen | Checklist |
|---|---|
| Sidebar: rail, Tabs, Pinned, Folders | [sidebar.md](sidebar.md) |
| Command bar | [command-bar.md](command-bar.md) |
| Link picker | [link-picker.md](link-picker.md) |
| Onboarding | [onboarding.md](onboarding.md) |
| Private window | [private-window.md](private-window.md) |
| Download manager | [downloads.md](downloads.md) |
| Settings: Defaults, Shortcuts, Link rules, Profile and Space editors | [settings.md](settings.md) |
| Sign-in panel and permission sheets | [auth-and-permission-sheets.md](auth-and-permission-sheets.md) |

Results: **pass**, **fixed** (in the pull request of #25), **filed** (a separate issue), **code** (read from the code,
tree owed).
