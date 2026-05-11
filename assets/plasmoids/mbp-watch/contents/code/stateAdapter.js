
function toNumber(value, fallback) {
    if (value === null || value === undefined || value === "") {
        return fallback;
    }

    var parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
}

function toStringValue(value, fallback) {
    if (value === null || value === undefined || value === "") {
        return fallback;
    }

    return String(value);
}

function normalizeSeverity(rawSeverity) {
    var severity = rawSeverity || {};

    return {
        className: toStringValue(severity.class, "ok"),
        title: toStringValue(severity.title, "Stable"),
        text: toStringValue(severity.text, "Waiting for diagnostics data."),
        reason: toStringValue(severity.reason, ""),
    };
}

function normalizeCounters(rawCounters) {
    var counters = rawCounters || {};
    var keys = ["wifi", "connectivity", "gpu", "bluetooth", "thermal", "pm", "audio", "throttle", "total"];
    var normalized = {};

    for (var i = 0; i < keys.length; i += 1) {
        normalized[keys[i]] = toNumber(counters[keys[i]], 0);
    }

    return normalized;
}

function selectPrimaryTemperature(temperatures) {
    var list = Array.isArray(temperatures) ? temperatures : [];
    var fallback = {
        label: "CPU Package",
        currentC: null,
        highC: null,
        critC: null,
        ratio: 0,
    };

    if (!list.length) {
        return fallback;
    }

    var selected = list[0];
    for (var i = 0; i < list.length; i += 1) {
        if (toStringValue(list[i].label, "") === "CPU Package") {
            selected = list[i];
            break;
        }
    }

    var currentC = toNumber(selected.current_c, null);
    var highC = toNumber(selected.high_c, null);
    var critC = toNumber(selected.crit_c, null);
    var baseline = critC !== null ? critC : highC;
    var ratio = baseline && currentC !== null ? Math.max(0, Math.min(1, currentC / baseline)) : 0;

    return {
        label: toStringValue(selected.label, "CPU Package"),
        currentC: currentC,
        highC: highC,
        critC: critC,
        ratio: ratio,
    };
}

function parseFanRpm(fanText) {
    var text = toStringValue(fanText, "");
    var match = text.match(/([0-9]+)/);

    return {
        text: text,
        rpm: match ? Number(match[1]) : null,
    };
}

function summarizeCpu(cpuPerf) {
    var cpu = cpuPerf || {};
    var freqRatio = toNumber(cpu.freq_ratio, null);
    var headroom = toNumber(cpu.freq_headroom, null);
    var throttleDelta = toNumber(cpu.throttle_count_delta, 0);
    var thermalAlarm = toStringValue(cpu.thermal_alarm, "none");
    var prochot = cpu.prochot === true;
    var state = "normal";

    if (throttleDelta > 0 || prochot || (thermalAlarm && thermalAlarm !== "none")) {
        state = "throttling";
    } else if (toStringValue(cpu.freq_state, "unknown") === "low" || (freqRatio !== null && freqRatio < 70)) {
        state = "warning";
    }

    return {
        state: state,
        currentFreqs: toStringValue(cpu.current_freqs, ""),
        usage: toStringValue(cpu.cpu_usage, ""),
        maxFreqMhz: toNumber(cpu.max_freq_mhz, null),
        freqRatio: freqRatio,
        headroom: headroom,
        freqState: toStringValue(cpu.freq_state, "unknown"),
        energyMode: toStringValue(cpu.energy_mode, "unknown"),
        governor: toStringValue(cpu.governor, "unknown"),
        throttleStatus: toStringValue(cpu.throttle_status, ""),
        thermalAlarm: thermalAlarm,
        prochot: prochot,
        throttleCountDelta: throttleDelta,
        baseFreqMhz: toNumber(cpu.base_freq_mhz, null),
    };
}

function summarizeBattery(rawBattery) {
    var battery = rawBattery || {};
    var percentage = toNumber(battery.percentage, null);
    var state = toStringValue(battery.state, "unknown");
    var tone = "ok";

    if (percentage !== null && percentage < 20) {
        tone = "critical";
    } else if (percentage !== null && percentage < 40) {
        tone = "warn";
    }

    return {
        percentage: percentage,
        state: state,
        timeToEmpty: toStringValue(battery.time_to_empty, ""),
        capacityPct: toNumber(battery.capacity_pct, null),
        energyWh: toNumber(battery.energy_wh, null),
        tone: tone,
    };
}

function summarizeWifi(link, analysis) {
    var wifiLink = link || {};
    var wifiAnalysis = analysis || {};
    var connected = wifiLink.connected === true;
    var signalDbm = toNumber(wifiLink.signal_dbm, null);
    var latencyMs = toNumber(wifiAnalysis.latency_ms, null);
    var packetLossPct = toNumber(wifiAnalysis.packet_loss_pct, null);
    var signalWarnDbm = toNumber(wifiAnalysis.signal_warn_dbm, -72);
    var tone = "ok";

    if (!connected) {
        tone = "critical";
    } else if ((signalDbm !== null && signalDbm < signalWarnDbm) ||
            (packetLossPct !== null && packetLossPct > 0) ||
            (latencyMs !== null && latencyMs > 100)) {
        tone = "warn";
    }

    return {
        connected: connected,
        ssid: toStringValue(wifiLink.ssid, ""),
        signalDbm: signalDbm,
        freqMhz: toNumber(wifiLink.freq_mhz, null),
        txMbps: toNumber(wifiLink.tx_mbps, null),
        rxMbps: toNumber(wifiLink.rx_mbps, null),
        txRetries: toNumber(wifiLink.tx_retries, null),
        powerSave: toStringValue(wifiLink.power_save, "unknown"),
        channel: toNumber(wifiAnalysis.channel, null),
        latencyMs: latencyMs,
        packetLossPct: packetLossPct,
        interferenceCount: toNumber(wifiAnalysis.interference_count, 0),
        pingTarget: toStringValue(wifiAnalysis.ping_target, "8.8.8.8"),
        scanSource: toStringValue(wifiAnalysis.scan_source, "none"),
        nearbyNetworks: Array.isArray(wifiAnalysis.nearby_networks) ? wifiAnalysis.nearby_networks : [],
        tone: tone,
    };
}

function normalizeSnapshot(rawSnapshot) {
    var snapshot = rawSnapshot || {};
    var loadAndSystem = snapshot.load_and_system || {};

    return {
        captured: toStringValue(snapshot.captured, ""),
        temperatures: Array.isArray(snapshot.temperatures) ? snapshot.temperatures : [],
        primaryTemperature: selectPrimaryTemperature(snapshot.temperatures),
        fan: parseFanRpm(snapshot.fan_rpm),
        cpu: summarizeCpu(snapshot.cpu_perf),
        loadAndSystem: {
            loadAverage: toStringValue(loadAndSystem.load_average, ""),
            contextSwitches: toNumber(loadAndSystem.context_switches, 0),
            topCpuProcesses: toStringValue(loadAndSystem.top_cpu_processes, ""),
            topMemoryProcesses: toStringValue(loadAndSystem.top_memory_processes, ""),
        },
        battery: summarizeBattery(snapshot.battery),
        wifi: summarizeWifi(snapshot.wifi_link, snapshot.wifi_analysis),
    };
}

function buildEventId(event) {
    return [
        toStringValue(event.ts, ""),
        toStringValue(event.category, "other"),
        toStringValue(event.message, ""),
    ].join("|");
}

function normalizeEvents(rawEvents) {
    var events = Array.isArray(rawEvents) ? rawEvents : [];
    var normalized = [];

    for (var i = 0; i < events.length; i += 1) {
        var event = events[i] || {};
        normalized.push({
            eventId: buildEventId(event),
            ts: toStringValue(event.ts, ""),
            category: toStringValue(event.category, "other"),
            message: toStringValue(event.message, ""),
        });
    }

    return normalized;
}

function normalizeDriverHealth(rawDriverHealth) {
    var driverHealth = rawDriverHealth || {};
    var drivers = Array.isArray(driverHealth.drivers) ? driverHealth.drivers : [];
    var normalizedDrivers = [];

    for (var i = 0; i < drivers.length; i += 1) {
        normalizedDrivers.push({
            name: toStringValue(drivers[i].name, "driver"),
            status: toStringValue(drivers[i].status, "OK"),
            detail: toStringValue(drivers[i].detail, ""),
            fix: toStringValue(drivers[i].fix, ""),
        });
    }

    return {
        captured: toStringValue(driverHealth.captured, ""),
        drivers: normalizedDrivers,
    };
}

function normalizeDailyHistory(rawHistory) {
    var history = Array.isArray(rawHistory) ? rawHistory : [];
    var normalized = [];
    var start = Math.max(0, history.length - 7);

    for (var i = start; i < history.length; i += 1) {
        normalized.push({
            date: toStringValue(history[i].date, ""),
            wifi: toNumber(history[i].wifi, 0),
            net: toNumber(history[i].net, 0),
            gpu: toNumber(history[i].gpu, 0),
            bt: toNumber(history[i].bt, 0),
            thermal: toNumber(history[i].thermal, 0),
            pm: toNumber(history[i].pm, 0),
            audio: toNumber(history[i].audio, 0),
            throttle: toNumber(history[i].throttle, 0),
            total: toNumber(history[i].total, 0),
        });
    }

    return normalized;
}

function adapt(rawData) {
    var data = rawData || {};

    return {
        generated: toStringValue(data.generated, ""),
        stateDir: toStringValue(data.state_dir, "/var/lib/mbp-watch"),
        severity: normalizeSeverity(data.severity),
        counters: normalizeCounters(data.counters),
        snapshot: normalizeSnapshot(data.snapshot),
        recentEvents: normalizeEvents(data.recent_events),
        driverHealth: normalizeDriverHealth(data.driver_health),
        dailyHistory: normalizeDailyHistory(data.daily_history),
    };
}
