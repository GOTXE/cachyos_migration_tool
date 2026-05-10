(() => {
    "use strict";

    if (window.__ytForceH264Installed__) {
        return;
    }

    Object.defineProperty(window, "__ytForceH264Installed__", {
        value: true,
        configurable: false,
        enumerable: false,
        writable: false
    });

    const BLOCKED_CODEC_MARKERS = ["vp8", "vp9", "vp09", "av1", "av01"];

    function normalizeType(value) {
        return typeof value === "string" ? value.toLowerCase() : "";
    }

    function isBlockedVideoType(type) {
        const normalized = normalizeType(type);

        if (!normalized || !normalized.includes("video/")) {
            return false;
        }

        return BLOCKED_CODEC_MARKERS.some((marker) => normalized.includes(marker));
    }

    function patchMediaSource(ctor) {
        if (!ctor || typeof ctor.isTypeSupported !== "function") {
            return;
        }

        const original = ctor.isTypeSupported.bind(ctor);

        try {
            Object.defineProperty(ctor, "isTypeSupported", {
                configurable: true,
                value(type) {
                    if (isBlockedVideoType(type)) {
                        return false;
                    }

                    return original(type);
                }
            });
        } catch {
            try {
                ctor.isTypeSupported = function isTypeSupportedPatched(type) {
                    if (isBlockedVideoType(type)) {
                        return false;
                    }

                    return original(type);
                };
            } catch {
                return;
            }
        }
    }

    function patchCanPlayType() {
        if (!window.HTMLMediaElement) {
            return;
        }

        const proto = window.HTMLMediaElement.prototype;

        if (!proto || typeof proto.canPlayType !== "function") {
            return;
        }

        const original = proto.canPlayType;

        try {
            Object.defineProperty(proto, "canPlayType", {
                configurable: true,
                value(type) {
                    if (isBlockedVideoType(type)) {
                        return "";
                    }

                    return original.call(this, type);
                }
            });
        } catch {
            try {
                proto.canPlayType = function canPlayTypePatched(type) {
                    if (isBlockedVideoType(type)) {
                        return "";
                    }

                    return original.call(this, type);
                };
            } catch {
                return;
            }
        }
    }

    function patchMediaCapabilities() {
        const mediaCapabilities = navigator.mediaCapabilities;

        if (!mediaCapabilities || typeof mediaCapabilities.decodingInfo !== "function") {
            return;
        }

        const original = mediaCapabilities.decodingInfo.bind(mediaCapabilities);

        try {
            Object.defineProperty(mediaCapabilities, "decodingInfo", {
                configurable: true,
                value: async function decodingInfoPatched(config) {
                    const videoType =
                        config &&
                        config.video &&
                        typeof config.video.contentType === "string"
                            ? config.video.contentType
                            : "";

                    if (isBlockedVideoType(videoType)) {
                        return {
                            supported: false,
                            smooth: false,
                            powerEfficient: false,
                            keySystemAccess: null
                        };
                    }

                    return original(config);
                }
            });
        } catch {
            try {
                mediaCapabilities.decodingInfo = async function decodingInfoPatched(config) {
                    const videoType =
                        config &&
                        config.video &&
                        typeof config.video.contentType === "string"
                            ? config.video.contentType
                            : "";

                    if (isBlockedVideoType(videoType)) {
                        return {
                            supported: false,
                            smooth: false,
                            powerEfficient: false,
                            keySystemAccess: null
                        };
                    }

                    return original(config);
                };
            } catch {
                return;
            }
        }
    }

    patchMediaSource(window.MediaSource);
    patchMediaSource(window.ManagedMediaSource);
    patchCanPlayType();
    patchMediaCapabilities();
})();
