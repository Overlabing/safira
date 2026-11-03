# Build the browser shell first and test extensions afterwards

Antonin's original rule was that without good Chrome extension support the project stops. The recommendation was a one-to-two-day spike loading Verrou and a wallet before building the shell; he chose to build the shell first. The go/no-go on extensions is therefore deferred, not lifted. The consequence is accepted: if extensions fail, the shell cannot be a daily browser, since passwords come through an extension. See `docs/scope-v1.md` section 9.
