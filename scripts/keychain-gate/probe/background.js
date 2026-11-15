// The same storage Verrou uses for its pairing key (background.js, "Saved pairing"): a CryptoKey in IndexedDB.
function database() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open("gate", 1);
    request.onupgradeneeded = () => request.result.createObjectStore("state");
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function stored(mode, action) {
  const db = await database();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction("state", mode);
    const request = action(transaction.objectStore("state"));
    transaction.oncomplete = () => resolve(request?.result);
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error);
  });
}

async function write() {
  const key = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
  await stored("readwrite", (store) => store.put({ key }, "client"));
  return "written";
}

async function read() {
  const saved = await stored("readonly", (store) => store.get("client"));
  if (!(saved?.key instanceof CryptoKey)) return "the key was not read back";
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const sealed = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, saved.key, new TextEncoder().encode("gate"));
  const opened = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, saved.key, sealed);
  return new TextDecoder().decode(opened) === "gate" ? "read back" : "the key read back does not decrypt";
}

browser.runtime.onMessage.addListener((message, _sender, reply) => {
  (message.op === "write" ? write() : read()).then(reply, (error) => reply(`error: ${error}`));
  return true;
});
