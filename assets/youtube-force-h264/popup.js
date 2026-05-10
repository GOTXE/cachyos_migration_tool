(() => {
    "use strict";

    const enabledInput = document.getElementById("enabled");
    const statusText = document.getElementById("status");

    function setStatus(enabled) {
        statusText.textContent = enabled
            ? "El parche está activo."
            : "El parche está desactivado.";
    }

    chrome.storage.local.get({ enabled: true }, (items) => {
        const enabled = items.enabled !== false;

        enabledInput.checked = enabled;
        setStatus(enabled);
    });

    enabledInput.addEventListener("change", () => {
        const enabled = enabledInput.checked;

        chrome.storage.local.set({ enabled }, () => {
            setStatus(enabled);
        });
    });
})();
