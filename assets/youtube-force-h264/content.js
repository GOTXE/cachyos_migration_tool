(() => {
    "use strict";

    const root = document.head || document.documentElement;

    if (!root || !chrome?.runtime?.getURL || !chrome?.storage?.local?.get) {
        return;
    }

    chrome.storage.local.get({ enabled: true }, (items) => {
        if (chrome.runtime.lastError || items.enabled === false) {
            return;
        }

        const script = document.createElement("script");

        script.src = chrome.runtime.getURL("inject.js");
        script.onload = () => script.remove();

        root.appendChild(script);
    });
})();
