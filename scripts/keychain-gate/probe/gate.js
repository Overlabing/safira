// Asks the service worker, so the key is stored and read where Verrou stores it: in the worker.
browser.runtime.sendMessage({ op: location.hash.slice(1) }).then(
  (answer) => { document.documentElement.dataset.gate = answer; },
  (error) => { document.documentElement.dataset.gate = `error: ${error}`; });
