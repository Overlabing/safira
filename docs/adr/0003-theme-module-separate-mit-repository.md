# The theme module lives in its own MIT repository

The color and theming code is shared with Oisillon, a closed-source app distributed through the App Store. Safira is GPL-3.0, so the module cannot live in Safira's repository without forcing Oisillon to go GPL. It is a separate MIT repository under the Overlabing organisation, and both apps depend on it. The module first spoke only of Themes, never of Spaces. Since both apps now share one design system and one Space model (ADR 0005), the module may use the word Space.
