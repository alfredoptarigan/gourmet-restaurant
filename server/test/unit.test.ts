import assert from 'node:assert/strict';
import { test } from 'node:test';
import { hashPassword, verifyPassword } from '../src/auth.ts';
import { loadConfig } from '../src/config.ts';
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
  });
  assert.equal(loadConfig({ DATABASE_URL: 'postgres://localhost/x', PORT: '8080' }).port, 8080);
});

test('config names the missing or invalid variable', () => {
  assert.throws(() => loadConfig({}), /DATABASE_URL/);
  assert.throws(() => loadConfig({ DATABASE_URL: 'postgres://localhost/x', PORT: 'abc' }), /PORT/);
});
