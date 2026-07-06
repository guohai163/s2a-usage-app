(function () {
  const DEFAULT_LIVE_PROBE_INTERVAL_MS = 10000;
  const WINDOWS_LIVE_PROBE_INTERVAL_MS = 30000;
  const gyTools = resolveGyTools();
  const state = {
    endpoint: null,
    endpointError: null,
    liveProbeError: null,
    liveProbeInFlight: false,
    liveProbeGeneration: 0,
    liveTimerId: null,
    loading: false,
    platform: '',
    reset: {
      appVersion: '',
      error: null,
      lastCheckedAt: null,
      loading: false,
      maskedKey: null,
      remaining: null,
      resetting: false,
      statusText: '先查询是否还有重置机会',
    },
    statusRegistered: false,
    statusText: '等待刷新',
    traceStats: {},
    updatedAt: '-',
    usage: null,
    usageError: null,
  };

  const elements = {};

  document.addEventListener('DOMContentLoaded', async () => {
    bindElements();
    bindEvents();

    if (!gyTools || !gyTools.custom) {
      state.usageError = '未检测到 GY Tools 插件 API。';
      state.statusText = state.usageError;
      render();
      return;
    }

    state.platform = String(gyTools?.env?.platform || '').toLowerCase();
    state.reset.appVersion = normalizeAppVersion(gyTools?.env?.appVersion);
    await loadMaskedResetKey();
    await registerStatusPanel();
    await refreshAll();
  });

  function resolveGyTools() {
    if (window.gyTools) return window.gyTools;
    if (typeof require === 'function') {
      try {
        return require('gy-tools');
      } catch (_error) {
        return null;
      }
    }
    return null;
  }

  function bindElements() {
    [
      'copyButton',
      'dailyAmount',
      'dailyFill',
      'dailyPercent',
      'endpointHost',
      'endpointLines',
      'endpointSource',
      'endpointTitle',
      'monthlyAmount',
      'monthlyFill',
      'monthlyPercent',
      'refreshButton',
      'remainingValue',
      'resetButton',
      'resetMaskedKey',
      'resetQueryButton',
      'resetRemainingValue',
      'resetStatusText',
      'schemaLabel',
      'statusText',
      'subtitle',
      'traceCount',
      'traceRoutes',
      'updatedValue',
      'weeklyAmount',
      'weeklyFill',
      'weeklyPercent',
    ].forEach((id) => {
      elements[id] = document.getElementById(id);
    });
  }

  function bindEvents() {
    elements.refreshButton.addEventListener('click', () => {
      refreshAll();
    });
    elements.copyButton.addEventListener('click', () => {
      copyEndpointHost();
    });
    elements.resetQueryButton.addEventListener('click', () => {
      queryResetRemaining();
    });
    elements.resetButton.addEventListener('click', () => {
      resetQuota();
    });
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) {
        stopLiveProbing();
      } else {
        startLiveProbing();
      }
    });
    window.addEventListener('beforeunload', () => {
      stopLiveProbing();
    });

    if (gyTools?.event) {
      gyTools.event.on('statusBarAction', (event) => {
        if (event?.action?.type === 'refresh') {
          refreshAll();
        }
      });
    }
  }

  async function refreshAll() {
    if (state.loading || !gyTools?.custom) return;

    stopLiveProbing();
    state.liveProbeGeneration += 1;
    state.loading = true;
    state.liveProbeError = null;
    state.statusText = '正在刷新...';
    state.usageError = null;
    state.endpointError = null;
    render();
    await updateStatusPanel();

    const cachedCandidates = await loadCachedEndpointCandidates();
    const usagePromise = gyTools.custom.loadUsageSnapshot();
    const endpointPromise = gyTools.custom.loadEndpointRecommendation(cachedCandidates);
    const [usageResult, endpointResult] = await Promise.allSettled([usagePromise, endpointPromise]);
    let shouldStartLiveProbe = false;

    if (usageResult.status === 'fulfilled') {
      state.usage = usageResult.value;
      state.usageError = null;
    } else {
      state.usageError = errorMessage(usageResult.reason);
    }

    if (endpointResult.status === 'fulfilled') {
      resetTraceStats(endpointResult.value?.candidates);
      mergeTraceStats(endpointResult.value);
      state.endpoint = endpointResult.value;
      state.endpointError = null;
      shouldStartLiveProbe = true;
      if (Array.isArray(endpointResult.value?.candidates) && endpointResult.value.candidates.length > 0) {
        await saveCachedEndpointCandidates(endpointResult.value.candidates);
      }
    } else {
      state.endpoint = null;
      state.endpointError = errorMessage(endpointResult.reason);
      state.traceStats = {};
    }

    state.updatedAt = new Date().toLocaleTimeString();
    state.statusText = buildStatusText();
    state.loading = false;
    render();
    await updateStatusPanel();
    if (shouldStartLiveProbe) startLiveProbing();
  }

  function buildStatusText() {
    if (state.usageError) return state.usageError;
    if (state.endpointError) return state.endpointError;
    return state.usage?.note || '已更新。';
  }

  async function registerStatusPanel() {
    if (state.statusRegistered || !gyTools?.statusBar) return;

    try {
      await gyTools.statusBar.register({
        id: 'gytools-plugins-usage-panel',
        title: 'Codex Usage',
        width: 320,
        height: 420,
        actions: [
          { id: 'refresh', type: 'refresh', label: 'Refresh', icon: 'refresh' },
          { id: 'copyEndpoint', type: 'copy', label: 'Copy endpoint', icon: 'copy', textPath: 'endpoint.host' },
          { id: 'openMain', type: 'openMainWindow', label: 'Open', icon: 'openMainWindow' },
        ],
        data: createStatusData(),
        template: [
          {
            type: 'header',
            title: 'Codex Usage',
            subtitle: '读取 ~/.codex 配置',
            caption: '{schema}',
            buttons: ['refresh', 'openMain'],
          },
          { type: 'summary', value: '{remainingPercent}%', caption: 'REMAINING' },
          {
            type: 'meter',
            title: 'Daily',
            icon: 'D',
            color: 'blue',
            valuePath: 'daily.usage',
            maxPath: 'daily.limit',
            amount: '{daily.amount}',
          },
          {
            type: 'meter',
            title: 'Weekly',
            icon: 'W',
            color: 'green',
            valuePath: 'weekly.usage',
            maxPath: 'weekly.limit',
            amount: '{weekly.amount}',
          },
          {
            type: 'meter',
            title: 'Monthly',
            icon: 'M',
            color: 'purple',
            valuePath: 'monthly.usage',
            maxPath: 'monthly.limit',
            amount: '{monthly.amount}',
          },
          {
            type: 'list',
            title: 'Endpoint',
            caption: '{endpoint.source}',
            itemsPath: 'endpoint.lines',
            emptyText: 'No endpoint',
            maxItems: 5,
          },
          { type: 'button', actionId: 'copyEndpoint', label: 'Copy {endpoint.host}', variant: 'default' },
          { type: 'footer', left: 'Expires: {expiresAt}', right: '{updatedAt}' },
        ],
      });
      state.statusRegistered = true;
    } catch (error) {
      state.statusText = `状态栏注册失败: ${errorMessage(error)}`;
      gyTools?.logOutput?.error?.(error);
    }
  }

  async function updateStatusPanel() {
    if (!gyTools?.statusBar) return;
    if (!state.statusRegistered) {
      await registerStatusPanel();
      return;
    }
    try {
      await gyTools.statusBar.update(createStatusData());
    } catch (error) {
      gyTools?.logOutput?.error?.(error);
    }
  }

  function createStatusData() {
    const usage = state.usage || emptyUsage();
    const endpoint = createEndpointData();

    return {
      schema: state.usageError ? 'ERROR' : usage.schemaLabel,
      remainingPercent: remainingPercent(usage),
      daily: periodData(usage.dailyUsage, usage.dailyLimit),
      weekly: periodData(usage.weeklyUsage, usage.weeklyLimit),
      monthly: periodData(usage.monthlyUsage, usage.monthlyLimit),
      endpoint,
      expiresAt: usage.expiresAt === '-' ? 'Never' : usage.expiresAt,
      updatedAt: state.updatedAt,
      statusText: state.statusText,
    };
  }

  function createEndpointData() {
    if (state.endpoint) {
      return {
        host: state.endpoint.recommendedHost || '-',
        source: state.endpoint.sourceLabel || '-',
        lines: normalizeLines(state.endpoint.detailLines),
      };
    }

    if (state.endpointError) {
      return {
        host: '-',
        source: 'ERROR',
        lines: [state.endpointError],
      };
    }

    return {
      host: '-',
      source: state.loading ? 'NETWORK' : '-',
      lines: [state.loading ? '正在读取公共设置并运行路由探测' : '等待探测'],
    };
  }

  function emptyUsage() {
    return {
      dailyUsage: 0,
      dailyLimit: 1,
      weeklyUsage: 0,
      weeklyLimit: 1,
      monthlyUsage: 0,
      monthlyLimit: 1,
      expiresAt: '-',
      remaining: null,
      schemaLabel: state.loading ? 'LOADING' : 'WAITING',
      note: null,
    };
  }

  function render() {
    const usage = state.usage || emptyUsage();
    const statusData = createStatusData();

    elements.refreshButton.disabled = state.loading;
    elements.subtitle.textContent = state.usageError ? '读取失败' : '读取本机 Codex 配置';
    elements.remainingValue.textContent = usage.remaining != null
      ? `$${formatAmount(usage.remaining)}`
      : `${statusData.remainingPercent}%`;
    elements.schemaLabel.textContent = state.usageError ? 'ERROR' : usage.schemaLabel;
    elements.updatedValue.textContent = state.updatedAt;
    elements.statusText.textContent = state.statusText;

    renderResetPanel();
    renderPeriod('daily', usage.dailyUsage, usage.dailyLimit);
    renderPeriod('weekly', usage.weeklyUsage, usage.weeklyLimit);
    renderPeriod('monthly', usage.monthlyUsage, usage.monthlyLimit);
    renderEndpoint(statusData.endpoint);
    renderTraceRoutes();
  }

  function renderResetPanel() {
    const remaining = Number(state.reset.remaining);
    const hasKnownRemaining = Number.isFinite(remaining);
    const hasOpportunity = hasKnownRemaining && remaining > 0;
    const busy = state.reset.loading || state.reset.resetting;
    const hasApi = Boolean(gyTools?.custom?.checkQuotaResetRemaining && gyTools?.custom?.resetQuota);
    const versionSupported = isResetVersionSupported();

    elements.resetRemainingValue.textContent = hasKnownRemaining ? `${remaining} 次` : '-';
    elements.resetMaskedKey.textContent = state.reset.maskedKey
      ? `KEY ${state.reset.maskedKey}`
      : 'KEY -';
    elements.resetQueryButton.disabled = busy || !hasApi;
    elements.resetButton.disabled = busy || !hasApi || !hasOpportunity;
    elements.resetStatusText.textContent = hasApi
      ? state.reset.statusText
      : '当前插件 API 不支持重置功能。';

    if (hasApi && hasOpportunity && !versionSupported && !busy && !isVersionGateMessage(state.reset.statusText)) {
      elements.resetStatusText.textContent = versionGateMessage();
    }
  }

  async function loadMaskedResetKey() {
    if (!gyTools?.custom?.getMaskedAPIKey) return;

    try {
      const result = await gyTools.custom.getMaskedAPIKey();
      state.reset.maskedKey = typeof result?.maskedKey === 'string' && result.maskedKey.trim()
        ? result.maskedKey.trim()
        : null;
    } catch (_error) {
      state.reset.maskedKey = null;
    }
  }

  async function queryResetRemaining() {
    if (state.reset.loading || state.reset.resetting || !gyTools?.custom?.checkQuotaResetRemaining) return;

    state.reset.loading = true;
    state.reset.error = null;
    state.reset.statusText = '正在查询重置机会...';
    render();

    try {
      const result = await gyTools.custom.checkQuotaResetRemaining();
      const remaining = normalizeRemaining(result?.remaining);
      state.reset.remaining = remaining;
      state.reset.lastCheckedAt = new Date().toLocaleTimeString();
      state.reset.statusText = remaining > 0
        ? `还有 ${remaining} 次重置机会，可以执行重置。`
        : '当前没有可用的重置机会。';
      if (result?.message) {
        state.reset.statusText += ` ${result.message}`;
      }
    } catch (error) {
      state.reset.error = errorMessage(error);
      state.reset.remaining = null;
      state.reset.statusText = `查询失败: ${state.reset.error}`;
    } finally {
      state.reset.loading = false;
      render();
      await updateStatusPanel();
    }
  }

  async function resetQuota() {
    const remaining = normalizeRemaining(state.reset.remaining);
    if (state.reset.loading || state.reset.resetting || remaining <= 0 || !gyTools?.custom?.resetQuota) return;
    if (!isResetVersionSupported()) {
      state.reset.error = null;
      state.reset.statusText = versionGateMessage();
      render();
      await updateStatusPanel();
      return;
    }

    state.reset.resetting = true;
    state.reset.error = null;
    state.reset.statusText = '正在请求重置用量...';
    render();

    try {
      const result = await gyTools.custom.resetQuota();
      if (result?.success === false) {
        throw new Error(result.message || '重置接口返回失败。');
      }

      let verifiedRemaining = null;
      let verifyError = null;
      try {
        const verifyResult = await gyTools.custom.checkQuotaResetRemaining();
        verifiedRemaining = normalizeRemaining(verifyResult?.remaining);
        state.reset.remaining = verifiedRemaining;
        state.reset.lastCheckedAt = new Date().toLocaleTimeString();
      } catch (error) {
        verifyError = error;
      }

      if (verifiedRemaining != null) {
        if (verifiedRemaining >= remaining) {
          throw new Error(
            result?.message || `剩余重置机会仍然是 ${verifiedRemaining} 次，系统没有确认本次重置成功。`,
          );
        }
        state.reset.statusText = result?.message || `重置成功，剩余 ${verifiedRemaining} 次机会。`;
      } else if (result?.success === true) {
        const fallbackRemaining = result?.remaining != null
          ? normalizeRemaining(result.remaining)
          : Math.max(remaining - 1, 0);
        state.reset.remaining = fallbackRemaining;
        state.reset.statusText = `重置请求已返回成功，但校验剩余机会失败：${errorMessage(verifyError)}`;
      } else {
        throw new Error(
          `重置接口返回结果不明确，且校验剩余机会失败：${errorMessage(verifyError)}`,
        );
      }

      await refreshAll();
    } catch (error) {
      state.reset.error = errorMessage(error);
      state.reset.statusText = `重置失败: ${state.reset.error}`;
    } finally {
      state.reset.resetting = false;
      render();
      await updateStatusPanel();
    }
  }

  function renderPeriod(key, usage, limit) {
    const percent = limit > 0 ? Math.max(0, Math.min(usage / limit * 100, 100)) : 0;
    elements[`${key}Percent`].textContent = `${percent.toFixed(1)}%`;
    elements[`${key}Fill`].style.width = `${percent}%`;
    elements[`${key}Amount`].textContent = `$${formatAmount(usage)} / $${formatAmount(limit)}`;
  }

  function renderEndpoint(endpoint) {
    const hasHost = endpoint.host && endpoint.host !== '-';
    elements.endpointTitle.textContent = state.endpoint?.headline || (state.endpointError ? '节点推荐 暂不可用' : '节点推荐 -');
    elements.endpointSource.textContent = endpoint.source;
    elements.endpointSource.classList.toggle('error', endpoint.source === 'ERROR');
    elements.endpointHost.textContent = endpoint.host;
    elements.copyButton.disabled = !hasHost;

    elements.endpointLines.classList.toggle('error', endpoint.source === 'ERROR');
    elements.endpointLines.replaceChildren(...endpoint.lines.map((line) => {
      const item = document.createElement('li');
      item.textContent = line;
      return item;
    }));
  }

  function renderTraceRoutes() {
    const groups = Array.isArray(state.endpoint?.traceGroups) ? state.endpoint.traceGroups : [];
    const maxSamples = Math.max(0, ...Object.values(state.traceStats).map((stats) => stats.samples || 0));
    const probing = state.liveProbeInFlight ? ' · probing' : '';
    const liveError = state.liveProbeError ? ' · retrying' : '';
    elements.traceCount.textContent = `${groups.length} nodes · ${maxSamples} samples${probing}${liveError}`;

    if (groups.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'trace-card';
      const summary = document.createElement('div');
      summary.className = 'trace-summary';
      summary.textContent = '等待路由链路数据';
      empty.appendChild(summary);
      elements.traceRoutes.replaceChildren(empty);
      return;
    }

    elements.traceRoutes.replaceChildren(...groups.map((group) => {
      const card = document.createElement('article');
      card.className = `trace-card${group.isRecommended ? ' recommended' : ''}`;

      const head = document.createElement('div');
      head.className = 'trace-card-head';

      const title = document.createElement('div');
      title.className = 'trace-card-title';
      const name = document.createElement('strong');
      name.textContent = group.name || group.host || '-';
      const host = document.createElement('code');
      host.textContent = group.host || '-';
      title.append(name, host);
      head.appendChild(title);

      if (group.isRecommended) {
        const badge = document.createElement('span');
        badge.className = 'trace-badge';
        badge.textContent = '推荐';
        head.appendChild(badge);
      }

      const summary = document.createElement('div');
      summary.className = 'trace-summary';
      summary.textContent = liveTraceSummary(group);

      const table = document.createElement('div');
      table.className = 'mtr-table';
      table.setAttribute('role', 'table');
      table.appendChild(createMtrHeader());
      const hops = Array.isArray(group.hops) && group.hops.length > 0
        ? group.hops
        : [{ index: '-', text: group.summaryText || '没有路由探测输出', sampleLatenciesMs: [], expectedProbeCount: 1 }];
      table.append(...hops.map((hop) => createMtrRow(group.host, hop)));

      card.append(head, summary, table);
      return card;
    }));
  }

  function createMtrHeader() {
    const header = document.createElement('div');
    header.className = 'mtr-row mtr-head';
    header.setAttribute('role', 'row');
    [
      'Host',
      'Loss%',
      'Snt',
      'Last',
      'Avg',
      'Best',
      'Wrst',
      'StDev',
    ].forEach((label) => {
      const cell = document.createElement('span');
      cell.textContent = label;
      header.appendChild(cell);
    });
    return header;
  }

  function createMtrRow(host, hop) {
    const metrics = liveHopMetrics(host, hop);
    const row = document.createElement('div');
    row.className = 'mtr-row';
    row.setAttribute('role', 'row');

    const hostCell = document.createElement('span');
    hostCell.className = 'mtr-host';
    const hostLabel = hop.timedOut && (!hop.address || hop.address === '*')
      ? '(waiting for reply)'
      : hop.address || hop.text || '-';
    hostCell.textContent = `${hop.index || '-'}. ${hostLabel}`;
    hostCell.title = hop.text || '';
    row.appendChild(hostCell);

    [
      `${metrics.loss}%`,
      metrics.sent,
      formatLatency(metrics.last),
      formatLatency(metrics.avg),
      formatLatency(metrics.best),
      formatLatency(metrics.worst),
      formatLatency(metrics.stdev),
    ].forEach((value) => {
      const cell = document.createElement('span');
      cell.className = 'mtr-number';
      cell.textContent = String(value);
      row.appendChild(cell);
    });

    return row;
  }

  function liveTraceSummary(group) {
    const stats = state.traceStats[group.host];
    const sampleText = stats?.samples ? `${stats.samples} samples` : '0 samples';
    const status = state.liveProbeInFlight ? ' · 正在探测' : '';
    const error = state.liveProbeError ? ` · ${state.liveProbeError}` : '';
    return `${group.summaryText || '-'} · ${sampleText}${status}${error}`;
  }

  function liveHopMetrics(host, hop) {
    const stats = state.traceStats[host]?.hops?.[String(hop.index)];
    if (!stats) {
      const sampleLatenciesMs = normalizedHopSamples(hop);
      const inlineStats = summarizeLatencies(sampleLatenciesMs);
      const expectedProbeCount = normalizedExpectedProbeCount(hop);
      return {
        avg: inlineStats.avg,
        best: inlineStats.best,
        last: inlineStats.last,
        loss: expectedProbeCount > 0
          ? Number(((expectedProbeCount - sampleLatenciesMs.length) / expectedProbeCount * 100).toFixed(1))
          : 0,
        sent: expectedProbeCount,
        stdev: inlineStats.stdev,
        worst: inlineStats.worst,
      };
    }

    const avg = stats.received > 0 ? stats.totalLatency / stats.received : null;
    const variance = stats.received > 1
      ? Math.max(0, stats.totalLatencySquared / stats.received - avg * avg)
      : 0;
    return {
      avg,
      best: stats.bestLatencyMs,
      last: stats.latestLatencyMs,
      loss: stats.sent > 0 ? Number((stats.lost / stats.sent * 100).toFixed(1)) : 0,
      sent: stats.sent,
      stdev: stats.received > 1 ? Math.sqrt(variance) : 0,
      worst: stats.worstLatencyMs,
    };
  }

  function periodData(usage, limit) {
    const safeUsage = roundNumber(usage);
    const safeLimit = roundNumber(limit || 1);
    return {
      usage: safeUsage,
      limit: safeLimit,
      amount: `$${formatAmount(safeUsage)} / $${formatAmount(safeLimit)}`,
    };
  }

  function remainingPercent(usage) {
    if (!usage || usage.dailyLimit <= 0) return 0;
    return Math.max(0, Math.min(100, Math.round(100 - usage.dailyUsage / usage.dailyLimit * 100)));
  }

  function normalizeRemaining(value) {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(0, Math.floor(number)) : 0;
  }

  function normalizeAppVersion(value) {
    return typeof value === 'string' ? value.trim() : '';
  }

  function isResetVersionSupported() {
    const appVersion = state.reset.appVersion;
    if (!appVersion) return false;
    return compareVersions(appVersion, '1.8.0') >= 0;
  }

  function versionGateMessage() {
    const current = state.reset.appVersion || '未知版本';
    return `当前版本 ${current} 过低，请升级到 1.8.0 以上版本后再执行重置。`;
  }

  function isVersionGateMessage(text) {
    return typeof text === 'string' && text.includes('请升级到 1.8.0 以上版本');
  }

  function compareVersions(left, right) {
    const leftParts = versionParts(left);
    const rightParts = versionParts(right);
    const length = Math.max(leftParts.length, rightParts.length);

    for (let index = 0; index < length; index += 1) {
      const leftValue = leftParts[index] || 0;
      const rightValue = rightParts[index] || 0;
      if (leftValue > rightValue) return 1;
      if (leftValue < rightValue) return -1;
    }
    return 0;
  }

  function versionParts(value) {
    const matches = String(value || '').match(/\d+/g) || [];
    return matches
      .map((part) => Number.parseInt(part, 10))
      .filter((part) => Number.isFinite(part));
  }

  function normalizeLines(lines) {
    if (!Array.isArray(lines) || lines.length === 0) return ['没有可展示的节点数据'];
    return lines.slice(0, 5).map((line) => String(line || '-'));
  }

  async function loadCachedEndpointCandidates() {
    if (!gyTools?.storage) return [];
    try {
      const raw = await gyTools.storage.getData();
      if (!raw) return [];
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed.endpointCandidates) ? parsed.endpointCandidates : [];
    } catch (error) {
      gyTools?.logOutput?.warn?.('读取节点缓存失败', error);
      return [];
    }
  }

  async function saveCachedEndpointCandidates(candidates) {
    if (!gyTools?.storage) return;
    try {
      await gyTools.storage.saveData(JSON.stringify({ endpointCandidates: candidates }));
    } catch (error) {
      gyTools?.logOutput?.warn?.('保存节点缓存失败', error);
    }
  }

  function startLiveProbing() {
    if (state.liveTimerId || document.hidden || state.loading) return;
    if (!gyTools?.custom?.probeEndpointCandidates) return;
    if (!Array.isArray(state.endpoint?.candidates) || state.endpoint.candidates.length === 0) return;

    state.liveTimerId = setInterval(() => {
      runLiveProbe();
    }, liveProbeIntervalMs());
  }

  function stopLiveProbing() {
    if (!state.liveTimerId) return;
    clearInterval(state.liveTimerId);
    state.liveTimerId = null;
  }

  async function runLiveProbe() {
    if (state.liveProbeInFlight || state.loading || document.hidden) return;
    if (!Array.isArray(state.endpoint?.candidates) || state.endpoint.candidates.length === 0) return;

    const generation = state.liveProbeGeneration;
    state.liveProbeInFlight = true;
    state.liveProbeError = null;
    render();

    try {
      const nextEndpoint = await gyTools.custom.probeEndpointCandidates(state.endpoint.candidates);
      if (generation !== state.liveProbeGeneration) return;
      mergeTraceStats(nextEndpoint);
      state.endpoint = nextEndpoint;
      state.endpointError = null;
      state.updatedAt = new Date().toLocaleTimeString();
      state.statusText = buildStatusText();
    } catch (error) {
      if (generation !== state.liveProbeGeneration) return;
      state.liveProbeError = errorMessage(error);
      state.statusText = `持续探测失败: ${state.liveProbeError}`;
    } finally {
      state.liveProbeInFlight = false;
      if (generation === state.liveProbeGeneration) {
        render();
        await updateStatusPanel();
      }
    }
  }

  function resetTraceStats(candidates) {
    const hosts = new Set((Array.isArray(candidates) ? candidates : [])
      .map((candidate) => candidate?.host)
      .filter(Boolean));
    const nextStats = {};
    for (const host of hosts) {
      nextStats[host] = { samples: 0, hops: {} };
    }
    state.traceStats = nextStats;
  }

  function mergeTraceStats(endpoint) {
    const groups = Array.isArray(endpoint?.traceGroups) ? endpoint.traceGroups : [];
    for (const group of groups) {
      if (!group.host) continue;
      const hostStats = state.traceStats[group.host] || { samples: 0, hops: {} };
      hostStats.samples += 1;

      for (const hop of Array.isArray(group.hops) ? group.hops : []) {
        const key = String(hop.index || '-');
        if (key === '-') continue;
        const hopStats = hostStats.hops[key] || {
          sent: 0,
          lost: 0,
          received: 0,
          bestLatencyMs: null,
          worstLatencyMs: null,
          totalLatency: 0,
          totalLatencySquared: 0,
          latestLatencyMs: null,
        };
        const sampleLatenciesMs = normalizedHopSamples(hop);
        const expectedProbeCount = normalizedExpectedProbeCount(hop);
        hopStats.sent += expectedProbeCount;
        hopStats.lost += Math.max(0, expectedProbeCount - sampleLatenciesMs.length);

        for (const sampleLatency of sampleLatenciesMs) {
          hopStats.received += 1;
          hopStats.totalLatency += sampleLatency;
          hopStats.totalLatencySquared += sampleLatency * sampleLatency;
          hopStats.latestLatencyMs = sampleLatency;
          hopStats.bestLatencyMs = hopStats.bestLatencyMs == null
            ? sampleLatency
            : Math.min(hopStats.bestLatencyMs, sampleLatency);
          hopStats.worstLatencyMs = hopStats.worstLatencyMs == null
            ? sampleLatency
            : Math.max(hopStats.worstLatencyMs, sampleLatency);
        }
        hostStats.hops[key] = hopStats;
      }

      state.traceStats[group.host] = hostStats;
    }
  }

  function normalizedHopSamples(hop) {
    if (Array.isArray(hop?.sampleLatenciesMs)) {
      return hop.sampleLatenciesMs
        .map((value) => Number(value))
        .filter((value) => Number.isFinite(value));
    }
    const fallbackLatency = Number(hop?.latencyMs);
    return Number.isFinite(fallbackLatency) ? [fallbackLatency] : [];
  }

  function normalizedExpectedProbeCount(hop) {
    const expected = Number(hop?.expectedProbeCount);
    return Number.isFinite(expected) && expected > 0 ? expected : 1;
  }

  function summarizeLatencies(latencies) {
    if (!Array.isArray(latencies) || latencies.length === 0) {
      return {
        avg: null,
        best: null,
        last: null,
        stdev: null,
        worst: null,
      };
    }

    const total = latencies.reduce((sum, value) => sum + value, 0);
    const avg = total / latencies.length;
    const variance = latencies.length > 1
      ? latencies.reduce((sum, value) => sum + (value - avg) * (value - avg), 0) / latencies.length
      : 0;

    return {
      avg,
      best: Math.min(...latencies),
      last: latencies[latencies.length - 1],
      stdev: latencies.length > 1 ? Math.sqrt(variance) : 0,
      worst: Math.max(...latencies),
    };
  }

  function liveProbeIntervalMs() {
    return state.platform === 'win32'
      ? WINDOWS_LIVE_PROBE_INTERVAL_MS
      : DEFAULT_LIVE_PROBE_INTERVAL_MS;
  }

  async function copyEndpointHost() {
    const host = state.endpoint?.recommendedHost;
    if (!host) return;

    try {
      await navigator.clipboard.writeText(host);
      state.statusText = `已复制域名 ${host}`;
    } catch (_error) {
      state.statusText = '复制失败，请手动选择域名。';
    }
    render();
    await updateStatusPanel();
  }

  function errorMessage(error) {
    if (!error) return '未知错误';
    if (typeof error === 'string') return error;
    return error.message || String(error);
  }

  function formatAmount(value) {
    const number = Number.isFinite(Number(value)) ? Number(value) : 0;
    if (Math.round(number) === number) return String(number);
    if (Math.abs(number) < 10) return number.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
    return number.toFixed(1).replace(/0+$/, '').replace(/\.$/, '');
  }

  function formatLatency(value) {
    const number = Number(value);
    if (!Number.isFinite(number)) return '-';
    return `${number.toFixed(1).replace(/\.0$/, '')} ms`;
  }

  function roundNumber(value) {
    const number = Number.isFinite(Number(value)) ? Number(value) : 0;
    return Number(number.toFixed(4));
  }
})();
