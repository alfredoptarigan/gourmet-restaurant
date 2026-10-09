// Integration tests against a real PostgreSQL database. Run: npm test
import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { createApp } from '../src/app.ts';
import { connect, migrate } from '../src/db.ts';

const databaseUrl = process.env.TEST_DATABASE_URL ?? 'postgres://localhost/gourmet_street_test';
// These tests truncate every table, so refuse anything that is not clearly a test database.
assert.match(new URL(databaseUrl).pathname, /_test$/, 'TEST_DATABASE_URL must name a database ending in _test');

const PASSWORD = 'correct horse battery';
const NO_RATE_LIMIT = { limit: 1000, windowMs: 60_000 };

const sql = connect(databaseUrl);
const app = createApp({ sql, authRateLimit: NO_RATE_LIMIT });

type CallOptions = { body?: unknown; rawBody?: string; token?: string };
type ApiResponse = { status: number; body: { success: boolean; data: any; error: string | null } };

async function call(target: typeof app, method: string, path: string, options: CallOptions = {}): Promise<ApiResponse> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (options.token) {
    headers.Authorization = `Bearer ${options.token}`;
  }
  const body = options.rawBody ?? (options.body === undefined ? undefined : JSON.stringify(options.body));
  const response = await target.request(path, { method, headers, body });
  return { status: response.status, body: await response.json() };
}

async function register(username = 'chef_anna'): Promise<string> {
  const response = await call(app, 'POST', '/auth/register', { body: { username, password: PASSWORD } });
  assert.equal(response.status, 201);
  return response.body.data.token;
}

before(async () => {
  await migrate(sql);
});

beforeEach(async () => {
  await sql`truncate users restart identity cascade`;
});

after(async () => {
  await sql.end();
});

test('migrate applies nothing the second time', async () => {
  assert.deepEqual(await migrate(sql), []);
});

test('health reports ok when the database answers', async () => {
  const response = await call(app, 'GET', '/health');

  assert.equal(response.status, 200);
  assert.deepEqual(response.body, { success: true, data: { status: 'ok' }, error: null });
});

test('time returns the server clock in milliseconds', async () => {
  const before = Date.now();

  const response = await call(app, 'GET', '/time');

  assert.ok(response.body.data.now >= before && response.body.data.now <= Date.now());
});

test('unknown routes return a 404 envelope', async () => {
  const response = await call(app, 'GET', '/no-such-route');

  assert.equal(response.status, 404);
  assert.deepEqual(response.body, { success: false, data: null, error: 'Not found' });
});

test('register creates an account with an empty profile', async () => {
  const token = await register();

  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(profile.status, 200);
  assert.deepEqual(profile.body.data, { username: 'chef_anna', coins: 0, cash: 0, version: 0, data: {} });
});

test('register never stores the password or the session token in plain text', async () => {
  const token = await register();

  const [user] = await sql`select password_hash from users`;
  const [session] = await sql`select token_hash from sessions`;

  assert.ok(!user.password_hash.includes(PASSWORD));
  assert.notEqual(session.token_hash.toString('base64url'), token);
});

test('register rejects a username that differs only by case', async () => {
  await register('chef_anna');

  const response = await call(app, 'POST', '/auth/register', { body: { username: 'Chef_Anna', password: PASSWORD } });

  assert.equal(response.status, 409);
  assert.equal(response.body.error, 'Username is already taken');
});

test('register rejects invalid input and says which field is wrong', async () => {
  const shortPassword = await call(app, 'POST', '/auth/register', { body: { username: 'chef_anna', password: 'short' } });
  const badUsername = await call(app, 'POST', '/auth/register', { body: { username: 'a b', password: PASSWORD } });
  const notJson = await call(app, 'POST', '/auth/register', { rawBody: '{not json' });

  assert.equal(shortPassword.status, 400);
  assert.match(shortPassword.body.error ?? '', /^password:/);
  assert.equal(badUsername.status, 400);
  assert.match(badUsername.body.error ?? '', /^username:/);
  assert.equal(notJson.status, 400);
});

test('login returns a working token for the right password', async () => {
  await register();

  const login = await call(app, 'POST', '/auth/login', { body: { username: 'CHEF_ANNA', password: PASSWORD } });
  const profile = await call(app, 'GET', '/profile', { token: login.body.data.token });

  assert.equal(login.status, 200);
  assert.equal(profile.status, 200);
});

test('login gives the same answer for a wrong password and an unknown user', async () => {
  await register();

  const wrongPassword = await call(app, 'POST', '/auth/login', { body: { username: 'chef_anna', password: 'wrong password' } });
  const unknownUser = await call(app, 'POST', '/auth/login', { body: { username: 'nobody_here', password: PASSWORD } });

  assert.equal(wrongPassword.status, 401);
  assert.deepEqual(wrongPassword.body, unknownUser.body);
});

test('profile requires a valid session', async () => {
  const missing = await call(app, 'GET', '/profile');
  const unknown = await call(app, 'GET', '/profile', { token: 'not-a-real-token' });

  assert.equal(missing.status, 401);
  assert.equal(unknown.status, 401);
});

test('an expired session is rejected', async () => {
  const token = await register();
  await sql`update sessions set expires_at = now() - interval '1 second'`;

  const response = await call(app, 'GET', '/profile', { token });

  assert.equal(response.status, 401);
});

test('logout ends the session', async () => {
  const token = await register();

  const logout = await call(app, 'POST', '/auth/logout', { token });
  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(logout.status, 200);
  assert.equal(profile.status, 401);
});

test('saving the profile stores the data and bumps the version', async () => {
  const token = await register();
  const layout = { floor: 'wood', tables: [{ x: 1, y: 2 }] };

  const save = await call(app, 'PUT', '/profile', { token, body: { version: 0, data: layout } });
  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(save.status, 200);
  assert.deepEqual(save.body.data, { version: 1 });
  assert.deepEqual(profile.body.data.data, layout);
  assert.equal(profile.body.data.version, 1);
});

test('saving from a stale version is rejected and changes nothing', async () => {
  const token = await register();
  await call(app, 'PUT', '/profile', { token, body: { version: 0, data: { floor: 'wood' } } });

  const stale = await call(app, 'PUT', '/profile', { token, body: { version: 0, data: { floor: 'marble' } } });
  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(stale.status, 409);
  assert.deepEqual(profile.body.data.data, { floor: 'wood' });
});

test('a save cannot set coins or cash', async () => {
  const token = await register();

  const save = await call(app, 'PUT', '/profile', { token, body: { version: 0, data: {}, coins: 999999, cash: 999 } });
  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(save.status, 400);
  assert.equal(profile.body.data.coins, 0);
  assert.equal(profile.body.data.cash, 0);
});

test('a save only touches the signed-in player', async () => {
  const anna = await register('chef_anna');
  const budi = await register('chef_budi');

  await call(app, 'PUT', '/profile', { token: anna, body: { version: 0, data: { floor: 'wood' } } });
  const profile = await call(app, 'GET', '/profile', { token: budi });

  assert.deepEqual(profile.body.data.data, {});
});

test('an oversized save is rejected', async () => {
  const token = await register();

  const save = await call(app, 'PUT', '/profile', { token, body: { version: 0, data: { blob: 'x'.repeat(300 * 1024) } } });

  assert.equal(save.status, 413);
});

test('auth endpoints are rate limited', async () => {
  const limited = createApp({ sql, authRateLimit: { limit: 2, windowMs: 60_000 } });
  const attempt = () => call(limited, 'POST', '/auth/login', { body: { username: 'nobody_here', password: PASSWORD } });

  const statuses = [(await attempt()).status, (await attempt()).status, (await attempt()).status];

  assert.deepEqual(statuses, [401, 401, 429]);
});

test('an unexpected failure returns 500 without leaking details', async () => {
  const closedSql = connect(databaseUrl);
  await closedSql.end();
  const broken = createApp({ sql: closedSql, authRateLimit: NO_RATE_LIMIT });

  const response = await call(broken, 'GET', '/health');

  assert.equal(response.status, 500);
  assert.deepEqual(response.body, { success: false, data: null, error: 'Internal server error' });
});
