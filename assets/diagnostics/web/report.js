'use strict';

const REFRESH_MS = 5000;
const KEY_DETAILS = 'mbpw-details';
const KEY_AUDIO = 'mbpw-audio';
const KEY_FILTER = 'mbpw-filter';

let lastData = null;
let lastTotal = null;
let audioCtx = null;
const WIFI_MODAL_ID = 'wifi-modal';

function esc(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function formatValue(value, fallback = '—') {
    if (value === null || value === undefined || value === '') {
        return fallback;
    }
    return esc(value);
}

function formatDate(isoString) {
    if (!isoString) return '—';
    try {
        const date = new Date(isoString);
        const now = new Date();
        const diffMs = now - date;
        const diffMins = Math.floor(diffMs / 60000);
        const diffHours = Math.floor(diffMs / 3600000);
        const diffDays = Math.floor(diffMs / 86400000);

        if (diffMins < 1) return 'just now';
        if (diffMins < 60) return `${diffMins}m ago`;
        if (diffHours < 24) return `${diffHours}h ago`;
        if (diffDays === 1) return 'yesterday';
        if (diffDays < 7) return `${diffDays}d ago`;

        return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    } catch (e) {
        return isoString;
    }
}

function parseNumber(value) {
    if (value === null || value === undefined || value === '') {
        return null;
    }
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
}

function wifiChannelFromFreq(freq) {
    const n = parseNumber(freq);
    if (n === null) return null;
    if (n >= 2412 && n <= 2484) return Math.round((n - 2407) / 5);
    if (n >= 5000 && n <= 6000) return Math.round((n - 5000) / 5);
    return null;
}

function wifiSignalQuality(signal) {
    const n = parseNumber(signal);
    if (n === null) return { label: 'Unknown', tone: 'muted' };
    if (n >= -55) return { label: 'Excellent', tone: 'good' };
    if (n >= -67) return { label: 'Good', tone: 'good' };
    if (n >= -75) return { label: 'Fair', tone: 'warn' };
    return { label: 'Weak', tone: 'bad' };
}

function wifiStatusModel(link = {}) {
    const signal = parseNumber(link.signal_dbm);
    const connected = Boolean(link.connected);
    const quality = wifiSignalQuality(signal);
    let status = 'ok';
    let title = connected ? `Connected to ${link.ssid || 'Wi-Fi'}` : 'Disconnected';
    let summary = connected ? 'Link looks stable.' : 'No active Wi-Fi link detected.';

    if (!connected) {
        status = 'alert';
    } else if (signal !== null && signal < -72) {
        status = 'warn';
        summary = 'Signal is weak and may affect throughput or roaming.';
    }

    return {
        status,
        title,
        summary,
        quality,
        connected,
        signal,
        channel: wifiChannelFromFreq(link.freq_mhz),
    };
}

function wifiProblems(link = {}, analysis = {}, wifiEvents = []) {
    const problems = [];
    const signal = parseNumber(link.signal_dbm);
    const retries = parseNumber(link.tx_retries);
    const latency = parseNumber(analysis.latency_ms);
    const packetLoss = parseNumber(analysis.packet_loss_pct);
    const interferenceCount = parseNumber(analysis.interference_count) || 0;
    const signalWarn = parseNumber(analysis.signal_warn_dbm) ?? -72;

    if (!link.connected) {
        problems.push('No active Wi-Fi connection.');
    }
    if (signal !== null && signal < signalWarn) {
        problems.push(`Weak signal (${signal} dBm).`);
    }
    if (retries !== null && retries > 50) {
        problems.push(`High TX retries (${retries}).`);
    }
    if (latency !== null && latency > 100) {
        problems.push(`High latency (${latency} ms).`);
    }
    if (packetLoss !== null && packetLoss > 0) {
        problems.push(`Packet loss detected (${packetLoss}%).`);
    }
    if (interferenceCount > 0) {
        problems.push(`${interferenceCount} nearby network(s) detected on the same channel.`);
    }
    if (Array.isArray(wifiEvents) && wifiEvents.length > 0) {
        problems.push(`${wifiEvents.length} recent Wi-Fi related journal event(s).`);
    }

    return problems;
}

function badge(status, label = status) {
    const map = {
        OK: 'ok',
        WARN: 'warn',
        ERROR: 'error',
        info: 'muted',
    };
    const klass = map[status] || 'muted';
    return `<span class="badge badge-${klass}">${esc(label)}</span>`;
}

function cpuModeMeta(value, kind) {
    const raw = String(value || 'unknown').toLowerCase();
    const meta = {
        label: raw,
        color: '#7d8590',
        emoji: '',
    };

    if (kind === 'energy') {
        if (raw === 'performance') {
            meta.label = 'performance';
            meta.color = '#f85149';
            meta.emoji = ' 🌶️';
        } else if (raw === 'balanced') {
            meta.label = 'equilibrado';
            meta.color = '#d29922';
            meta.emoji = ' ⚖️';
        } else if (raw === 'power-saver' || raw === 'low-power' || raw === 'powersave' || raw === 'quiet') {
            meta.label = 'ahorro';
            meta.color = '#3fb950';
            meta.emoji = ' 🌿';
        } else {
            meta.emoji = ' ❔';
        }
    } else if (kind === 'governor') {
        if (raw === 'performance') {
            meta.label = 'performance';
            meta.color = '#f85149';
            meta.emoji = ' 🌶️';
        } else if (raw === 'schedutil') {
            meta.label = 'schedutil';
            meta.color = '#d29922';
            meta.emoji = ' ⚙️';
        } else if (raw === 'powersave') {
            meta.label = 'powersave';
            meta.color = '#3fb950';
            meta.emoji = ' 🪫';
        } else if (raw === 'conservative') {
            meta.label = 'conservative';
            meta.color = '#7d8590';
            meta.emoji = ' 🐢';
        } else if (raw === 'ondemand') {
            meta.label = 'ondemand';
            meta.color = '#d29922';
            meta.emoji = ' 📈';
        } else if (raw === 'userspace') {
            meta.label = 'userspace';
            meta.color = '#7dd3d9';
            meta.emoji = ' 🧑‍💻';
        } else {
            meta.emoji = ' ❔';
        }
    }

    return meta;
}

function tone(ctx, freq, startAt, dur) {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.type = 'sine';
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.18, ctx.currentTime + startAt);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + startAt + dur);
    osc.start(ctx.currentTime + startAt);
    osc.stop(ctx.currentTime + startAt + dur);
}

function playAlert(critical) {
    if (!audioCtx) {
        return;
    }
    if (critical) {
        tone(audioCtx, 932, 0.00, 0.14);
        tone(audioCtx, 784, 0.18, 0.14);
        tone(audioCtx, 622, 0.36, 0.26);
    } else {
        tone(audioCtx, 660, 0.00, 0.35);
    }
}

function updateAudioButton() {
    const button = document.getElementById('audio-btn');
    if (!button) {
        return;
    }
    const enabled = localStorage.getItem(KEY_AUDIO) === '1';
    button.textContent = enabled ? 'Audio on' : 'Audio off';
    button.dataset.active = enabled ? 'true' : 'false';
}

function saveDetailsState() {
    try {
        const state = {};
        document.querySelectorAll('details[data-persist]').forEach((el) => {
            state[el.id] = el.open;
        });
        localStorage.setItem(KEY_DETAILS, JSON.stringify(state));
    } catch (err) {
        // ignore storage failures
    }
}

function restoreDetailsState() {
    try {
        const state = JSON.parse(localStorage.getItem(KEY_DETAILS) || '{}');
        document.querySelectorAll('details[data-persist]').forEach((el) => {
            if (Object.prototype.hasOwnProperty.call(state, el.id)) {
                el.open = state[el.id];
            }
        });
    } catch (err) {
        // ignore storage failures
    }
}

function setFilter(filter) {
    localStorage.setItem(KEY_FILTER, filter);
    render(lastData);
}

function getFilter() {
    return localStorage.getItem(KEY_FILTER) || 'all';
}

function severityBanner(severity) {
    const klass = severity?.class || 'ok';
    const title = severity?.title || 'Stable';
    const text = severity?.text || 'No hardware errors detected.';
    const reason = severity?.reason || '';
    return `
        <section class="banner ${esc(klass)}">
            <h2>${esc(title)}</h2>
            <p>${esc(text)}</p>
            <p class="mini-note"><strong>Reason:</strong> ${esc(reason)}</p>
        </section>
    `;
}

function metricCards(counters = {}) {
    const rows = [
        ['wifi', 'WI-FI'],
        ['connectivity', 'CONNECTIVITY'],
        ['gpu', 'GPU / DRM'],
        ['bluetooth', 'BLUETOOTH'],
        ['thermal', 'THERMAL / ACPI'],
        ['pm', 'SUSPEND / PM'],
        ['audio', 'AUDIO / HW'],
        ['throttle', 'THROTTLE EVENTS'],
    ];
    return rows.map(([key, label]) => {
        const value = parseNumber(counters[key]) || 0;
        const alert = value > 0;
        const color = alert ? '#d29922' : '#7d8590';
        return `
            <article class="metric-card ${alert ? 'alert' : ''}">
                <div class="metric-label" style="color:${color}; text-transform:uppercase; letter-spacing:0.8px">${esc(label)}</div>
                <div class="metric-value" style="color:${color}; font-size:26px; font-weight:700">${alert ? value : '—'}</div>
                <div class="metric-sub" style="color:${color}; font-size:10px">${alert ? 'events' : 'clear'}</div>
            </article>
        `;
    }).join('');
}

function driverHealth(driverHealth = {}) {
    const drivers = Array.isArray(driverHealth.drivers) ? driverHealth.drivers : [];
    if (!drivers.length) {
        return `<div class="panel"><p class="subtle">No driver health data captured yet.</p></div>`;
    }

    return `
        <article class="panel">
            <div class="panel-header">
                <div class="panel-title">Driver Health</div>
            </div>
            <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(200px, 1fr)); gap:10px">
                ${drivers.map((entry) => {
                    const status = entry.status || 'OK';
                    let badgeBg = '#1a3327';
                    let badgeColor = '#3fb950';
                    if (status === 'WARN') {
                        badgeBg = '#2d2415';
                        badgeColor = '#d29922';
                    } else if (status === 'ERROR') {
                        badgeBg = '#3d1a1a';
                        badgeColor = '#f85149';
                    }

                    return `
                        <div style="background:#161b22; border:1px solid #30363d; border-radius:10px; padding:12px; display:flex; flex-direction:column; gap:8px">
                            <div style="display:flex; align-items:center; justify-content:space-between; gap:8px">
                                <div style="color:#e6edf3; font-weight:700; font-size:12px">${esc(entry.name || 'driver')}</div>
                                <span style="background:${badgeBg}; color:${badgeColor}; font-size:9px; font-weight:700; padding:3px 8px; border-radius:999px; text-transform:uppercase; letter-spacing:0.5px">${status}</span>
                            </div>
                            ${entry.detail ? `<div style="color:#7d8590; font-size:10px; line-height:1.4">${esc(entry.detail)}</div>` : ''}
                        </div>
                    `;
                }).join('')}
            </div>
        </article>
    `;
}

function cpuPerfPanel(cpu = {}, throttleCount = 0) {
    if (!cpu || (!cpu.current_freqs && !cpu.freq_state && !cpu.throttle_status && !cpu.governor && !cpu.energy_mode)) {
        return `<div class="panel"><p class="subtle">No CPU performance snapshot captured yet.</p></div>`;
    }

    const perfStatus = String(cpu.throttle_status || '');
    const freqState = String(cpu.freq_state || perfStatus.match(/freq_state=([a-z-]+)/)?.[1] || 'unknown');
    const ratio = String(cpu.freq_ratio || perfStatus.match(/(?:ratio|freq_ratio)=(\d+)%/)?.[1] || '—');
    const headroom = String(cpu.freq_headroom || perfStatus.match(/headroom=(\d+)%/)?.[1] || (ratio !== '—' ? String(Math.max(0, 100 - Number(ratio))) : '—'));
    const isLowFreq = freqState === 'low' || (ratio !== '—' && Number(ratio) < 70);
    const energyMode = cpuModeMeta(cpu.energy_mode, 'energy');
    const governor = cpuModeMeta(cpu.governor, 'governor');
    const maxFreq = parseNumber(cpu.max_freq_mhz) || 3000;
    const thermalAlarm = String(cpu.thermal_alarm || 'none').trim();
    const isThrottling = throttleCount > 0 || (thermalAlarm !== 'none' && thermalAlarm !== '') || cpu.prochot === true;

    // Parsear frecuencias por núcleo (ej: "core0=2300MHz core1=2300MHz...")
    const coreFreqs = [];
    const freqMatch = String(cpu.current_freqs || '').match(/core\d+=(\d+)MHz/g) || [];
    freqMatch.forEach((match) => {
        const freq = parseInt(match.split('=')[1]);
        coreFreqs.push(freq);
    });

    // Parsear uso de CPU por core (ej: "core0=45% core1=32% core2=28% core3=15%")
    const coreUsages = [];
    const usageMatch = String(cpu.cpu_usage || '').match(/core\d+=\d+%/g) || [];
    usageMatch.forEach((match) => {
        const usage = parseInt(match.split('=')[1]);
        coreUsages.push(usage);
    });

    return `
        <article class="panel">
            <div class="panel-header" style="display:flex; gap:16px; align-items:center; justify-content:space-between">
                <div style="display:flex; align-items:center; gap:10px; flex-wrap:wrap">
                    <div class="panel-title">CPU Performance</div>
                    ${isThrottling ? `<span class="throttle-warn">&#9650; THERMAL THROTTLE</span>` : ''}
                </div>
                <div style="display:flex; gap:12px; align-items:center; flex-wrap:wrap; justify-content:flex-end">
                    <div style="display:flex; gap:10px; align-items:center; font-size:10px; flex-wrap:wrap">
                        <span>Energy Mode: <span style="color:${energyMode.color}; font-weight:700">${esc(energyMode.label)}${energyMode.emoji}</span></span>
                        <span style="color:#57606a">|</span>
                        <span>Governor: <span style="color:${governor.color}; font-weight:700">${esc(governor.label)}${governor.emoji}</span></span>
                        <span style="color:${maxFreq >= 3000 ? '#f85149' : '#d29922'}; font-weight:600">${maxFreq} MHz</span>
                    </div>
                    ${isLowFreq ? badge('WARN', `Freq ${ratio}% / Headroom ${headroom}%`) : badge('OK', `Freq ${ratio}% / Headroom ${headroom}%`)}
                </div>
            </div>

            <div style="display:flex; gap:12px; flex-wrap:wrap">
                ${coreFreqs.length > 0 ? coreFreqs.map((freq, idx) => {
                    const usage = coreUsages[idx] || 0;
                    const usageColor = usage >= 80 ? '#f85149' : usage >= 50 ? '#d29922' : '#3fb950';
                    const freqColor = freq >= 3100 ? '#f85149' : freq >= 3000 ? '#d29922' : '#7d8590';

                    return `
                        <div style="background:#1c2128; border:1px solid #30363d; border-radius:8px; padding:12px; display:flex; flex-direction:column; gap:6px; min-height:85px; justify-content:space-between; flex:1; min-width:150px">
                            <div>
                                <div style="font-size:11px; color:#bfe7ea; font-weight:700">Core ${idx}</div>
                                <div style="font-size:22px; font-weight:700; color:${usageColor}">${usage}%</div>
                                <div style="font-size:9px; color:${freqColor}">${freq} MHz</div>
                            </div>
                            <div style="height:4px; background:#21262d; border-radius:2px; width:100%; margin-top:auto; overflow:hidden">
                                <div style="height:100%; background:${usageColor}; width:${usage}%; border-radius:2px"></div>
                            </div>
                        </div>
                    `;
                }).join('') : '<div style="color:var(--muted); font-size:12px">No frequency data</div>'}
            </div>
        </article>
    `;
}

function temperaturePanel(temperatures = [], fan = '') {
    const list = Array.isArray(temperatures) ? temperatures : [];
    if (!list.length && !fan) {
        return `<div class="panel"><p class="subtle">No temperature data captured yet.</p></div>`;
    }

    const items = [];

    // Parsear RPM del fan (ej: "fan1: 1527 RPM")
    let fanRpm = 0;
    if (fan) {
        const rpmMatch = fan.match(/(\d+)\s*RPM/i);
        if (rpmMatch) fanRpm = parseInt(rpmMatch[1]);
    }
    const fanColor = fanRpm > 5000 ? '#ff7a7a' : fanRpm > 3000 ? '#f5c451' : '#3a8862';

    if (fan) {
        const fanPct = Math.min(100, Math.round((fanRpm / 6000) * 100));
        items.push(`
            <div style="background:#0d1f14; border:1px solid #1a3327; border-radius:8px; padding:12px; display:flex; flex-direction:column; gap:6px; min-height:85px; justify-content:space-between; flex:1; min-width:150px">
                <div>
                    <div style="font-size:11px; color:#7dd3d9; font-weight:700">Fan Speed</div>
                    <div style="font-size:18px; font-weight:700; color:#e6edf3">${fanRpm} RPM</div>
                </div>
                <div style="height:4px; background:#21262d; border-radius:2px; width:100%; margin-top:auto; overflow:hidden">
                    <div style="height:100%; background:${fanColor}; width:${fanPct}%; border-radius:2px"></div>
                </div>
            </div>
        `);
    }

    for (const sensor of list) {
        const current = parseNumber(sensor.current_c) || 0;
        const high = parseNumber(sensor.high_c);
        const crit = parseNumber(sensor.crit_c);
        const safeHigh = (high && high <= 100) ? high : 80;
        const safeCrit = (crit && crit <= 100) ? crit : 95;
        const color = current >= safeCrit ? '#f85149' : current >= safeHigh ? '#d29922' : '#3fb950';
        const tempPct = Math.min(100, Math.round((current / 120) * 100));
        items.push(`
            <div style="background:#1c2128; border:1px solid #30363d; border-radius:8px; padding:12px; display:flex; flex-direction:column; gap:6px; min-height:85px; justify-content:space-between; flex:1; min-width:150px">
                <div>
                    <div style="font-size:11px; color:#bfe7ea; font-weight:700">${esc(sensor.label)}</div>
                    <div style="font-size:18px; font-weight:700; color:${color}">${current}°C</div>
                </div>
                <div style="height:4px; background:#21262d; border-radius:2px; width:100%; margin-top:auto; overflow:hidden">
                    <div style="height:100%; background:${color}; width:${tempPct}%; border-radius:2px"></div>
                </div>
            </div>
        `);
    }

    return `
        <article class="panel">
            <div class="panel-header" style="display:flex; gap:16px; align-items:center; justify-content:space-between">
                <div style="display:flex; gap:12px; align-items:center">
                    <div class="panel-title">Temperature / Fans</div>
                </div>
                <div style="display:flex; gap:4px; align-items:center; font-size:10px">
                    <span style="color:#7d8590">sensors + applesmc</span>
                    <span style="color:#7d8590">warning: 80°C  |  critical: 95°C</span>
                </div>
            </div>
            <div style="display:flex; gap:12px; flex-wrap:wrap">
                ${items.join('')}
            </div>
        </article>
    `;
}

function performanceCard(loadData = {}) {
    const loadAvg = loadData.load_average || '—';
    const ctxSwitches = parseNumber(loadData.context_switches) || 0;
    const topCpu = loadData.top_cpu_processes || '—';
    const topMem = loadData.top_memory_processes || '—';

    const parseLoad = (load) => {
        if (!load || load === '—') return null;
        const match = load.match(/average: ([\d.]+)/);
        return match ? parseFloat(match[1]) : null;
    };
    const load1 = parseLoad(loadAvg);
    let loadColor = '#3fb950';
    if (load1 !== null && load1 > 4) loadColor = '#f85149';
    else if (load1 !== null && load1 > 2) loadColor = '#d29922';

    return `
        <article class="panel">
            <div class="panel-header">
                <div class="panel-title">System Load & Performance</div>
                <span style="color:#7d8590; font-size:11px">CPU contention analysis</span>
            </div>
            <div style="display:flex; flex-direction:column; gap:12px">
                <div style="background:#1c2128; border-radius:6px; padding:10px; border-left:3px solid ${loadColor}">
                    <div style="font-size:11px; color:#7d8590; font-weight:700; margin-bottom:4px">System Load (1m avg)</div>
                    <div style="font-size:16px; font-weight:700; color:${loadColor}">${esc(loadAvg)}</div>
                </div>
                <div style="display:flex; gap:8px; font-size:11px">
                    <div style="flex:1; background:#1c2128; border-radius:4px; padding:8px">
                        <div style="color:#7d8590; margin-bottom:3px">Context Switches</div>
                        <div style="font-weight:700; color:#e6edf3">${ctxSwitches.toLocaleString()}</div>
                    </div>
                </div>
                <div style="display:flex; flex-direction:column; gap:6px">
                    <div style="font-size:11px; color:#7d8590; font-weight:700">Top CPU Processes</div>
                    <div style="font-size:11px; color:#b1bac4; font-family:monospace; background:#0d1117; padding:6px; border-radius:4px; overflow-x:auto">${esc(topCpu || 'N/A')}</div>
                    <div style="font-size:11px; color:#7d8590; font-weight:700">Top Memory Processes</div>
                    <div style="font-size:11px; color:#b1bac4; font-family:monospace; background:#0d1117; padding:6px; border-radius:4px; overflow-x:auto">${esc(topMem || 'N/A')}</div>
                </div>
            </div>
        </article>
    `;
}

function batteryCard(battery = {}) {
    const pct = parseNumber(battery.percentage);
    const state = battery.state || 'unknown';
    const cap = pct === null ? 0 : Math.max(0, Math.min(100, pct));
    let barColor = '#f85149';
    if (cap >= 80) barColor = '#3fb950';
    else if (cap >= 50) barColor = '#d29922';
    else if (cap >= 20) barColor = '#e8833c';

    let stateColor = '#7d8590';
    let stateBg = 'rgba(255, 255, 255, 0.04)';
    const stateLower = state.toLowerCase();
    if (stateLower.includes('fully') || stateLower.includes('full')) {
        stateColor = '#3fb950';
        stateBg = 'rgba(63, 185, 80, 0.15)';
    } else if (stateLower.includes('charging')) {
        stateColor = '#e8833c';
        stateBg = 'rgba(232, 131, 60, 0.15)';
    } else if (stateLower.includes('discharging')) {
        stateColor = '#d29922';
        stateBg = 'rgba(210, 153, 34, 0.15)';
    }

    return `
        <article class="panel">
            <div class="panel-header">
                <div class="panel-title">Battery</div>
                ${state ? `<span style="color:${stateColor}; background:${stateBg}; border:1px solid rgba(0,0,0,0.2); font-size:0.78rem; font-weight:700; padding:5px 10px; border-radius:999px; text-transform:capitalize">${esc(state)}</span>` : ''}
            </div>
            <div style="display:flex; flex-direction:column; gap:12px">
                <div style="height:8px; background:#21262d; border-radius:4px; overflow:hidden">
                    <div style="width:${cap}%; height:100%; background:${barColor}"></div>
                </div>
                <div style="display:flex; gap:16px; align-items:center; justify-content:space-between">
                    <div style="font-size:28px; font-weight:700; color:#e6edf3">${pct === null ? '—' : `${pct}%`}</div>
                    <div style="display:flex; gap:8px; align-items:center">
                        <span style="padding:4px 8px; background:#1c2128; border-radius:999px; font-size:11px; color:#7d8590">${esc(battery.time_to_empty || '—')}</span>
                        <span style="padding:4px 8px; background:#1c2128; border-radius:999px; font-size:11px; color:#7d8590">capacity: ${battery.capacity_pct ?? '—'}%</span>
                        <span style="padding:4px 8px; background:#1c2128; border-radius:999px; font-size:11px; color:#7d8590">energy: ${battery.energy_wh ?? '—'} Wh</span>
                    </div>
                </div>
            </div>
        </article>
    `;
}

function wifiLinkCard(link = {}) {
    const signal = parseNumber(link.signal_dbm);
    const signalColor = signal === null ? '#7d8590' : signal >= -65 ? '#3fb950' : signal >= -75 ? '#d29922' : '#f85149';
    const retries = parseNumber(link.tx_retries);
    const retryWarn = retries !== null && retries > 50;
    const connected = link.connected ? 'Connected' : 'Disconnected';

    return `
        <article class="panel">
            <div class="panel-header">
                <div class="panel-title">Wi-Fi Link</div>
                ${connected === 'Connected' ? badge('OK', connected) : badge('WARN', connected)}
            </div>
            <div style="display:flex; gap:12px; font-size:12px">
                <div style="display:flex; flex-direction:column; gap:6px; flex:1">
                    <div style="display:flex; justify-content:space-between; align-items:center">
                        <span style="color:#7d8590; font-size:11px">SSID</span>
                        <span style="color:#e6edf3; font-weight:600">${esc(link.ssid || '—')}</span>
                    </div>
                    <div style="display:flex; justify-content:space-between; align-items:center">
                        <span style="color:#7d8590; font-size:11px">Signal</span>
                        <span style="color:${signalColor}; font-weight:600">${signal === null ? '—' : `${signal} dBm`}</span>
                    </div>
                    <div style="display:flex; justify-content:space-between; align-items:center">
                        <span style="color:#7d8590; font-size:11px">Freq</span>
                        <span style="color:#e6edf3">${link.freq_mhz ?? '—'} MHz</span>
                    </div>
                </div>
                <div style="display:flex; flex-direction:column; gap:6px; flex:1">
                    <div style="display:flex; justify-content:space-between; align-items:center">
                        <span style="color:#7d8590; font-size:11px">TX rate</span>
                        <span style="color:#e6edf3">${link.tx_mbps ?? '—'} Mbps</span>
                    </div>
                    <div style="display:flex; justify-content:space-between; align-items:center">
                        <span style="color:#7d8590; font-size:11px">RX rate</span>
                        <span style="color:#e6edf3">${link.rx_mbps ?? '—'} Mbps</span>
                    </div>
                    <div style="display:flex; justify-content:space-between; align-items:center">
                        <span style="color:#7d8590; font-size:11px">TX retries</span>
                        <span style="color:${retryWarn ? '#f85149' : '#e6edf3'}">${retries ?? '—'}</span>
                    </div>
                </div>
            </div>
        </article>
    `;
}

function eventCategory(message) {
    const lower = String(message || '').toLowerCase();
    if (/(brcmf|wpa_supplicant|networkmanager|dhcp4|iwlwifi|mt76|ath|rtl|rtw)/.test(lower)) return 'wifi';
    if (/(gpu|drm|i915|command_buffer|sharedimagemanager)/.test(lower)) return 'gpu';
    if (/(pm:|suspend|resume|sleep|lid|s2idle)/.test(lower)) return 'power';
    if (/(thermal|acpi|applesmc|throttl)/.test(lower)) return 'thermal';
    if (/(snd_hda|audio|alsa|pipewire)/.test(lower)) return 'audio';
    if (/(bluetooth|btusb|hci)/.test(lower)) return 'bluetooth';
    return 'other';
}

function eventsPanel(events = []) {
    const list = Array.isArray(events) ? events : [];
    const filter = getFilter();
    const cats = ['all', 'wifi', 'gpu', 'power', 'thermal', 'audio', 'bluetooth', 'other'];
    const filtered = filter === 'all' ? list : list.filter((event) => event.category === filter);

    // Contar eventos por categoría
    const catCounts = {};
    cats.forEach(cat => {
        catCounts[cat] = cat === 'all' ? list.length : list.filter((e) => (e.category || eventCategory(e.message)) === cat).length;
    });

    return `
        <article class="panel">
            <div class="panel-header">
                <div class="panel-title">Recent Events</div>
            </div>
            <div style="display:flex; gap:4px; margin-bottom:12px; background:#1c2128; padding:3px 4px; border-radius:8px; border:1px solid #30363d">
                ${cats.map((cat) => {
                    const hasEvents = catCounts[cat] > 0;
                    const isActive = cat === filter;
                    return `
                        <button class="chip" data-filter="${esc(cat)}" data-active="${isActive ? 'true' : 'false'}" style="background:${isActive ? '#30363d' : 'transparent'}; color:${hasEvents && cat !== 'all' ? '#f85149' : '#e6edf3'}; border:none; padding:5px 12px; border-radius:6px; font-size:12px; cursor:pointer; font-weight:${isActive ? '600' : 'normal'}">${esc(cat)}</button>
                    `;
                }).join('')}
            </div>
            <div style="display:flex; flex-direction:column; gap:6px">
                ${filtered.length ? filtered.map((event) => `
                    <div style="background:#161b22; border:1px solid #30363d; border-radius:8px; padding:10px 14px; display:flex; gap:12px">
                        <div style="display:flex; gap:8px; align-items:center">
                            <span style="font-size:11px; color:#7d8590">${formatDate(event.ts)}</span>
                            <span style="background:#2d2415; color:#d29922; font-size:10px; font-weight:700; padding:3px 8px; border-radius:999px">${esc(event.category || eventCategory(event.message))}</span>
                        </div>
                        <div style="font-size:12px; color:#e6edf3">${esc(event.message || '')}</div>
                    </div>
                `).join('') : `<div style="color:#7d8590; font-size:12px">No events match the current filter.</div>`}
            </div>
        </article>
    `;
}

function dailyChart(history = []) {
    const list = Array.isArray(history) ? history : [];
    if (!list.length) {
        return `<article class="panel"><p class="subtle">No daily history yet.</p></article>`;
    }

    const max = Math.max(...list.map((item) => parseNumber(item.total) || 0), 1);
    const rows = [...list].reverse().slice(0, 12);

    return `
        <article class="panel">
            <div class="panel-header">
                <div class="panel-title">Daily History</div>
                <span class="subtle">Latest 12 days</span>
            </div>
            <div class="daily-chart">
                ${rows.map((item) => {
                    const total = parseNumber(item.total) || 0;
                    const width = Math.max(2, Math.round((total / max) * 100));
                    const dateStr = item.date ? new Date(item.date + 'T00:00:00').toISOString() : '';
                    return `
                        <div class="daily-row">
                            <div class="daily-label">${formatDate(dateStr)}</div>
                            <div class="daily-bar">
                                <div class="daily-fill" style="width:${width}%"></div>
                            </div>
                            <div class="daily-label" style="text-align:right">${total}</div>
                        </div>
                    `;
                }).join('')}
            </div>
        </article>
    `;
}

function inventoryPanel(inventory = {}) {
    const entries = [
        ['apple_model', 'APPLE MODEL', 'apple_model_desc'],
        ['cpu', 'CPU', 'cpu_desc'],
        ['kernel', 'KERNEL', 'kernel_desc'],
        ['gpu', 'GPU', 'gpu_desc'],
        ['wifi_chip', 'WI-FI CHIP', 'wifi_chip_desc'],
        ['bluetooth', 'BLUETOOTH', 'bluetooth_desc'],
        ['audio', 'AUDIO', 'audio_desc'],
        ['camera', 'CAMERA', 'camera_desc'],
        ['usb', 'USB', 'usb_desc'],
        ['thunderbolt', 'THUNDERBOLT', 'thunderbolt_desc'],
        ['screen', 'SCREEN', 'screen_desc'],
        ['storage', 'STORAGE', 'storage_desc'],
    ];

    return `
        <article class="panel">
            <div class="panel-header">
                <div style="display:flex; gap:12px; align-items:center">
                    <div class="panel-title">Hardware Inventory</div>
                </div>
                <span class="subtle">captured at boot</span>
            </div>
            <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(200px, 1fr)); gap:10px">
                ${entries.map(([key, label, descKey]) => {
                    const value = inventory[key];
                    const desc = inventory[descKey];
                    return `
                        <div style="background:#161b22; border:1px solid #30363d; border-radius:8px; padding:12px; display:flex; flex-direction:column; gap:6px">
                            <div style="font-size:10px; color:#7d8590; font-weight:700; letter-spacing:0.8px">${esc(label)}</div>
                            <div style="font-size:12px; color:#e6edf3">${value ? esc(value) : '—'}</div>
                            ${desc ? `<div style="font-size:11px; color:#7d8590">${esc(desc)}</div>` : ''}
                        </div>
                    `;
                }).join('')}
            </div>
        </article>
    `;
}

function render(data) {
    if (!data) {
        return;
    }
    lastData = data;

    const root = document.getElementById('app');
    if (!root) {
        return;
    }

    const generated = data.generated || new Date().toISOString();
    const severity = data.severity || {};
    const counters = data.counters || {};
    const snapshot = data.snapshot || {};
    const driverHealthData = data.driver_health || {};

    root.innerHTML = `
        <section class="shell">
            <header class="header">
                <div>
                    <div class="eyebrow">MBP Watch</div>
                    <div class="title-row">
                        <h1>Hardware stability dashboard</h1>
                    </div>
                    <div class="meta-row">
                        <span>Generated: ${formatDate(generated)}</span>
                        <span>State dir: <span class="mono">${esc(data.state_dir || '/var/lib/mbp-watch')}</span></span>
                    </div>
                </div>
                <div class="actions">
                    <button id="audio-btn" class="button" type="button">Audio off</button>
                    <button id="digest-btn" class="button" type="button">AI digest</button>
                    <button id="wifi-btn" class="button" type="button">📶 Wi-Fi Details</button>
                </div>
            </header>

            ${severityBanner(severity)}

            <section class="metrics">
                ${metricCards(counters)}
            </section>

            <section class="section" id="live" data-persist>
                <div class="section-header">
                    <h2 class="section-title">Live Telemetry</h2>
                    <span class="subtle">${formatDate(snapshot.captured)}</span>
                </div>
                <div class="stack">
                    ${temperaturePanel(snapshot.temperatures || [], snapshot.fan_rpm || '')}
                    ${cpuPerfPanel(snapshot.cpu_perf || {}, counters.throttle || 0)}
                    ${performanceCard(snapshot.load_and_system || {})}
                    <div class="grid" style="grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px;">
                        ${batteryCard(snapshot.battery || {})}
                        ${wifiLinkCard(snapshot.wifi_link || {})}
                    </div>
                </div>
            </section>

            <section class="section" id="events" data-persist>
                <div class="section-header">
                    <h2 class="section-title">Recent Events</h2>
                    <span class="subtle">Journal filter: ${esc(getFilter())}</span>
                </div>
                ${eventsPanel(data.recent_events || [])}
            </section>

            <section class="section" id="drivers" data-persist>
                <div class="section-header">
                    <h2 class="section-title">Driver Health</h2>
                    <span class="subtle">${formatDate(driverHealthData.captured)}</span>
                </div>
                ${driverHealth(driverHealthData)}
            </section>

            <section class="section" id="history" data-persist>
                <div class="section-header">
                    <h2 class="section-title">Daily History</h2>
                    <span class="subtle">Persistent daily counts</span>
                </div>
                ${dailyChart(data.daily_history || [])}
            </section>

            <section class="section" id="inventory" data-persist>
                <div class="section-header">
                    <h2 class="section-title">Hardware Inventory</h2>
                    <span class="subtle">Stable baseline</span>
                </div>
                ${inventoryPanel(data.inventory || {})}
            </section>
        </section>
    `;

    restoreDetailsState();
    updateAudioButton();

    const audioBtn = document.getElementById('audio-btn');
    if (audioBtn) {
        audioBtn.addEventListener('click', () => {
            const enabled = localStorage.getItem(KEY_AUDIO) === '1';
            const next = enabled ? '0' : '1';
            localStorage.setItem(KEY_AUDIO, next);
            if (next === '1') {
                try {
                    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
                    playAlert(false);
                } catch (err) {
                    localStorage.setItem(KEY_AUDIO, '0');
                }
            } else if (audioCtx) {
                try {
                    audioCtx.close();
                } catch (err) {
                    // ignore
                }
                audioCtx = null;
            }
            updateAudioButton();
        });
    }

    const digestBtn = document.getElementById('digest-btn');
    if (digestBtn) {
        digestBtn.addEventListener('click', openDigestModal);
    }

    const wifiBtn = document.getElementById('wifi-btn');
    if (wifiBtn) {
        wifiBtn.addEventListener('click', openWifiModal);
    }

    document.querySelectorAll('[data-filter]').forEach((button) => {
        button.addEventListener('click', () => setFilter(button.getAttribute('data-filter') || 'all'));
    });
}

function flashBanner() {
    const banner = document.querySelector('.banner');
    if (!banner) {
        return;
    }
    banner.style.transition = 'filter 160ms ease, transform 160ms ease';
    banner.style.filter = 'brightness(1.12)';
    banner.style.transform = 'translateY(-1px)';
    window.setTimeout(() => {
        banner.style.filter = '';
        banner.style.transform = '';
    }, 350);
}

function openDigestModal() {
    const modal = document.getElementById('digest-modal');
    const textEl = document.getElementById('digest-text');

    modal.classList.add('active');
    textEl.textContent = 'Loading...';

    fetch('report.txt', { cache: 'no-store' })
        .then((response) => {
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            return response.text();
        })
        .then((text) => {
            textEl.textContent = text;
        })
        .catch((err) => {
            textEl.textContent = `Error loading digest: ${err.message}`;
        });
}

function closeDigestModal() {
    const modal = document.getElementById('digest-modal');
    modal.classList.remove('active');
}

function openModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.classList.add('active');
    }
}

function closeModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.classList.remove('active');
    }
}

function wifiMetricCard(label, value, meta = '') {
    return `
        <article class="wifi-mini-card">
            <div class="wifi-mini-label">${esc(label)}</div>
            <div class="wifi-mini-value">${esc(value)}</div>
            ${meta ? `<div class="wifi-mini-meta">${esc(meta)}</div>` : ''}
        </article>
    `;
}

function renderWifiModalContent(data) {
    const body = document.getElementById('wifi-modal-body');
    if (!body) {
        return;
    }

    const snapshot = data?.snapshot || {};
    const link = snapshot.wifi_link || {};
    const analysis = snapshot.wifi_analysis || {};
    const wifiEvents = (data?.recent_events || []).filter((event) => (event.category || eventCategory(event.message)) === 'wifi').slice(0, 6);
    const status = wifiStatusModel(link);
    const problems = wifiProblems(link, analysis, wifiEvents);
    const signal = status.signal;
    const signalWidth = signal === null ? 0 : Math.max(8, Math.min(100, ((signal + 90) / 60) * 100));
    const channel = parseNumber(analysis.channel) || status.channel;
    const latencyValue = parseNumber(analysis.latency_ms);
    const packetLossValue = parseNumber(analysis.packet_loss_pct);
    const latency = latencyValue === null ? '—' : `${latencyValue} ms`;
    const packetLoss = packetLossValue === null ? '—' : `${packetLossValue}%`;
    const txRate = link.tx_mbps ? `${link.tx_mbps} Mbps` : '—';
    const rxRate = link.rx_mbps ? `${link.rx_mbps} Mbps` : '—';
    const retries = link.tx_retries ?? '—';
    const powerSave = link.power_save || 'unknown';
    const nearbyNetworks = Array.isArray(analysis.nearby_networks) ? analysis.nearby_networks : [];
    const interferenceCount = parseNumber(analysis.interference_count) || 0;
    const scanSource = analysis.scan_source || 'none';
    const pingTarget = analysis.ping_target || '8.8.8.8';
    const nearbyMarkup = nearbyNetworks.length
        ? `
            <div class="wifi-nearby-list">
                ${nearbyNetworks.slice(0, 10).map((network) => `
                    <div class="wifi-nearby-item ${network.same_channel ? 'is-interfering' : ''}">
                        <strong>${esc(network.ssid || '(hidden)')}</strong>
                        <span>Channel ${esc(network.channel ?? '—')} • ${esc(network.signal_dbm ?? '—')} dBm</span>
                    </div>
                `).join('')}
            </div>
        `
        : `
            <div class="wifi-note-card">
                <strong>No nearby scan data.</strong>
                <span>Scan source: ${esc(scanSource)}.</span>
            </div>
        `;
    const eventsMarkup = wifiEvents.length
        ? wifiEvents.map((event) => `
            <div class="wifi-event-row">
                <div class="wifi-event-time">${esc(formatDate(event.ts))}</div>
                <div class="wifi-event-text">${esc(event.message || '')}</div>
            </div>
        `).join('')
        : '<p class="subtle">No recent Wi-Fi journal events.</p>';

    body.innerHTML = `
        <section class="wifi-modal-shell">
            <div class="wifi-modal-header">
                <div>
                    <div class="eyebrow">Integrated View</div>
                    <h3>📶 Wi-Fi Monitor</h3>
                </div>
                <div class="subtle">Snapshot + ping + cached nearby scan from mbp_watch</div>
            </div>

            <div class="wifi-status-card wifi-status-${esc(status.status)}">
                <div class="wifi-status-dot"></div>
                <div class="wifi-status-copy">
                    <strong>${esc(status.title)}</strong>
                    <span>${esc(status.summary)}</span>
                </div>
            </div>

            <div class="wifi-modal-grid">
                ${wifiMetricCard('Signal strength', signal === null ? '—' : `${signal} dBm`, status.quality.label)}
                ${wifiMetricCard('Network info', link.ssid || '—', channel === null ? 'Channel unknown' : `Channel ${channel}`)}
                ${wifiMetricCard('Latency', latency, `Target ${pingTarget}`)}
                ${wifiMetricCard('Packet loss', packetLoss, `Target ${pingTarget}`)}
                ${wifiMetricCard('TX rate', txRate, `Retries ${retries}`)}
                ${wifiMetricCard('Connection', link.connected ? 'Connected' : 'Disconnected', `Power save ${powerSave}`)}
            </div>

            <section class="wifi-detail-card">
                <div class="wifi-detail-head">
                    <h4>Signal quality</h4>
                    <span>${signal === null ? '—' : `${signal} dBm`}</span>
                </div>
                <div class="wifi-bar-track">
                    <div class="wifi-bar-fill wifi-bar-${esc(status.quality.tone)}" style="width:${signalWidth}%"></div>
                </div>
            </section>

            <section class="wifi-detail-card">
                <div class="wifi-detail-head">
                    <h4>Problems detected</h4>
                    <span>${problems.length}</span>
                </div>
                ${problems.length ? `
                    <div class="wifi-problem-list">
                        ${problems.map((problem) => `<div class="wifi-problem-item">${esc(problem)}</div>`).join('')}
                    </div>
                ` : '<p class="subtle">No obvious Wi-Fi issues in the current snapshot.</p>'}
            </section>

            <section class="wifi-detail-card">
                <div class="wifi-detail-head">
                    <h4>Nearby networks / same-channel interference</h4>
                    <span>${interferenceCount} same-channel</span>
                </div>
                ${nearbyMarkup}
            </section>

            <section class="wifi-detail-card">
                <div class="wifi-detail-head">
                    <h4>Link details</h4>
                    <span>${esc(formatDate(snapshot.captured))}</span>
                </div>
                <div class="wifi-table-wrap">
                    <table class="wifi-table">
                        <thead>
                            <tr>
                                <th>SSID</th>
                                <th>Channel</th>
                                <th>Signal</th>
                                <th>TX</th>
                                <th>RX</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td>${esc(link.ssid || '—')}</td>
                                <td>${channel === null ? '—' : esc(channel)}</td>
                                <td>${signal === null ? '—' : esc(`${signal} dBm`)}</td>
                                <td>${esc(txRate)}</td>
                                <td>${esc(rxRate)}</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </section>

            <section class="wifi-detail-card">
                <div class="wifi-detail-head">
                    <h4>Recent Wi-Fi events</h4>
                    <span>${wifiEvents.length}</span>
                </div>
                <div class="wifi-events-list">
                    ${eventsMarkup}
                </div>
            </section>
        </section>
    `;
}

function openWifiModal() {
    if (!lastData) {
        return;
    }
    renderWifiModalContent(lastData);
    openModal(WIFI_MODAL_ID);
}

function downloadDigest() {
    const link = document.createElement('a');
    link.href = 'report.txt';
    link.download = 'report.txt';
    link.click();
}

async function refresh() {
    try {
        const response = await fetch(`data.json?t=${Date.now()}`, { cache: 'no-store' });
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }
        const data = await response.json();
        const total = Number(data?.counters?.total ?? 0);
        const critical = data?.severity?.class === 'critical';

        if (lastTotal !== null && total > lastTotal && localStorage.getItem(KEY_AUDIO) === '1') {
            if (!audioCtx) {
                audioCtx = new (window.AudioContext || window.webkitAudioContext)();
            }
            playAlert(critical);
            flashBanner();
        }

        lastTotal = total;
        saveDetailsState();
        render(data);
        if (wifiModal.classList.contains('active')) {
            renderWifiModalContent(data);
        }
    } catch (err) {
        if (!lastData) {
            const root = document.getElementById('app');
            if (root) {
                root.innerHTML = `
                    <section class="shell shell-loading">
                        <div class="loading-card">
                            <div class="eyebrow">MBP Watch</div>
                            <h1>Waiting for data</h1>
                            <p>Could not load <code>data.json</code> yet.</p>
                        </div>
                    </section>
                `;
            }
        }
    } finally {
        window.setTimeout(refresh, REFRESH_MS);
    }
}

document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && lastData) {
        render(lastData);
    }
});

const digestModal = document.getElementById('digest-modal');
const digestDownload = document.getElementById('digest-download');
const digestClose = digestModal.querySelector('.modal-close');
const digestOverlay = digestModal.querySelector('.modal-overlay');
const wifiModal = document.getElementById(WIFI_MODAL_ID);
const wifiClose = wifiModal.querySelector('[data-modal-close="wifi-modal"]');
const wifiOverlay = wifiModal.querySelector('.modal-overlay');

if (digestClose) {
    digestClose.addEventListener('click', closeDigestModal);
}

if (digestDownload) {
    digestDownload.addEventListener('click', downloadDigest);
}

if (digestOverlay) {
    digestOverlay.addEventListener('click', closeDigestModal);
}

if (wifiClose) {
    wifiClose.addEventListener('click', () => closeModal(WIFI_MODAL_ID));
}

if (wifiOverlay) {
    wifiOverlay.addEventListener('click', () => closeModal(WIFI_MODAL_ID));
}

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') {
        return;
    }

    if (digestModal.classList.contains('active')) {
        closeDigestModal();
    }

    if (wifiModal.classList.contains('active')) {
        closeModal(WIFI_MODAL_ID);
    }
});

restoreDetailsState();
updateAudioButton();
refresh();
