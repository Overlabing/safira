# Safira uses only public WebKit API and does not fork or embed WebKit

Safira renders with the system `WKWebView` and calls no private API (SPI). It does not ship its own build of WebKit. A fork would unlock more of the Chrome extension API surface, but it would weaken the sandbox, drop restricted entitlements, and make Safira responsible for WebKit security fixes every four to eight weeks, which contradicts a privacy-first browser. SPI would break on macOS updates. The cost is accepted: some extension APIs and an in-app Web Inspector are out of reach (see `docs/conformance-bench-plan.md`).
