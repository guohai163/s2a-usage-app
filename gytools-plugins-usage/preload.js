const fs = require('fs');
const http = require('http');
const https = require('https');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const AUTH_PATH = path.join(os.homedir(), '.codex', 'auth.json');
const CONFIG_PATH = path.join(os.homedir(), '.codex', 'config.toml');
const REQUEST_TIMEOUT_MS = 15000;
const SETTINGS_TIMEOUT_MS = 12000;
const MAC_TRACEROUTE_TIMEOUT_MS = 20000;
const WINDOWS_TRACERT_TIMEOUT_MS = 60000;
const QUOTA_REMAINING_URL = 'https://s2adb.gydev.cn/api/quota/remaining';
const QUOTA_RESET_URL = 'https://s2adb.gydev.cn/api/quota/reset';

async function loadUsageSnapshot() {
  const apiKey = await loadAPIKey();
  const baseURL = await loadBaseURL();
  const payload = await requestJSON(`${baseURL}/v1/usage`, {
    headers: { Authorization: `Bearer ${apiKey}` },
    statusMessage: '请求用量接口失败',
    timeoutMs: REQUEST_TIMEOUT_MS,
  });

  return parseSnapshot(payload);
}

async function loadEndpointRecommendation(cachedCandidates = []) {
  let baseURL = null;
  let apiKey = null;
  let fallbackError = null;

  try {
    baseURL = await loadBaseURL();
    apiKey = await loadAPIKey().catch(() => null);
  } catch (error) {
    fallbackError = error;
  }

  if (baseURL) {
    try {
      const settingsURL = publicSettingsURL(baseURL);
      const payload = await requestJSON(settingsURL, {
        headers: apiKey ? { Authorization: `Bearer ${apiKey}` } : {},
        statusMessage: '请求公共设置失败',
        timeoutMs: SETTINGS_TIMEOUT_MS,
      });
      const candidates = parseEndpointCandidates(payload);
      return probeEndpoints(candidates, false, null, candidates);
    } catch (error) {
      fallbackError = error;
    }
  }

  const normalizedCache = normalizeCachedCandidates(cachedCandidates);
  if (normalizedCache.length > 0) {
    return probeEndpoints(
      normalizedCache,
      true,
      fallbackError ? fallbackError.message : '公共设置不可用',
      normalizedCache,
    );
  }

  throw fallbackError || new Error('公共设置中没有可识别的 custom_endpoints 节点。');
}

async function probeEndpointCandidates(candidates = []) {
  const normalizedCandidates = normalizeCachedCandidates(candidates);
  if (normalizedCandidates.length === 0) {
    throw new Error('没有可探测的 custom_endpoints 节点。');
  }
  return probeEndpoints(normalizedCandidates, false, null, normalizedCandidates);
}

async function checkQuotaResetRemaining() {
  const apiKey = await loadAPIKey();
  const payload = await requestJSON(QUOTA_REMAINING_URL, {
    body: JSON.stringify({ key: apiKey }),
    headers: { 'Content-Type': 'application/json' },
    method: 'POST',
    statusMessage: '查询重置机会失败',
    timeoutMs: REQUEST_TIMEOUT_MS,
  });
  return parseQuotaRemaining(payload);
}

async function resetQuota() {
  const apiKey = await loadAPIKey();
  const payload = await requestJSON(QUOTA_RESET_URL, {
    body: JSON.stringify({ key: apiKey }),
    headers: { 'Content-Type': 'application/json' },
    method: 'POST',
    statusMessage: '重置用量失败',
    timeoutMs: REQUEST_TIMEOUT_MS,
  });
  return parseQuotaReset(payload);
}

async function getMaskedAPIKey() {
  const apiKey = await loadAPIKey();
  return {
    maskedKey: maskAPIKey(apiKey),
  };
}

async function loadAPIKey() {
  if (!fs.existsSync(AUTH_PATH)) {
    throw new Error(`未找到文件: ${AUTH_PATH}`);
  }

  try {
    const text = await fs.promises.readFile(AUTH_PATH, 'utf8');
    const payload = JSON.parse(text);
    const value = String(payload.OPENAI_API_KEY || '').trim();
    if (!value) throw new Error('auth.json 缺少有效的 OPENAI_API_KEY。');
    return value;
  } catch (error) {
    if (error instanceof SyntaxError) {
      throw new Error(`JSON 格式不正确: ${error.message}`);
    }
    throw error;
  }
}

async function loadBaseURL() {
  if (!fs.existsSync(CONFIG_PATH)) {
    throw new Error(`未找到文件: ${CONFIG_PATH}`);
  }

  try {
    const text = await fs.promises.readFile(CONFIG_PATH, 'utf8');
    const value = parseOpenAIBaseURL(text);
    if (!value) throw new Error('config.toml 缺少有效的 [model_providers.OpenAI].base_url。');
    return normalizeBaseURL(value);
  } catch (error) {
    throw error;
  }
}

function parseOpenAIBaseURL(text) {
  let inOpenAIProvider = false;

  for (const rawLine of String(text).split(/\r?\n/)) {
    const line = stripComment(rawLine).trim();
    if (!line) continue;

    if (line.startsWith('[') && line.endsWith(']')) {
      inOpenAIProvider = line === '[model_providers.OpenAI]';
      continue;
    }
    if (!inOpenAIProvider) continue;

    const equalsIndex = line.indexOf('=');
    if (equalsIndex < 0) continue;
    const key = line.slice(0, equalsIndex).trim();
    if (key !== 'base_url') continue;

    const rawValue = line.slice(equalsIndex + 1).trim();
    const unquoted = rawValue.replace(/^['"]|['"]$/g, '').trim();
    return unquoted || null;
  }

  return null;
}

function stripComment(line) {
  let quote = null;
  let escaped = false;
  let result = '';

  for (const character of String(line)) {
    if ((character === '"' || character === "'") && !escaped) {
      quote = quote === character ? null : quote || character;
    }
    if (character === '#' && !quote) break;
    result += character;
    escaped = character === '\\' && !escaped;
    if (character !== '\\') escaped = false;
  }

  return result;
}

function normalizeBaseURL(value) {
  let normalized = String(value || '').trim();
  if (!normalized) throw new Error('config.toml 缺少有效的 [model_providers.OpenAI].base_url。');
  if (normalized.startsWith('//')) {
    normalized = `https:${normalized}`;
  } else if (!normalized.includes('://')) {
    normalized = `https://${normalized}`;
  }

  try {
    const url = new URL(normalized);
    return url.toString().replace(/\/+$/, '');
  } catch (_error) {
    throw new Error(`接口地址无效: ${value}`);
  }
}

function maskAPIKey(value) {
  const key = String(value || '').trim();
  if (!key) return '-';
  if (key.length <= 20) return key;
  return `${key.slice(0, 10)}...${key.slice(-10)}`;
}

function requestJSON(urlString, options = {}) {
  const {
    body = null,
    headers = {},
    method = 'GET',
    redirectCount = 0,
    statusMessage = '请求失败',
    timeoutMs = REQUEST_TIMEOUT_MS,
  } = options;

  return new Promise((resolve, reject) => {
    let url;
    try {
      url = new URL(urlString);
    } catch (_error) {
      reject(new Error(`接口地址无效: ${urlString}`));
      return;
    }

    const transport = url.protocol === 'http:' ? http : https;
    const requestHeaders = { ...headers };
    if (body != null && requestHeaders['Content-Length'] == null && requestHeaders['content-length'] == null) {
      requestHeaders['Content-Length'] = Buffer.byteLength(body);
    }
    const request = transport.request(url, { headers: requestHeaders, method }, (response) => {
      const statusCode = response.statusCode || 0;
      const location = response.headers.location;
      if (statusCode >= 300 && statusCode < 400 && location && redirectCount < 3) {
        response.resume();
        requestJSON(new URL(location, url).toString(), {
          body,
          headers,
          method,
          redirectCount: redirectCount + 1,
          statusMessage,
          timeoutMs,
        }).then(resolve, reject);
        return;
      }

      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => {
        const body = Buffer.concat(chunks).toString('utf8');
        if (statusCode < 200 || statusCode >= 300) {
          reject(new Error(`${statusMessage}，HTTP 状态码: ${statusCode}`));
          return;
        }
        if (!body.trim()) {
          reject(new Error(`${statusMessage}: 响应为空`));
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch (error) {
          reject(new Error(`JSON 格式不正确: ${error.message}`));
        }
      });
    });

    request.on('error', (error) => {
      reject(new Error(`网络请求失败: ${error.message}`));
    });
    request.setTimeout(timeoutMs, () => {
      request.destroy(new Error('请求超时'));
    });
    if (body != null) {
      request.write(body);
    }
    request.end();
  });
}

function parseQuotaRemaining(payload) {
  const remaining = findFirstNumber(payload, [
    'remaining',
    'remain',
    'count',
    'quota',
    'chance',
    'chances',
    'resetRemaining',
    'reset_remaining',
    'remainingResets',
    'remaining_resets',
  ]);
  if (remaining == null) {
    throw new Error('重置机会响应中没有可识别的 remaining/count 字段。');
  }

  return {
    remaining: Math.max(0, Math.floor(remaining)),
    message: findMessage(payload),
    raw: payload,
  };
}

function parseQuotaReset(payload) {
  const explicitSuccess = findFirstBoolean(payload, ['success', 'ok']);
  const code = findFirstNumber(payload, ['code', 'statusCode']);
  const status = findFirstText(payload, ['status', 'state', 'result']);
  const success = explicitSuccess != null
    ? explicitSuccess
    : code != null
      ? code === 0 || (code >= 200 && code < 300)
      : status
        ? ['ok', 'success', 'succeeded', 'done'].includes(status.toLowerCase())
        : null;
  const remaining = findFirstNumber(payload, [
    'remaining',
    'remain',
    'count',
    'resetRemaining',
    'reset_remaining',
    'remainingResets',
    'remaining_resets',
  ]);

  return {
    success,
    hasExplicitOutcome: explicitSuccess != null || code != null || status != null,
    remaining: remaining == null ? null : Math.max(0, Math.floor(remaining)),
    message: findMessage(payload) || (success === false ? '重置失败。' : null),
    raw: payload,
  };
}

function findMessage(value) {
  return findFirstText(value, ['message', 'msg', 'detail', 'error', 'reason']);
}

function findFirstNumber(value, keys) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findFirstNumber(item, keys);
      if (found != null) return found;
    }
    return null;
  }
  if (!isRecord(value)) return null;

  for (const key of keys) {
    if (value[key] == null) continue;
    const found = findFirstNumber(value[key], keys);
    if (found != null) return found;
  }
  for (const nested of ['data', 'result', 'payload']) {
    if (value[nested] == null) continue;
    const found = findFirstNumber(value[nested], keys);
    if (found != null) return found;
  }
  return null;
}

function findFirstBoolean(value, keys) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (['true', 'yes', 'ok', 'success', '1'].includes(normalized)) return true;
    if (['false', 'no', 'fail', 'failed', '0'].includes(normalized)) return false;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findFirstBoolean(item, keys);
      if (found != null) return found;
    }
    return null;
  }
  if (!isRecord(value)) return null;

  for (const key of keys) {
    if (value[key] == null) continue;
    const found = findFirstBoolean(value[key], keys);
    if (found != null) return found;
  }
  for (const nested of ['data', 'result', 'payload']) {
    if (value[nested] == null) continue;
    const found = findFirstBoolean(value[nested], keys);
    if (found != null) return found;
  }
  return null;
}

function findFirstText(value, keys) {
  if (typeof value === 'string' && value.trim()) return value.trim();
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findFirstText(item, keys);
      if (found) return found;
    }
    return null;
  }
  if (!isRecord(value)) return null;

  for (const key of keys) {
    if (typeof value[key] === 'string' && value[key].trim()) {
      return value[key].trim();
    }
  }
  for (const nested of ['data', 'result', 'payload']) {
    const found = findFirstText(value[nested], keys);
    if (found) return found;
  }
  return null;
}

function parseSnapshot(object) {
  if (!isRecord(object)) {
    throw new Error('响应中没有 subscription，也不是可识别的代理用量格式。');
  }

  if (isRecord(object.subscription)) {
    return parseSubscriptionSnapshot(object.subscription);
  }

  if (object.daily_usage != null || object.usage != null) {
    return parseProxyUsageSnapshot(object);
  }

  throw new Error('响应中没有 subscription，也不是可识别的代理用量格式。');
}

function parseSubscriptionSnapshot(subscription) {
  const dailyLimit = requireNumber(subscription, 'daily_limit_usd');
  const weeklyLimit = requireNumber(subscription, 'weekly_limit_usd');
  const monthlyLimit = requireNumber(subscription, 'monthly_limit_usd');
  if (dailyLimit <= 0 || weeklyLimit <= 0 || monthlyLimit <= 0) {
    throw new Error('subscription 中存在 limit 为 0 或负数，无法计算进度。');
  }

  return {
    dailyUsage: requireNumber(subscription, 'daily_usage_usd'),
    dailyLimit,
    weeklyUsage: requireNumber(subscription, 'weekly_usage_usd'),
    weeklyLimit,
    monthlyUsage: requireNumber(subscription, 'monthly_usage_usd'),
    monthlyLimit,
    expiresAt: requireText(subscription, 'expires_at'),
    remaining: null,
    schemaLabel: 'Subscription',
    note: null,
  };
}

function parseProxyUsageSnapshot(payload) {
  const usage = isRecord(payload.usage) ? payload.usage : {};
  const today = isRecord(usage.today) ? usage.today : null;
  const total = isRecord(usage.total) ? usage.total : null;
  const rows = Array.isArray(payload.daily_usage) ? payload.daily_usage.filter(isRecord) : [];
  const dailyUsage = optionalCost(today) ?? currentDayCost(rows);
  const weeklyUsage = periodCost(rows, 'week');
  const monthlyUsage = periodCost(rows, 'month');
  const totalUsage = optionalCost(total) ?? rows.reduce((sum, row) => sum + cost(row), 0);
  const remaining = optionalNumber(payload, 'remaining') ?? optionalNumber(payload, 'balance') ?? 0;
  const budget = Math.max(remaining + Math.max(monthlyUsage, totalUsage), monthlyUsage, weeklyUsage, dailyUsage, 1);
  const planName = typeof payload.planName === 'string' ? payload.planName.trim() : '';
  const noteParts = [
    '代理用量格式',
    planName ? `套餐: ${planName}` : null,
    `Remaining: ${formatAmount(remaining)} USD`,
  ].filter(Boolean);

  return {
    dailyUsage,
    dailyLimit: budget,
    weeklyUsage,
    weeklyLimit: budget,
    monthlyUsage,
    monthlyLimit: budget,
    expiresAt: '-',
    remaining,
    schemaLabel: '代理用量格式',
    note: noteParts.join(' · '),
  };
}

function requireNumber(payload, field) {
  const value = optionalNumber(payload, field);
  if (value == null) throw new Error(`subscription.${field} 缺失或不是数字。`);
  return value;
}

function optionalNumber(payload, field) {
  if (!isRecord(payload)) return null;
  const value = payload[field];
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function requireText(payload, field) {
  const value = isRecord(payload) && typeof payload[field] === 'string' ? payload[field].trim() : '';
  if (!value) throw new Error(`subscription.${field} 缺失或不是有效字符串。`);
  return value;
}

function optionalCost(payload) {
  return optionalNumber(payload, 'actual_cost') ?? optionalNumber(payload, 'cost');
}

function cost(payload) {
  return optionalCost(payload) ?? 0;
}

function currentDayCost(rows) {
  const now = new Date();
  return rows.reduce((sum, row) => {
    const date = dateFromRow(row);
    return date && sameDay(date, now) ? sum + cost(row) : sum;
  }, 0);
}

function periodCost(rows, period) {
  const now = new Date();
  return rows.reduce((sum, row) => {
    const date = dateFromRow(row);
    if (!date) return sum;
    if (period === 'month') {
      return date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth()
        ? sum + cost(row)
        : sum;
    }
    return sameWeek(date, now) ? sum + cost(row) : sum;
  }, 0);
}

function dateFromRow(row) {
  if (!isRecord(row) || typeof row.date !== 'string') return null;
  const match = row.date.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
}

function sameDay(left, right) {
  return left.getFullYear() === right.getFullYear()
    && left.getMonth() === right.getMonth()
    && left.getDate() === right.getDate();
}

function sameWeek(left, right) {
  const leftStart = startOfWeek(left);
  const rightStart = startOfWeek(right);
  return sameDay(leftStart, rightStart);
}

function startOfWeek(date) {
  const copy = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const mondayOffset = (copy.getDay() + 6) % 7;
  copy.setDate(copy.getDate() - mondayOffset);
  return copy;
}

function publicSettingsURL(baseURL) {
  const url = new URL(normalizeBaseURL(baseURL));
  url.pathname = '/api/v1/settings/public';
  url.search = '';
  url.hash = '';
  return url.toString();
}

function parseEndpointCandidates(object) {
  const customEndpoints = findCustomEndpoints(object);
  if (customEndpoints == null) {
    throw new Error('公共设置中没有可识别的 custom_endpoints 节点。');
  }

  const candidates = dedupeCandidates(endpointCandidates(customEndpoints, null));
  if (candidates.length === 0) {
    throw new Error('公共设置中没有可识别的 custom_endpoints 节点。');
  }
  return candidates;
}

function findCustomEndpoints(object) {
  if (Array.isArray(object)) {
    for (const item of object) {
      const found = findCustomEndpoints(item);
      if (found != null) return found;
    }
    return null;
  }

  if (!isRecord(object)) return null;
  if (object.custom_endpoints != null) return object.custom_endpoints;
  if (object.customEndpoints != null) return object.customEndpoints;

  for (const key of Object.keys(object).sort()) {
    const found = findCustomEndpoints(object[key]);
    if (found != null) return found;
  }
  return null;
}

function endpointCandidates(value, fallbackName) {
  if (Array.isArray(value)) {
    return value.flatMap((item, index) => endpointCandidates(item, fallbackName || `节点 ${index + 1}`));
  }

  if (isRecord(value)) {
    const endpoint = firstText(value, endpointValueKeys);
    if (endpoint) {
      const name = firstText(value, endpointNameKeys) || fallbackName || endpoint;
      const candidate = makeEndpointCandidate(name, endpoint);
      return candidate ? [candidate] : [];
    }

    return Object.keys(value).sort().flatMap((key) => {
      return endpointCandidates(value[key], displayNameFromKey(key));
    });
  }

  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return [];
    if ((trimmed.startsWith('{') || trimmed.startsWith('['))) {
      try {
        return endpointCandidates(JSON.parse(trimmed), fallbackName);
      } catch (_error) {
        // Fall through and treat the string as an endpoint.
      }
    }
    const candidate = makeEndpointCandidate(fallbackName || trimmed, trimmed);
    return candidate ? [candidate] : [];
  }

  return [];
}

const endpointNameKeys = [
  'name',
  'label',
  'title',
  'display_name',
  'displayName',
  'region',
];

const endpointValueKeys = [
  'url',
  'base_url',
  'baseURL',
  'endpoint',
  'api_base',
  'apiBase',
  'value',
  'host',
  'domain',
];

function firstText(payload, keys) {
  for (const key of keys) {
    if (typeof payload[key] === 'string' && payload[key].trim()) {
      return payload[key].trim();
    }
  }
  return null;
}

function makeEndpointCandidate(name, endpoint) {
  const trimmedEndpoint = String(endpoint || '').trim();
  const host = hostFromEndpoint(trimmedEndpoint);
  if (!host) return null;
  return {
    name: String(name || host).trim() || host,
    endpoint: trimmedEndpoint,
    host,
  };
}

function normalizeCachedCandidates(candidates) {
  if (!Array.isArray(candidates)) return [];

  return dedupeCandidates(candidates.map((candidate) => {
    if (typeof candidate === 'string') {
      return makeEndpointCandidate(candidate, candidate);
    }
    if (!isRecord(candidate)) return null;
    const endpoint = candidate.endpoint || candidate.url || candidate.host || candidate.domain;
    const name = candidate.name || candidate.label || candidate.title || endpoint;
    return makeEndpointCandidate(name, endpoint);
  }).filter(Boolean));
}

function hostFromEndpoint(endpoint) {
  let normalized = String(endpoint || '').trim();
  if (!normalized) return null;

  if (normalized.startsWith('//')) {
    normalized = `https:${normalized}`;
  } else if (!normalized.includes('://')) {
    normalized = `https://${normalized}`;
  }

  try {
    const url = new URL(normalized);
    if (url.hostname.trim()) return url.hostname.trim();
  } catch (_error) {
    const withoutScheme = String(endpoint).replace(/^https?:\/\//i, '');
    const hostPart = withoutScheme.split('/')[0].split(':')[0].trim();
    return hostPart || null;
  }

  return null;
}

function displayNameFromKey(key) {
  return String(key || '').replace(/_/g, ' ').trim();
}

function dedupeCandidates(candidates) {
  const result = [];
  const seen = new Set();

  for (const candidate of candidates) {
    if (!candidate || !candidate.host) continue;
    const key = candidate.host.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(candidate);
  }

  return result;
}

async function probeEndpoints(candidates, isFromCache, fallbackReason, cacheCandidates) {
  const limitedCandidates = dedupeCandidates(candidates).slice(0, 4);
  if (limitedCandidates.length === 0) {
    throw new Error('没有可探测的 custom_endpoints 节点。');
  }

  const results = await Promise.all(limitedCandidates.map((candidate) => runRouteProbe(candidate)));
  return createRecommendation(results, isFromCache, fallbackReason, cacheCandidates || limitedCandidates);
}

function runRouteProbe(candidate) {
  if (process.platform === 'darwin') {
    return runUnixTraceroute(candidate);
  }
  if (process.platform === 'win32') {
    return runWindowsTracert(candidate);
  }
  return Promise.resolve(probeError(candidate, '当前平台暂不支持路由探测'));
}

function runUnixTraceroute(candidate) {
  const traceroutePath = findMacTraceroutePath();
  if (!traceroutePath) {
    return Promise.resolve(probeError(candidate, '未找到 traceroute'));
  }

  return runProbeCommand(
    traceroutePath,
    ['-n', '-q', '1', '-m', '16', '-w', '1', candidate.host],
    MAC_TRACEROUTE_TIMEOUT_MS,
    candidate,
    parseUnixTracerouteOutput,
  ).then((outcome) => outcome.result);
}

async function runWindowsTracert(candidate) {
  const executables = windowsTracertExecutables();
  let lastError = null;

  for (const executable of executables) {
    const outcome = await runProbeCommand(
      executable,
      ['-d', '-h', '16', '-w', '600', candidate.host],
      WINDOWS_TRACERT_TIMEOUT_MS,
      candidate,
      parseWindowsTracertOutput,
    );

    if (outcome.error) {
      lastError = outcome.error;
      if (outcome.error.code === 'ENOENT') {
        continue;
      }
      return probeError(candidate, outcome.error.message);
    }

    return outcome.result;
  }

  return probeError(candidate, lastError?.code === 'ENOENT' ? '未找到 tracert' : (lastError?.message || '未找到 tracert'));
}

function runProbeCommand(executable, args, timeoutMs, candidate, parser) {
  return new Promise((resolve) => {
    let output = '';
    let timedOut = false;
    let settled = false;
    const child = spawn(executable, args, {
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    const finish = (payload) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(payload);
    };

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
    }, timeoutMs);

    child.stdout.on('data', (chunk) => {
      output += chunk.toString('utf8');
    });
    child.stderr.on('data', (chunk) => {
      output += chunk.toString('utf8');
    });
    child.on('error', (error) => {
      finish({ error });
    });
    child.on('close', (code) => {
      finish({ result: parser(output, candidate, timedOut, code ?? (timedOut ? 1 : 0)) });
    });
  });
}

function findMacTraceroutePath() {
  return ['/usr/sbin/traceroute', '/sbin/traceroute', '/usr/bin/traceroute']
    .find((candidate) => {
      try {
        fs.accessSync(candidate, fs.constants.X_OK);
        return true;
      } catch (_error) {
        return false;
      }
    }) || null;
}

function windowsTracertExecutables() {
  const executables = ['tracert'];
  const systemRoot = process.env.SystemRoot || process.env.WINDIR || 'C:\\Windows';
  const fallback = path.join(systemRoot, 'System32', 'tracert.exe');
  if (!executables.includes(fallback)) {
    executables.push(fallback);
  }
  return executables;
}

function parseUnixTracerouteOutput(output, candidate, timedOut, terminationStatus) {
  let hopCount = 0;
  let timeoutHops = 0;
  const latencies = [];
  const hops = [];

  for (const line of String(output || '').split(/\r?\n/)) {
    const trimmed = line.trim();
    const firstToken = trimmed.split(/\s+/)[0];
    const hopNumber = Number.parseInt(firstToken, 10);
    if (!Number.isFinite(hopNumber)) continue;
    const lineLatencies = latencyValues(trimmed);
    hopCount = Math.max(hopCount, hopNumber);
    if (trimmed.includes('*')) timeoutHops += 1;
    latencies.push(...lineLatencies);
    const sampleLatenciesMs = lineLatencies.slice();
    hops.push({
      index: hopNumber,
      text: formatHopLine(trimmed, hopNumber),
      address: hopAddress(trimmed, hopNumber),
      latencyMs: sampleLatenciesMs.length ? sampleLatenciesMs[sampleLatenciesMs.length - 1] : null,
      sampleLatenciesMs,
      expectedProbeCount: 1,
      timedOut: sampleLatenciesMs.length === 0,
    });
  }

  const averageLatencyMs = latencies.length
    ? latencies.reduce((sum, latency) => sum + latency, 0) / latencies.length
    : null;
  const lastLatencyMs = latencies.length ? latencies[latencies.length - 1] : null;
  const errorMessage = latencies.length === 0 && terminationStatus !== 0
    ? firstUsefulLine(output) || 'traceroute 未返回可用数据'
    : null;

  return decorateProbeResult({
    candidate,
    hopCount,
    timeoutHops,
    lastLatencyMs,
    averageLatencyMs,
    timedOut,
    errorMessage,
    hops,
  });
}

function parseWindowsTracertOutput(output, candidate, timedOut, terminationStatus) {
  let hopCount = 0;
  let timeoutHops = 0;
  const latencies = [];
  const hops = [];

  for (const line of String(output || '').split(/\r?\n/)) {
    const hopMatch = line.match(/^\s*(\d+)\s+(.*)$/);
    if (!hopMatch) continue;

    const hopNumber = Number.parseInt(hopMatch[1], 10);
    if (!Number.isFinite(hopNumber)) continue;

    const parsedHop = parseWindowsTracertHop(hopMatch[2], hopNumber);
    if (!parsedHop) continue;

    hopCount = Math.max(hopCount, hopNumber);
    if (parsedHop.sampleLatenciesMs.length < parsedHop.expectedProbeCount) {
      timeoutHops += 1;
    }
    latencies.push(...parsedHop.sampleLatenciesMs);
    hops.push(parsedHop);
  }

  const averageLatencyMs = latencies.length
    ? latencies.reduce((sum, latency) => sum + latency, 0) / latencies.length
    : null;
  const lastLatencyMs = latencies.length ? latencies[latencies.length - 1] : null;
  const errorMessage = latencies.length === 0
    ? firstUsefulProbeLine(output) || (terminationStatus !== 0 ? 'tracert 未返回可用数据' : '路由探测未返回可用数据')
    : null;

  return decorateProbeResult({
    candidate,
    hopCount,
    timeoutHops,
    lastLatencyMs,
    averageLatencyMs,
    timedOut,
    errorMessage,
    hops,
  });
}

function parseWindowsTracertHop(rest, hopNumber) {
  const tokens = String(rest || '').trim().split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return null;

  const parsedSamples = [];
  let index = 0;

  for (let probeIndex = 0; probeIndex < 3; probeIndex += 1) {
    const parsedSample = parseWindowsLatencyToken(tokens, index);
    if (!parsedSample) {
      return null;
    }
    parsedSamples.push(parsedSample.latencyMs);
    index = parsedSample.nextIndex;
  }

  const addressText = tokens.slice(index).join(' ').trim();
  const sampleLatenciesMs = parsedSamples.filter((value) => typeof value === 'number');
  const address = normalizeWindowsHopAddress(addressText);
  const timedOut = sampleLatenciesMs.length === 0;

  return {
    index: hopNumber,
    text: addressText || 'Request timed out.',
    address,
    latencyMs: sampleLatenciesMs.length ? sampleLatenciesMs[sampleLatenciesMs.length - 1] : null,
    sampleLatenciesMs,
    expectedProbeCount: parsedSamples.length,
    timedOut,
  };
}

function parseWindowsLatencyToken(tokens, startIndex) {
  const token = tokens[startIndex];
  if (!token) return null;

  if (token === '*') {
    return { latencyMs: null, nextIndex: startIndex + 1 };
  }

  if (/^<?\d+$/i.test(token) && /^ms$/i.test(tokens[startIndex + 1] || '')) {
    return {
      latencyMs: Number(token.replace('<', '')),
      nextIndex: startIndex + 2,
    };
  }

  const inlineMatch = token.match(/^<?(\d+)ms$/i);
  if (inlineMatch) {
    return {
      latencyMs: Number(inlineMatch[1]),
      nextIndex: startIndex + 1,
    };
  }

  return null;
}

function normalizeWindowsHopAddress(text) {
  const value = String(text || '').trim();
  if (!value || /^request timed out\.?$/i.test(value)) {
    return '*';
  }
  const bracketMatch = value.match(/\[([^\]]+)\]\s*$/);
  if (bracketMatch) {
    return bracketMatch[1];
  }
  const parts = value.split(/\s+/);
  return parts[parts.length - 1] || '*';
}

function latencyValues(text) {
  const values = [];
  const regex = /([0-9]+(?:\.[0-9]+)?)\s*ms/gi;
  let match;
  while ((match = regex.exec(text)) != null) {
    values.push(Number(match[1]));
  }
  return values;
}

function firstUsefulLine(output) {
  return String(output || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean) || null;
}

function firstUsefulProbeLine(output) {
  return String(output || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find((line) => /^\d+\s+/.test(line) || /request timed out/i.test(line)) || null;
}

function probeError(candidate, message) {
  return decorateProbeResult({
    candidate,
    hopCount: 0,
    timeoutHops: 0,
    lastLatencyMs: null,
    averageLatencyMs: null,
    timedOut: false,
    errorMessage: message,
    hops: [{
      index: '-',
      text: message,
      address: '*',
      latencyMs: null,
      sampleLatenciesMs: [],
      expectedProbeCount: 1,
      timedOut: false,
    }],
  });
}

function formatHopLine(line, hopNumber) {
  return line.replace(new RegExp(`^\\s*${hopNumber}\\s+`), '').trim() || '*';
}

function hopAddress(line, hopNumber) {
  const rest = formatHopLine(line, hopNumber);
  if (!rest || rest.startsWith('*')) return '*';
  return rest.split(/\s+/)[0] || '*';
}

function decorateProbeResult(result) {
  const latency = result.lastLatencyMs ?? result.averageLatencyMs;
  const score = latency == null
    ? null
    : latency
      + result.hopCount * 2.5
      + result.timeoutHops * 35
      + (result.timedOut ? 160 : 0);

  return {
    ...result,
    score,
    summaryText: probeSummaryText({ ...result, score }),
  };
}

function probeSummaryText(result) {
  if (result.errorMessage && result.score == null) {
    return result.errorMessage;
  }

  const parts = [latencyText(result.lastLatencyMs ?? result.averageLatencyMs), `${result.hopCount} 跳`];
  if (result.timeoutHops > 0) parts.push(`${result.timeoutHops} 个超时跳`);
  if (result.timedOut) parts.push('已截断');
  return parts.join(' · ');
}

function latencyText(latency) {
  if (latency == null) return '无 RTT';
  return Math.round(latency) === latency ? `${latency} ms` : `${latency.toFixed(1)} ms`;
}

function createRecommendation(results, isFromCache, fallbackReason, cacheCandidates) {
  const recommended = results
    .map((result, index) => ({ result, index, score: result.score }))
    .filter((item) => item.score != null)
    .sort((left, right) => left.score === right.score ? left.index - right.index : left.score - right.score)[0]?.result || null;

  const rankedResults = results
    .map((result, index) => ({ result, index, score: result.score ?? Number.POSITIVE_INFINITY }))
    .sort((left, right) => left.score === right.score ? left.index - right.index : left.score - right.score)
    .map((item) => item.result);

  const sourceLabel = isFromCache ? 'CACHE' : 'NETWORK';
  const detailLines = recommendationDetailLines(rankedResults, recommended, isFromCache);

  return {
    results,
    isFromCache,
    fallbackReason,
    recommended,
    recommendedHost: recommended?.candidate?.host || null,
    sourceLabel,
    headline: recommended ? `推荐 ${candidateDisplayName(recommended.candidate)}` : '节点推荐 暂不可用',
    detailLines,
    traceGroups: traceGroups(rankedResults, recommended),
    candidates: dedupeCandidates(cacheCandidates || results.map((result) => result.candidate)),
  };
}

function traceGroups(results, recommended) {
  return results.map((result) => ({
    name: candidateDisplayName(result.candidate),
    host: result.candidate.host,
    isRecommended: Boolean(recommended && result.candidate.host === recommended.candidate.host),
    summaryText: result.summaryText,
    hops: Array.isArray(result.hops) && result.hops.length > 0
      ? result.hops
      : [{
        index: '-',
        text: result.errorMessage || '没有路由探测输出',
        address: '*',
        latencyMs: null,
        sampleLatenciesMs: [],
        expectedProbeCount: 1,
        timedOut: false,
      }],
  }));
}

function recommendationDetailLines(results, recommended, isFromCache) {
  if (!recommended) {
    const failed = results.map((result) => `${candidateDisplayName(result.candidate)}: ${result.summaryText}`);
    return failed.length ? failed : ['没有可探测的 custom_endpoints 节点。'];
  }

  const heading = isFromCache ? '缓存节点路由探测' : '全部节点路由探测';
  const lines = results.map((result) => {
    const marker = result.candidate.host === recommended.candidate.host ? '推荐 ' : '';
    return `${marker}${candidateDisplayName(result.candidate)}: ${result.summaryText}`;
  });
  return [heading, ...lines];
}

function candidateDisplayName(candidate) {
  const name = String(candidate?.name || '').trim();
  const host = String(candidate?.host || '').trim();
  return !name || name.toLowerCase() === host.toLowerCase() ? host : name;
}

function formatAmount(value) {
  const number = Number.isFinite(Number(value)) ? Number(value) : 0;
  if (Math.round(number) === number) return String(number);
  return number.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

module.exports = {
  checkQuotaResetRemaining,
  getMaskedAPIKey,
  loadEndpointRecommendation,
  loadUsageSnapshot,
  probeEndpointCandidates,
  resetQuota,
};
