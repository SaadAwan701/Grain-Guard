import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { endAt, get, limitToLast, orderByChild, query, ref, serverTimestamp, set, startAt, update } from 'firebase/database';
import { readFile } from 'node:fs/promises';

let environment;
const projectId = 'demo-grainguard';
const device = 'GG001';
const lot = 'WHEAT-001';
const latest = `devices/${device}/latest`;
const history = `devices/${device}/lots/${lot}/samples`;
const db = uid => (uid ? environment.authenticatedContext(uid) : environment.unauthenticatedContext()).database();
const sample = (sampleId, measuredAtMs = Date.now()) => ({
  schemaVersion: 1, deviceId: device, lotId: lot, sampleId, measuredAtMs,
  receivedAtMs: serverTimestamp(), sensors: { co2Ppm: 0 }, battery: { percent: 0 },
});
const publish = (database, data) => update(ref(database), {
  [latest]: data, [`${history}/${data.sampleId}`]: data,
});

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    database: { rules: await readFile(new URL('./database.rules.json', import.meta.url), 'utf8') },
  });
});
after(async () => environment?.cleanup());
beforeEach(async () => {
  await environment.clearDatabase();
  await environment.withSecurityRulesDisabled(async context => {
    await update(ref(context.database()), {
      'memberships/viewer/GG001': { label: 'East Silo' },
      'deviceWriters/GG001': 'publisher',
      'devices/GG001/meta': { activeLotId: lot },
      'devices/GG002/meta': { activeLotId: lot },
    });
  });
});

test('viewer has scoped live access and bounded history only', async () => {
  await assertSucceeds(publish(db('publisher'), sample('first')));
  const viewer = db('viewer');
  await assertFails(get(ref(db(), latest)));
  await assertFails(get(ref(viewer)));
  await assertFails(get(ref(viewer, 'devices/GG001')));
  await assertFails(get(ref(viewer, 'devices/GG002/meta')));
  await assertFails(get(ref(viewer, 'deviceWriters/GG001')));
  await assertSucceeds(get(ref(viewer, 'memberships/viewer')));
  await assertSucceeds(get(ref(viewer, 'devices/GG001/meta')));
  assert.equal((await get(ref(viewer, latest))).child('battery/percent').val(), 0);
  await assertFails(get(ref(viewer, history)));
  const readings = await assertSucceeds(get(query(ref(viewer, history),
    orderByChild('measuredAtMs'), startAt(Date.now() - 60000), endAt(Date.now()), limitToLast(144))));
  assert.equal(readings.size, 1);
});

test('publishing is scoped, append-only, and monotonic', async () => {
  const publisher = db('publisher');
  const time = Date.now();
  await assertFails(publish(db('viewer'), sample('unauthorized', time)));
  await assertFails(set(ref(publisher, latest), sample('latest-only', time)));
  await assertFails(set(ref(publisher, 'devices/GG002/latest'), sample('wrong-bin', time)));
  await assertFails(publish(publisher, { ...sample('bad', time), battery: { percent: 101 } }));
  await assertFails(publish(publisher, { ...sample('bad-shape', time), battery: { unknown: 1 } }));
  await assertSucceeds(publish(publisher, sample('first', time)));
  await assertFails(publish(publisher, sample('first', time)));
  await assertFails(publish(publisher, sample('old', time - 1000)));
  await assertSucceeds(set(ref(publisher, `${history}/old`), sample('old', time - 1000)));
  await assertFails(set(ref(publisher, `${history}/old`), null));
  await assertFails(set(ref(db('viewer'), 'memberships/viewer/GG002'), true));
});

test('acknowledgments belong to the assigned signed-in viewer', async () => {
  const path = 'userState/viewer/devices/GG001/alertAcks/episode_1';
  const ack = { acknowledgedAtMs: serverTimestamp() };
  await assertFails(set(ref(db('publisher'), path), ack));
  await assertFails(set(ref(db('viewer'), path.replace('GG001', 'GG002')), ack));
  await assertFails(set(ref(db('viewer'), path), { ...ack, extra: true }));
  await assertSucceeds(set(ref(db('viewer'), path), ack));
  await assertSucceeds(get(ref(db('viewer'), path)));
  await assertFails(get(ref(db('publisher'), path)));
});
