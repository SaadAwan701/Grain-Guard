import { deleteApp, initializeApp } from 'firebase/app';
import { connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signInWithEmailAndPassword } from 'firebase/auth';

const projectId = 'demo-grainguard';
const host = '127.0.0.1';
const namespace = `${projectId}-default-rtdb`;
const settings = { projectId, apiKey: 'fake-api-key', databaseURL: `https://${namespace}.firebaseio.com` };
const password = 'GrainGuardLocal2026';
const device = 'GG001';
const lot = 'WHEAT-001';
const app = initializeApp(settings, 'fixture');
const auth = getAuth(app);
connectAuthEmulator(auth, `http://${host}:9099`, { disableWarnings: true });

async function databaseRequest(path, { method = 'GET', token, body, admin = false } = {}) {
  const url = new URL(`http://${host}:9000/${path}.json`);
  url.searchParams.set('ns', namespace);
  if (token) url.searchParams.set('auth', token);
  const response = await fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(admin ? { Authorization: 'Bearer owner' } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`Emulator database ${method} failed (${response.status})`);
  return response.json();
}

async function account(email) {
  try {
    return (await createUserWithEmailAndPassword(auth, email, password)).user.uid;
  } catch (error) {
    if (error.code !== 'auth/email-already-in-use') throw error;
    return (await signInWithEmailAndPassword(auth, email, password)).user.uid;
  }
}

try {
  if (process.argv[2] === 'seed') {
    const viewer = await account('viewer@example.test');
    const publisher = await account('publisher@example.test');
    await databaseRequest('', {
      method: 'PATCH',
      admin: true,
      body: {
        [`memberships/${viewer}/${device}`]: { label: 'East Silo', grainType: 'wheat' },
        [`deviceWriters/${device}`]: publisher,
        [`devices/${device}/meta`]: {
          label: 'East Silo', activeLotId: lot, grainType: 'wheat', expectedCadenceSec: 600,
          firmwareVersion: 'Local fixture',
        },
      },
    });
    console.log('Emulator seeded. Sign in with viewer@example.test / GrainGuardLocal2026');
  } else if (['publish', 'backfill'].includes(process.argv[2])) {
    const { user } = await signInWithEmailAndPassword(auth, 'publisher@example.test', password);
    const token = await user.getIdToken();
    const measuredAtMs = Date.now() - (process.argv[2] === 'backfill' ? 3600000 : 0);
    const sampleId = process.argv[3] ?? `GG001-fixture-${measuredAtMs}`;
    if (!/^[A-Za-z0-9_-]{1,100}$/.test(sampleId)) throw new Error('Invalid sample ID');
    const history = `devices/${device}/lots/${lot}/samples/${sampleId}`;
    if (await databaseRequest(history, { token })) {
      console.log(`Already recorded: ${sampleId}`);
    } else {
      const sample = {
        schemaVersion: 1, deviceId: device, lotId: lot, sampleId, measuredAtMs,
        receivedAtMs: { '.sv': 'timestamp' },
        sensors: {
          temperatureC: 30.2, relativeHumidityPct: 75.4, co2Ppm: 1200,
          gasResistanceOhm: 45000, acousticEvents: 8, acousticWindowSec: 600,
        },
        battery: { percent: 67, voltageMv: 3820, chargeState: 'discharging' },
      };
      if (process.argv[2] === 'backfill') {
        await databaseRequest(history, { method: 'PUT', token, body: sample });
      } else {
        await databaseRequest('', {
          method: 'PATCH', token, body: { [history]: sample, [`devices/${device}/latest`]: sample },
        });
      }
      console.log(`Recorded: ${sampleId}`);
    }
  } else {
    throw new Error('Usage: node firebase/fixture.mjs seed|publish|backfill [sample-id]');
  }
} finally {
  await deleteApp(app);
}
