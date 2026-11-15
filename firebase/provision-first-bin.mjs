import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { join } from 'node:path';

const project = 'grainguard-8248c';
const owner = process.argv[2];
if (!owner) throw new Error('Usage: node firebase/provision-first-bin.mjs <Firebase CLI account email>');
const database = 'https://grainguard-8248c-default-rtdb.firebaseio.com';
const device = 'GG001';
const lot = 'WHEAT-001';
const identity = 'https://identitytoolkit.googleapis.com';
const require = createRequire(import.meta.url);
const auth = require(join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));
const account = auth.getAllAccounts().find((entry) => entry.user.email === owner);
if (!account) throw new Error('Authorize the requested Firebase CLI account first.');
const { access_token: accessToken } = await auth.getAccessToken(
  account.tokens.refresh_token, [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/firebase',
    'https://www.googleapis.com/auth/userinfo.email',
  ],
);

async function request(url, method, body, token = accessToken) {
  const response = await fetch(url, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      'Content-Type': 'application/json',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  const result = await response.json();
  if (!response.ok) {
    const error = result?.error;
    throw new Error(error?.message ?? error ?? `HTTP ${response.status}`);
  }
  return result;
}

const endpoint = `${identity}/admin/v2/projects/${project}/config`;
const config = await request(endpoint, 'GET');
if (!config.signIn?.email?.enabled || !config.signIn?.email?.passwordRequired) {
  throw new Error('Enable Email/Password sign-in in Firebase Console first.');
}

const credentialsPath = new URL('../app/config/first-bin-credentials.json', import.meta.url);
await mkdir(new URL('.', credentialsPath), { recursive: true });
const makeAccount = (email) => ({ email, password: randomBytes(24).toString('base64url') });
try {
  await writeFile(credentialsPath, JSON.stringify({
    operator: makeAccount(owner),
    publisher: makeAccount('gg001@devices.grainguard.invalid'),
  }, null, 2), { flag: 'wx', mode: 0o600 });
} catch (error) {
  if (error.code !== 'EEXIST') throw error;
}
const credentials = JSON.parse(await readFile(credentialsPath, 'utf8'));
const options = JSON.parse((await readFile(new URL('../app/config/staging.json', import.meta.url), 'utf8')).replace(/^\uFEFF/, ''));
const signIn = (details) => request(
  `${identity}/v1/accounts:signInWithPassword?key=${encodeURIComponent(options.GG_STAGING_API_KEY)}`,
  'POST', { ...details, returnSecureToken: true }, null,
);

async function provision(details) {
  try {
    await request(`${identity}/v1/projects/${project}/accounts`, 'POST', details);
  } catch (error) {
    if (!error.message.includes('EMAIL_EXISTS')) throw error;
  }
  return signIn(details);
}

const operator = await provision(credentials.operator);
const publisher = await provision(credentials.publisher);
const existingMeta = await request(`${database}/devices/${device}/meta.json`, 'GET');
if (existingMeta && (existingMeta.activeLotId !== lot || existingMeta.grainType !== 'wheat')) {
  throw new Error('GG001 already has a different active lot or grain type.');
}
const writer = await request(`${database}/deviceWriters/${device}.json`, 'GET');
if (writer && writer !== publisher.localId) throw new Error('GG001 already has a different publisher.');
await request(`${database}/.json`, 'PATCH', {
  [`memberships/${operator.localId}/${device}`]: { label: 'East Silo', grainType: 'wheat' },
  [`deviceWriters/${device}`]: publisher.localId,
  ...(!existingMeta ? {
    [`devices/${device}/meta`]: {
      label: 'East Silo', activeLotId: lot, grainType: 'wheat',
      expectedCadenceSec: 5, offlineTimeoutSec: 20,
    },
  } : {}),
});
const memberUrl = new URL(`${database}/memberships/${operator.localId}/${device}.json`);
memberUrl.searchParams.set('auth', operator.idToken);
const membership = await request(memberUrl, 'GET', undefined, null);
if (membership?.grainType !== 'wheat') throw new Error('Could not verify operator access to GG001.');
console.log('Provisioned GG001. Credentials are saved locally in app/config/first-bin-credentials.json.');
