# Native messaging in Safira: registering a host

Safira runs Chrome-style web extensions with WebKit, and supports `runtime.connectNative` and `runtime.sendNativeMessage` the way Chrome does on macOS. If your app already ships a native messaging host for Chrome or Brave, supporting Safira is one more manifest file. Safira has no code for any particular app (ADR 0007).

## Register the host

Write the same manifest you write for Chrome into Safira's folder, in the user's home:

```
~/Library/Application Support/Safira/NativeMessagingHosts/<name>.json
```

```json
{
  "name": "com.example.myapp",
  "description": "My App",
  "path": "/Applications/My App.app/Contents/MacOS/my-native-host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://abcdefghijklmnopabcdefghijklmnop/"]
}
```

- `name` is the name your extension passes to `connectNative`, and the file's name without `.json`. Like Chrome, Safira accepts lowercase letters, digits, `_` and `.`, not at the start or the end, and no two dots in a row.
- `path` is absolute.
- `type` is `stdio`.
- `allowed_origins` lists each extension that may start the host, as `chrome-extension://<id>/`, with no wildcard. Safira derives an extension's id from the `key` in its `manifest.json`, the way Chrome does. An extension with a `key` gets the same id in Chrome, Brave and Safira, so the same `allowed_origins` works everywhere.

Create the folder if it is missing. A sandboxed app that writes it needs its own home-relative read-write exception for `/Library/Application Support/Safira/NativeMessagingHosts/`.

## What Safira does

- **On `connectNative(name)`:** Safira reads `<name>.json`. It refuses the port with Chrome's errors: "Specified native messaging host not found." for a missing or invalid manifest or a program that does not start, and "Access to the specified native messaging host is forbidden." when the extension's origin is not listed.
- **Starting the host:** Safira starts `path` with one argument, the caller's origin (`chrome-extension://<id>/`), in the program's own folder, with stderr discarded.
- **Messages:** each message, in each direction, is a 4-byte length in native (little-endian) byte order, then UTF-8 JSON. A host's message may be at most 1 MB; a longer one ends the connection with "Error when communicating with the native messaging host."
- **Lifetime:** one process per port. When the port closes (the extension disconnects it, or WebKit drops it with the service worker), Safira closes the host's stdin and ends the process a second later if it has not exited. When the host exits, the port is disconnected ("Native host has exited.").
- **One-time messages:** `sendNativeMessage` starts a process, sends the message, takes the host's first message as the reply, and ends the process.

## The sandbox

Safira is sandboxed, and the host runs inside Safira's sandbox:

- **Location:** it can read `/Applications/` and `~/Applications/`, so put the host program inside your app's bundle there.
- **Network:** it may open network connections as a client (for example to your app on `127.0.0.1`).
- **Files:** it cannot read the user's files.
- **XPC:** it cannot look up your app's XPC or Mach services. Use a loopback socket, or start your app with `open` or `NSWorkspace` from the host.

**A host that is sandboxed on its own does not run.** If your host's code signature has `com.apple.security.app-sandbox` without `com.apple.security.inherit`, macOS kills it at launch when its parent is sandboxed (SIGTRAP in `_libsecinit_appsandbox`). Safira reads the host's entitlements before starting it and refuses the port with: "Native messaging host <name> is sandboxed without com.apple.security.inherit, so macOS would stop it at launch." Ship a host without the App Sandbox entitlement, or one with both `app-sandbox` and `inherit`.

## Check your host

1. With your extension loaded in Safira (Debug mode, Load Unpacked Extension…), open its service worker in Safari's Develop menu.
2. Run `chrome.runtime.connectNative("<name>")` there.
3. Send a message and watch `onMessage` and `onDisconnect`.

Caveat: WebKit does not yet hand Safira's disconnect error to `onDisconnect`, so check your manifest first when a port closes at once.
