// Cloudflare Pages direct-upload deployer.
//
// Why this exists: `npx wrangler pages deploy` needs a working npm install,
// and this machine's npm hits EPERM on its cache directory plus a flaky
// connection to the registry. The Pages direct-upload API needs only HTTPS
// and the API token, so it sidesteps npm entirely.
//
// Protocol (per Cloudflare's Pages direct-upload API):
//   1. POST /pages/projects/{project}/deployments  -> get upload JWTs + a
//      list of files that already exist (deduplicated by content hash).
//   2. POST each missing file to /pages/assets/upload with its hash.
//   3. POST /pages/projects/{project}/deployments/{id}/start to go live.
//
// Usage: node tools/deploy-pages.js
// Requires env: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const TOKEN = process.env.CLOUDFLARE_API_TOKEN;
const ACCOUNT = process.env.CLOUDFLARE_ACCOUNT_ID;
const PROJECT = process.env.PAGES_PROJECT || 'my-blog';
const ROOT = process.env.PAGES_DIR || 'public';
const BRANCH = process.env.PAGES_BRANCH || 'main';

if (!TOKEN || !ACCOUNT) {
  console.error('Missing CLOUDFLARE_API_TOKEN or CLOUDFLARE_ACCOUNT_ID');
  process.exit(1);
}

const API = 'https://api.cloudflare.com/client/v4';
const auth = { Authorization: `Bearer ${TOKEN}` };

// Pages uses a 32-hex-char hash: the first 16 bytes of the SHA-256 digest,
// base64 then re-encoded as hex. This is not a plain SHA-256 hex digest.
function hashFile(buf) {
  const digest = crypto.createHash('sha256').update(buf).digest();
  return digest.subarray(0, 16).toString('hex');
}

function walk(dir, base = dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full, base));
    else out.push({ full, rel: '/' + path.relative(base, full).split(path.sep).join('/') });
  }
  return out;
}

async function api(pathname, init = {}) {
  const res = await fetch(API + pathname, {
    ...init,
    headers: {
      ...auth,
      ...(init.body && typeof init.body === 'string' ? { 'Content-Type': 'application/json' } : {}),
      ...(init.headers || {}),
    },
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = { raw: text }; }
  if (!res.ok || json.success === false) {
    const detail = JSON.stringify(json.errors || json, null, 2);
    throw new Error(`${init.method || 'GET'} ${pathname} -> HTTP ${res.status}\n${detail}`);
  }
  return json.result;
}

(async () => {
  if (!fs.existsSync(ROOT)) throw new Error(`Build directory not found: ${ROOT}`);

  const local = walk(ROOT).map((f) => {
    const buf = fs.readFileSync(f.full);
    return { ...f, buf, hash: hashFile(buf), size: buf.length };
  });
  console.log(`Local files: ${local.length}`);

  // Step 1: open the deployment and learn which hashes already exist.
  const dep = await api(`/accounts/${ACCOUNT}/pages/projects/${PROJECT}/deployments`, {
    method: 'POST',
    body: JSON.stringify({ branch: BRANCH }),
  });
  const jwt = dep.jwt;
  const already = new Set((dep.missing_hashes ? [] : []).concat());
  // The response lists the hashes it still needs in `missing_hashes` when
  // present; otherwise assume nothing is cached and upload everything.
  const needed = Array.isArray(dep.missing_hashes) ? new Set(dep.missing_hashes) : null;
  console.log(`Deployment id: ${dep.id}`);

  const toUpload = needed ? local.filter((f) => needed.has(f.hash)) : local;
  console.log(`Uploading ${toUpload.length} of ${local.length} file(s)`);

  // Step 2: upload missing blobs in one multipart request.
  if (toUpload.length) {
    const form = new FormData();
    for (const f of toUpload) {
      form.append(f.hash, new Blob([f.buf]), path.basename(f.rel));
    }
    const up = await fetch(`${API}/pages/assets/upload`, {
      method: 'POST',
      headers: { ...auth, Authorization: `Bearer ${jwt}` },
      body: form,
    });
    const upText = await up.text();
    if (!up.ok) throw new Error(`Upload failed: HTTP ${up.status}\n${upText}`);
    console.log('Upload OK');
  }

  // Step 3: register the manifest and start serving it.
  const manifest = Object.fromEntries(local.map((f) => [f.rel, f.hash]));
  await fetch(`${API}/pages/assets/upsert_hashes`, {
    method: 'POST',
    headers: { ...auth, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: JSON.stringify([...new Set(local.map((f) => f.hash))]),
  });

  await api(`/accounts/${ACCOUNT}/pages/projects/${PROJECT}/deployments/${dep.id}`, {
    method: 'PATCH',
    body: JSON.stringify({ manifest }),
  });

  const started = await api(`/accounts/${ACCOUNT}/pages/projects/${PROJECT}/deployments/${dep.id}/start`, {
    method: 'POST',
  });

  console.log('\nDeployed.');
  console.log('URL      :', started.url);
  console.log('Alias    :', started.aliases ? started.aliases.join(', ') : '(none)');
  console.log('Stage    :', started.environment);
})().catch((err) => {
  console.error('\nDEPLOY FAILED\n' + err.message);
  process.exit(1);
});
