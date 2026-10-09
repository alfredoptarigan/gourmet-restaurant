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
  assert.deepEqual(profile.body.data, { username: 'chef_anna', coins: 0, cash: 0, gourmetPoints: 0, level: 1, version: 0, data: {} });
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

// Pretends the player last earned `seconds` ago, so a report has allowance to draw on.
async function ageEarnings(seconds: number): Promise<void> {
  await sql`update profiles set last_earned_at = now() - make_interval(secs => ${seconds})`;
}

test('reporting dishes credits two coins each', async () => {
  const token = await register();
  await ageEarnings(60);

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 3 } });
  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(report.status, 200);
  assert.deepEqual(report.body.data, { credited: 3, coins: 6, gourmetPoints: 3, level: 1, levelUpReward: 0 });
  assert.equal(profile.body.data.coins, 6);
});

test('dishes beyond what the elapsed time allows are not credited', async () => {
  const token = await register();
  await ageEarnings(60);

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 100 } });

  assert.deepEqual(report.body.data, { credited: 28, coins: 56, gourmetPoints: 28, level: 1, levelUpReward: 0 });
});

test('nothing is credited when no time has passed', async () => {
  const token = await register();

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 5 } });

  assert.equal(report.status, 200);
  assert.deepEqual(report.body.data, { credited: 0, coins: 0, gourmetPoints: 0, level: 1, levelUpReward: 0 });
});

test('a report uses up the allowance it drew on', async () => {
  const token = await register();
  await ageEarnings(60);

  await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 28 } });
  const again = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 28 } });

  assert.deepEqual(again.body.data, { credited: 0, coins: 56, gourmetPoints: 28, level: 1, levelUpReward: 0 });
});

test('a report that credits nothing leaves the allowance to keep building', async () => {
  const token = await register();
  await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 5 } });
  await ageEarnings(60);

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 5 } });

  assert.deepEqual(report.body.data, { credited: 5, coins: 10, gourmetPoints: 5, level: 1, levelUpReward: 0 });
});

test('allowance stops building after ten minutes away', async () => {
  const token = await register();
  await ageEarnings(24 * 60 * 60);

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 1000 } });

  assert.deepEqual(report.body.data, { credited: 280, coins: 8560, gourmetPoints: 280, level: 5, levelUpReward: 8000 });
});

test('each credited dish is one gourmet point', async () => {
  const token = await register();
  await ageEarnings(60);

  await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 3 } });
  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(profile.body.data.gourmetPoints, 3);
  assert.equal(profile.body.data.level, 1);
});

test('reaching 50 gourmet points is level 2 and pays its 3500 coin reward once', async () => {
  const token = await register();
  await ageEarnings(600);

  const first = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 50 } });
  await ageEarnings(600);
  const second = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 5 } });

  assert.deepEqual(first.body.data, { credited: 50, coins: 3600, gourmetPoints: 50, level: 2, levelUpReward: 3500 });
  assert.deepEqual(second.body.data, { credited: 5, coins: 3610, gourmetPoints: 55, level: 2, levelUpReward: 0 });
});

test('one report can cross several levels and pays every reward on the way', async () => {
  const token = await register();
  await ageEarnings(600);

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 100 } });

  // Levels 2, 3, and 4 start at 50, 70, and 100 points and pay 3500, 2500, and 1000.
  assert.deepEqual(report.body.data, { credited: 100, coins: 7200, gourmetPoints: 100, level: 4, levelUpReward: 7000 });
});

test('earnings only reach the signed-in player', async () => {
  const anna = await register('chef_anna');
  const budi = await register('chef_budi');
  await ageEarnings(60);

  await call(app, 'POST', '/profile/earnings', { token: anna, body: { dishes: 4 } });
  const profile = await call(app, 'GET', '/profile', { token: budi });

  assert.equal(profile.body.data.coins, 0);
});

test('an earnings report must be a whole number of dishes from 1 to 1000', async () => {
  const token = await register();
  await ageEarnings(60);

  for (const body of [{ dishes: 0 }, { dishes: -1 }, { dishes: 1.5 }, { dishes: '3' }, { dishes: 1001 }, {}, { dishes: 1, coins: 99 }]) {
    const report = await call(app, 'POST', '/profile/earnings', { token, body });
    assert.equal(report.status, 400, JSON.stringify(body));
  }
  const profile = await call(app, 'GET', '/profile', { token });
  assert.equal(profile.body.data.coins, 0);
});

test('earnings require a session', async () => {
  const report = await call(app, 'POST', '/profile/earnings', { body: { dishes: 1 } });

  assert.equal(report.status, 401);
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
