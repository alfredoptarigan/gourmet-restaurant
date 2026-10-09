import assert from 'node:assert/strict';
import { test } from 'node:test';
import { hashPassword, verifyPassword } from '../src/auth.ts';
import { parseCatalog } from '../src/catalog.ts';
import { loadConfig } from '../src/config.ts';
import { LEVELS, levelFor, rewardBetween } from '../src/levels.ts';
import { createRateLimiter } from '../src/rate-limit.ts';

test('a hashed password verifies only against the same password', async () => {
  const stored = await hashPassword('correct horse battery');

  assert.equal(await verifyPassword('correct horse battery', stored), true);
  assert.equal(await verifyPassword('wrong horse battery', stored), false);
});

test('hashing the same password twice gives different hashes', async () => {
  assert.notEqual(await hashPassword('correct horse battery'), await hashPassword('correct horse battery'));
});

test('a malformed stored hash never verifies', async () => {
  for (const stored of ['', 'plain-text', 'scrypt$$', 'scrypt$c2FsdA==$', 'bcrypt$c2FsdA==$a2V5']) {
    assert.equal(await verifyPassword('', stored), false, `stored hash ${JSON.stringify(stored)}`);
  }
});

test('the rate limiter allows the limit, then blocks until the window ends', () => {
  let now = 0;
  const isAllowed = createRateLimiter(2, 1000, () => now);

  assert.deepEqual([isAllowed('a'), isAllowed('a'), isAllowed('a')], [true, true, false]);
  assert.equal(isAllowed('b'), true, 'other clients are counted separately');

  now = 1000;
  assert.equal(isAllowed('a'), true);
});

test('the rate limiter forgets clients whose window has ended', () => {
  let now = 0;
  const isAllowed = createRateLimiter(1, 1000, () => now, 2);
  isAllowed('a');
  isAllowed('b');

  now = 1000;
  isAllowed('c');

  assert.equal(isAllowed('a'), true);
});

test('config reads the database url and defaults the port', () => {
  assert.deepEqual(loadConfig({ DATABASE_URL: 'postgres://localhost/gourmet_street' }), {
    databaseUrl: 'postgres://localhost/gourmet_street',
    port: 3000,
    itemCatalogPath: '../data/restaurant.json',
  });
  assert.equal(loadConfig({ DATABASE_URL: 'postgres://localhost/x', PORT: '8080' }).port, 8080);
});

test('config names the missing or invalid variable', () => {
  assert.throws(() => loadConfig({}), /DATABASE_URL/);
  assert.throws(() => loadConfig({ DATABASE_URL: 'postgres://localhost/x', PORT: 'abc' }), /PORT/);
});

test('the level table starts at zero points and only climbs', () => {
  assert.equal(LEVELS.length, 66);
  assert.equal(LEVELS[0].points, 0);
  for (let index = 1; index < LEVELS.length; index += 1) {
    assert.ok(LEVELS[index].points > LEVELS[index - 1].points, `level ${index + 1}`);
  }
});

test('a level is the last threshold the points have reached', () => {
  assert.equal(levelFor(0), 1);
  assert.equal(levelFor(49), 1);
  assert.equal(levelFor(50), 2);
  assert.equal(levelFor(99), 3);
  assert.equal(levelFor(100), 4);
  assert.equal(levelFor(999_999_999), 66);
});

test('the reward between two levels is the sum of every level entered', () => {
  assert.equal(rewardBetween(1, 1), 0);
  assert.equal(rewardBetween(1, 2), 3500);
  assert.equal(rewardBetween(1, 4), 7000);
  assert.equal(rewardBetween(3, 4), 1000);
});

test('the catalog keeps prices for every item and marks what coins can buy', () => {
  const catalog = parseCatalog([
    { name: 'Chair', items: [{ id: '10', cost: '200', cash: '0' }, { id: '11', cost: '90', cash: '3' }] },
    { name: 'Award', items: [{ id: '12', cost: '0', cash: '0' }, { id: '13', cost: '50', cash: '0', invisible: true }] },
  ]);

  assert.deepEqual(catalog.get(10), { cost: 200, purchasable: true, unlockLevel: 0, consumable: false });
  assert.deepEqual(catalog.get(11), { cost: 90, purchasable: false, unlockLevel: 0, consumable: false });
  assert.deepEqual(catalog.get(12), { cost: 0, purchasable: false, unlockLevel: 0, consumable: false });
  assert.deepEqual(catalog.get(13), { cost: 50, purchasable: false, unlockLevel: 0, consumable: false });
  assert.equal(catalog.get(14), undefined);
});

test('a catalog that is not a list of groups is rejected', () => {
  assert.throws(() => parseCatalog({ name: 'Chair' }), /catalog/i);
  assert.throws(() => parseCatalog([{ name: 'Chair', items: [{ id: 'abc', cost: '1' }] }]), /catalog/i);
});
