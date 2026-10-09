// Integration tests against a real PostgreSQL database. Run: npm test
import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { createApp } from '../src/app.ts';
import { parseCatalog, type Catalog } from '../src/catalog.ts';
import { parseCookbook } from '../src/kitchen.ts';
import { parseQuiz } from '../src/quiz.ts';
import { parseRewards } from '../src/foodking.ts';
import { connect, migrate } from '../src/db.ts';

const databaseUrl = process.env.TEST_DATABASE_URL ?? 'postgres://localhost/gourmet_street_test';
// These tests truncate every table, so refuse anything that is not clearly a test database.
assert.match(new URL(databaseUrl).pathname, /_test$/, 'TEST_DATABASE_URL must name a database ending in _test');

const PASSWORD = 'correct horse battery';
const NO_RATE_LIMIT = { limit: 1000, windowMs: 60_000 };

const sql = connect(databaseUrl);
// A stand-in for data/restaurant.json, which is not in the repository.
const CHAIR = 3040001;
const FANCY_LAMP = 3020099;
const AWARD = 3100000;
const CASH_ONLY = 3020098;
const OUTDOOR_AREA = 3900000;
const WOOD_FLOOR_FOR_TEST = 3050001;
const RUBY_JUICE = 6000000;
const catalog: Catalog = parseCatalog([
  { items: [{ id: '3900000', cost: '2500', unlockLevel: '10' }] },
  { items: [{ id: '6000000', cost: '80', workTime: '3600' }] },
  { name: 'Chair', items: [{ id: String(CHAIR), cost: '200', cash: '0' }] },
  {
    name: 'Decoration',
    items: [
      { id: String(FANCY_LAMP), cost: '600', cash: '0' },
      { id: String(CASH_ONLY), cost: '600', cash: '5' },
    ],
  },
  { name: 'Award', items: [{ id: String(AWARD), cost: '0', cash: '0', invisible: true }] },
]);
const GARDEN_SALAD = 5000008;
const SALAD = 4000034;
const cookbook = parseCookbook(
  [
    {
      name: 'Starter',
      items: [
        { id: String(GARDEN_SALAD), ingredients: 'Salad, Tomato, Egg' },
        { id: '5000099', ingredients: 'Salad, Salad, Basil' },
        { id: '5000098', ingredients: 'Salad', expireDate: '2010-12-31' },
      ],
    },
  ],
  [
    {
      name: 'Ingredient',
      items: [
        { id: '4000034', name: 'Salad', cash: '4' },
        { id: '4000040', name: 'Tomato', cash: '8' },
        { id: '4000013', name: 'Egg', cash: '6' },
        { id: '4000000', name: 'Basil', cash: '8', noCoinShop: true, plantClassName: 'BasilGrown' },
      ],
    },
  ],
);
const quiz = parseQuiz(
  [
    {
      items: [
        {
          question: 'A tomato is a?',
          reward: 'Salad',
          children: [{ attributes: { text: 'Nut' } }, { attributes: { text: 'Fruit', correct: 'true' } }],
        },
        { question: 'No answer here?', reward: 'Salad', children: [{ attributes: { text: 'A' } }, { attributes: { text: 'B' } }] },
      ],
    },
  ],
  [{ items: [{ id: '4000034', name: 'Salad' }] }],
);
const app = createApp({ sql, catalog, cookbook, quiz, authRateLimit: NO_RATE_LIMIT });

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

test('register creates an account with the starting restaurant', async () => {
  const token = await register();

  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(profile.status, 200);
  const { data, ...rest } = profile.body.data;
  assert.deepEqual(rest, { username: 'chef_anna', coins: 0, cash: 0, gourmetPoints: 0, level: 1, version: 0 });
  assert.equal(data.layout.items.length, 16);
  assert.equal(data.layout.floor, 3050000);
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
  const settings = { music: 'off', tutorial: { step: 3 } };

  const save = await call(app, 'PUT', '/profile', { token, body: { version: 0, data: settings } });
  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(save.status, 200);
  assert.deepEqual(save.body.data, { version: 1 });
  assert.equal(profile.body.data.data.music, 'off');
  assert.deepEqual(profile.body.data.data.tutorial, { step: 3 });
  assert.equal(profile.body.data.version, 1);
});

test('a save that leaves out the layout keeps the restaurant as it was', async () => {
  const token = await register();

  await call(app, 'PUT', '/profile', { token, body: { version: 0, data: { music: 'off' } } });
  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(profile.body.data.data.layout.items.length, 16);
});

test('saving from a stale version is rejected and changes nothing', async () => {
  const token = await register();
  await call(app, 'PUT', '/profile', { token, body: { version: 0, data: { floor: 'wood' } } });

  const stale = await call(app, 'PUT', '/profile', { token, body: { version: 0, data: { floor: 'marble' } } });
  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(stale.status, 409);
  assert.equal(profile.body.data.data.floor, 'wood');
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

  assert.equal(profile.body.data.data.floor, undefined);
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
  assert.deepEqual(report.body.data, { credited: 3, creditedExtras: 0, coins: 6, gourmetPoints: 3, level: 1, levelUpReward: 0 });
  assert.equal(profile.body.data.coins, 6);
});

test('dishes beyond what the elapsed time allows are not credited', async () => {
  const token = await register();
  await ageEarnings(60);

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 100 } });

  assert.deepEqual(report.body.data, { credited: 28, creditedExtras: 0, coins: 56, gourmetPoints: 28, level: 1, levelUpReward: 0 });
});

test('nothing is credited when no time has passed', async () => {
  const token = await register();

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 5 } });

  assert.equal(report.status, 200);
  assert.deepEqual(report.body.data, { credited: 0, creditedExtras: 0, coins: 0, gourmetPoints: 0, level: 1, levelUpReward: 0 });
});

test('a report uses up the allowance it drew on', async () => {
  const token = await register();
  await ageEarnings(60);

  await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 28 } });
  const again = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 28 } });

  assert.deepEqual(again.body.data, { credited: 0, creditedExtras: 0, coins: 56, gourmetPoints: 28, level: 1, levelUpReward: 0 });
});

test('a report that credits nothing leaves the allowance to keep building', async () => {
  const token = await register();
  await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 5 } });
  await ageEarnings(60);

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 5 } });

  assert.deepEqual(report.body.data, { credited: 5, creditedExtras: 0, coins: 10, gourmetPoints: 5, level: 1, levelUpReward: 0 });
});

test('allowance stops building after ten minutes away', async () => {
  const token = await register();
  await ageEarnings(24 * 60 * 60);

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 1000 } });

  assert.deepEqual(report.body.data, { credited: 280, creditedExtras: 0, coins: 8560, gourmetPoints: 280, level: 5, levelUpReward: 8000 });
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

  assert.deepEqual(first.body.data, { credited: 50, creditedExtras: 0, coins: 3600, gourmetPoints: 50, level: 2, levelUpReward: 3500 });
  assert.deepEqual(second.body.data, { credited: 5, creditedExtras: 0, coins: 3610, gourmetPoints: 55, level: 2, levelUpReward: 0 });
});

test('one report can cross several levels and pays every reward on the way', async () => {
  const token = await register();
  await ageEarnings(600);

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 100 } });

  // Levels 2, 3, and 4 start at 50, 70, and 100 points and pay 3500, 2500, and 1000.
  assert.deepEqual(report.body.data, { credited: 100, creditedExtras: 0, coins: 7200, gourmetPoints: 100, level: 4, levelUpReward: 7000 });
});

test('extras pay one coin and one gourmet point each, after the dishes', async () => {
  const token = await register();
  await ageEarnings(60);

  const report = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 27, extras: 5 } });
  const onlyExtras = await call(app, 'POST', '/profile/earnings', { token, body: { dishes: 0, extras: 1 } });

  // A minute allows 28 payouts: all 27 dishes, then one of the extras.
  assert.deepEqual(report.body.data, { credited: 27, creditedExtras: 1, coins: 55, gourmetPoints: 28, level: 1, levelUpReward: 0 });
  assert.equal(onlyExtras.status, 200);
  assert.equal(onlyExtras.body.data.creditedExtras, 0);
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

  for (const body of [{ dishes: 0 }, { dishes: -1 }, { dishes: 1.5 }, { dishes: '3' }, { dishes: 1001 }, {}, { dishes: 1, coins: 99 }, { dishes: 1, extras: -1 }, { dishes: 0, extras: 0 }]) {
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

async function giveCoins(amount: number): Promise<void> {
  await sql`update profiles set coins = ${amount}`;
}

async function inventory(token: string): Promise<Record<string, number>> {
  const response = await call(app, 'GET', '/shop/inventory', { token });
  assert.equal(response.status, 200);
  return response.body.data.items;
}

test('food for the staff is paid for and used up, never owned', async () => {
  const token = await register();
  await giveCoins(100);

  const used = await call(app, 'POST', '/shop/use', { token, body: { itemId: RUBY_JUICE } });
  const again = await call(app, 'POST', '/shop/use', { token, body: { itemId: RUBY_JUICE } });
  const bought = await call(app, 'POST', '/shop/buy', { token, body: { itemId: RUBY_JUICE } });
  const chair = await call(app, 'POST', '/shop/use', { token, body: { itemId: CHAIR } });

  assert.equal(used.status, 200);
  assert.deepEqual(used.body.data, { coins: 20 });
  assert.equal(again.status, 409);
  assert.equal(bought.status, 404);
  assert.equal(chair.status, 404);
  assert.equal((await inventory(token))[String(RUBY_JUICE)], undefined);
});

test('a new player knows three recipes and holds the ingredients for them', async () => {
  const token = await register();

  const kitchen = await call(app, 'GET', '/kitchen', { token });
  const again = await call(app, 'GET', '/kitchen', { token });

  assert.equal(kitchen.status, 200);
  assert.deepEqual(kitchen.body.data.recipes, { 5000008: 1, 5100003: 1, 5200000: 1 });
  assert.equal(kitchen.body.data.ingredients[SALAD], 2);
  assert.deepEqual(again.body.data, kitchen.body.data);
});

test('a set of ingredients takes a recipe a level higher and earns gourmet points', async () => {
  const token = await register();
  await call(app, 'GET', '/kitchen', { token });

  const learned = await call(app, 'POST', '/kitchen/learn', { token, body: { recipeId: GARDEN_SALAD } });
  const second = await call(app, 'POST', '/kitchen/learn', { token, body: { recipeId: GARDEN_SALAD } });
  const third = await call(app, 'POST', '/kitchen/learn', { token, body: { recipeId: GARDEN_SALAD } });

  assert.equal(learned.status, 200);
  // Level 2 is worth 50 gourmet points, which also reaches player level 2 and its reward.
  assert.equal(learned.body.data.level, 2);
  assert.equal(learned.body.data.gourmetPoints, 50);
  assert.equal(learned.body.data.levelUpReward, 3500);
  assert.equal(learned.body.data.ingredients[SALAD], 1);
  assert.equal(second.body.data.level, 3);
  assert.equal(second.body.data.ingredients[SALAD], undefined);
  assert.equal(third.status, 409);
  assert.equal(third.body.error, 'You do not have the ingredients for this recipe');
});

test('a recipe needing an ingredient twice takes two of it, and nothing is spent on a refusal', async () => {
  const token = await register();
  await call(app, 'GET', '/kitchen', { token });

  const refused = await call(app, 'POST', '/kitchen/learn', { token, body: { recipeId: 5000099 } });
  const kitchen = await call(app, 'GET', '/kitchen', { token });
  const expired = await call(app, 'POST', '/kitchen/learn', { token, body: { recipeId: 5000098 } });

  assert.equal(refused.status, 409);
  assert.equal(kitchen.body.data.ingredients[SALAD], 2);
  assert.equal(expired.body.error, 'This recipe can no longer be learned');
});

test('ingredients sell for coins by their cash price, except the ones kept for cash', async () => {
  const token = await register();
  await giveCoins(1500);

  const bought = await call(app, 'POST', '/kitchen/buy-ingredient', { token, body: { ingredientId: SALAD } });
  const tooDear = await call(app, 'POST', '/kitchen/buy-ingredient', { token, body: { ingredientId: 4000040 } });
  const cashOnly = await call(app, 'POST', '/kitchen/buy-ingredient', { token, body: { ingredientId: 4000000 } });

  assert.deepEqual(bought.body.data, { coins: 500, quantity: 1 });
  assert.equal(tooDear.status, 409);
  assert.equal(cashOnly.status, 404);
});

async function ageGarden(seconds: number): Promise<void> {
  await sql`update garden_plots set checked_at = checked_at - make_interval(secs => ${seconds}),
            wet_until = wet_until - make_interval(secs => ${seconds})`;
}

test('a garden plot opens at level 7 and a seed costs 2000 coins', async () => {
  const token = await register();
  await giveCoins(5000);

  const locked = await call(app, 'POST', '/garden/plant', { token, body: { plot: 0 } });
  await sql`update profiles set gourmet_points = 1000`;
  const planted = await call(app, 'POST', '/garden/plant', { token, body: { plot: 0 } });
  const twice = await call(app, 'POST', '/garden/plant', { token, body: { plot: 0 } });

  assert.equal(locked.status, 409);
  assert.equal(planted.status, 200);
  assert.equal(planted.body.data.plotCount, 1);
  assert.deepEqual(planted.body.data.plots, [{ plot: 0, ingredientId: 4000000, grownSeconds: 0, wetSeconds: 10800, ripe: false }]);
  assert.equal(twice.body.error, 'Something already grows there');
  assert.equal((await call(app, 'GET', '/profile', { token })).body.data.coins, 3000);
});

test('a plant only grows while its soil is wet, and is harvested into an ingredient', async () => {
  const token = await register();
  await giveCoins(2000);
  await sql`update profiles set gourmet_points = 1000`;
  await call(app, 'POST', '/garden/plant', { token, body: { plot: 0 } });

  await ageGarden(5 * 3600);
  const dry = await call(app, 'GET', '/garden', { token });
  const early = await call(app, 'POST', '/garden/harvest', { token, body: { plot: 0 } });
  const watered = await call(app, 'POST', '/garden/water', { token, body: { plot: 0 } });
  for (let watering = 0; watering < 3; watering += 1) {
    await call(app, 'POST', '/garden/water', { token, body: { plot: 0 } });
  }
  const soaked = await call(app, 'GET', '/garden', { token });
  await sql`update garden_plots set grown_seconds = ${48 * 3600}`;
  const harvested = await call(app, 'POST', '/garden/harvest', { token, body: { plot: 0 } });
  const kitchen = await call(app, 'GET', '/kitchen', { token });

  // Five hours passed, but the soil was wet for only three of them.
  assert.equal(dry.body.data.plots[0].grownSeconds, 10800);
  assert.equal(dry.body.data.plots[0].wetSeconds, 0);
  assert.equal(early.status, 409);
  assert.equal(watered.body.data.plots[0].wetSeconds, 10800);
  assert.equal(soaked.body.data.plots[0].wetSeconds, 9 * 3600);
  assert.equal(harvested.body.data.ingredientId, 4000000);
  assert.deepEqual(harvested.body.data.plots, []);
  assert.equal(kitchen.body.data.ingredients[4000000], 1);
});

test('spending 2000 coins earns the bronze big-spender trophy', async () => {
  const token = await register();
  await giveCoins(2000);

  for (let chair = 0; chair < 10; chair += 1) {
    await call(app, 'POST', '/shop/buy', { token, body: { itemId: CHAIR } });
  }
  const awards = await call(app, 'GET', '/awards', { token });

  assert.deepEqual(awards.body.data.progress, { 4: 2000, 5: 10 });
  const owned = await inventory(token);
  assert.equal(owned['3400008'], 1);
  assert.equal(owned['3400017'], 1);
});

test('the client may report only the awards of its own simulation', async () => {
  const token = await register();

  const trash = await call(app, 'POST', '/awards/progress', { token, body: { award: 1, amount: 100 } });
  const coins = await call(app, 'POST', '/awards/progress', { token, body: { award: 4, amount: 100 } });
  const tooMany = await call(app, 'POST', '/awards/progress', { token, body: { award: 1, amount: 101 } });

  assert.deepEqual(trash.body.data, { trophies: [3400023] });
  assert.equal(coins.status, 400);
  assert.equal(tooMany.status, 400);
});

test('the daily quiz pays an ingredient for a right answer, once a day', async () => {
  const token = await register();

  const asked = await call(app, 'GET', '/quiz', { token });
  const answered = await call(app, 'POST', '/quiz/answer', { token, body: { choice: 1 } });
  const again = await call(app, 'POST', '/quiz/answer', { token, body: { choice: 1 } });
  const after = await call(app, 'GET', '/quiz', { token });
  const kitchen = await call(app, 'GET', '/kitchen', { token });

  // The question with no right answer is left out of the quiz.
  assert.equal(quiz.length, 1);
  assert.deepEqual(asked.body.data, { question: 'A tomato is a?', choices: ['Nut', 'Fruit'], rewardIngredientId: SALAD, answered: false });
  assert.deepEqual(answered.body.data, { correct: true, correctChoice: 1, rewardIngredientId: SALAD });
  assert.equal(again.status, 409);
  assert.equal(after.body.data.answered, true);
  // Two from the starting ingredients and one from the quiz.
  assert.equal(kitchen.body.data.ingredients[SALAD], 3);
});

test('a wrong answer pays nothing and still uses up the day', async () => {
  const token = await register();

  const wrong = await call(app, 'POST', '/quiz/answer', { token, body: { choice: 0 } });
  const retry = await call(app, 'POST', '/quiz/answer', { token, body: { choice: 1 } });
  const nonsense = await call(app, 'POST', '/quiz/answer', { token, body: { choice: 9 } });

  assert.deepEqual(wrong.body.data, { correct: false, correctChoice: 1, rewardIngredientId: null });
  assert.equal(retry.status, 409);
  assert.equal(nonsense.status, 400);
});

test('when the Food King visits, one of his three rewards can be claimed once', async () => {
  const rewards = parseRewards([
    { kind: 'ingredient', groups: [{ items: [{ id: String(SALAD), foodKingFeed: true }, { id: '4000040' }] }] },
    { kind: 'recipe', groups: [{ items: [{ id: '5000019', foodKingFeed: true }] }] },
    { kind: 'item', groups: [{ items: [{ id: String(FANCY_LAMP), foodKingFeed: true }] }] },
  ]);
  const always = createApp({ sql, catalog, cookbook, foodKingRewards: rewards, foodKingChance: 1, authRateLimit: NO_RATE_LIMIT });
  const never = createApp({ sql, catalog, cookbook, foodKingRewards: rewards, foodKingChance: 1_000_000_007, authRateLimit: NO_RATE_LIMIT });
  const token = await register();

  const visit = await call(always, 'GET', '/foodking', { token });
  const missed = await call(never, 'POST', '/foodking/claim', { token, body: { choice: 0 } });
  const claims = [];
  for (const choice of [0, 1, 2]) {
    claims.push(await call(always, 'POST', '/foodking/claim', { token, body: { choice } }));
  }

  assert.equal(rewards.length, 3);
  assert.equal(visit.body.data.visiting, true);
  assert.equal(visit.body.data.rewards.length, 3);
  assert.equal(missed.status, 409);
  assert.equal(claims[0].status, 200);
  assert.deepEqual(claims[0].body.data.reward, visit.body.data.rewards[0]);
  assert.deepEqual(claims.slice(1).map((claim) => claim.status), [409, 409]);
});

test('an item with an unlock level cannot be bought before that level', async () => {
  const token = await register();
  await giveCoins(5000);

  const early = await call(app, 'POST', '/shop/buy', { token, body: { itemId: OUTDOOR_AREA } });
  // Level 10 starts at 6000 gourmet points.
  await sql`update profiles set gourmet_points = 6000`;
  const later = await call(app, 'POST', '/shop/buy', { token, body: { itemId: OUTDOOR_AREA } });

  assert.equal(early.status, 409);
  assert.equal(early.body.error, 'Reach level 10 to buy this');
  assert.equal(later.status, 200);
  assert.equal(later.body.data.coins, 2500);
});

test('every painted floor tile uses one owned floor item', async () => {
  const token = await register();
  const profile = await call(app, 'GET', '/profile', { token });
  const layout = profile.body.data.data.layout;
  const floor = layout.floor;

  const one = await call(app, 'PUT', '/profile', {
    token,
    body: { version: 0, data: { layout: { ...layout, floor: WOOD_FLOOR_FOR_TEST, tiles: [{ id: floor, x: 2, y: 2 }] } } },
  });
  const twice = await call(app, 'PUT', '/profile', {
    token,
    body: { version: 0, data: { layout: { ...layout, tiles: [{ id: floor, x: 2, y: 2 }, { id: floor, x: 2, y: 2 }] } } },
  });
  const unowned = await call(app, 'PUT', '/profile', {
    token,
    body: { version: 0, data: { layout: { ...layout, tiles: [{ id: floor, x: 2, y: 2 }] } } },
  });

  assert.equal(one.status, 409);
  assert.equal(twice.status, 400);
  // The base floor already uses the only one owned.
  assert.equal(unowned.status, 409);
});

test('a new player owns the furniture of the starting restaurant', async () => {
  const token = await register();

  const items = await inventory(token);

  assert.equal(items[CHAIR], 3);
  assert.equal(items[3050000], 1, 'the starting floor');
  assert.equal(items[3060016], 1, 'the starting wallpaper');
});

test('an account from before the shop existed gets the starting restaurant on its next visit', async () => {
  const token = await register();
  await sql`delete from owned_items`;
  await sql`update profiles set data = '{"note": "kept"}'`;

  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(profile.body.data.data.layout.items.length, 16);
  assert.equal(profile.body.data.data.note, 'kept');
  assert.equal((await inventory(token))[CHAIR], 3);
});

test('buying an item takes its price and adds it to the inventory', async () => {
  const token = await register();
  await giveCoins(1000);

  const bought = await call(app, 'POST', '/shop/buy', { token, body: { itemId: FANCY_LAMP } });
  const profile = await call(app, 'GET', '/profile', { token });

  assert.equal(bought.status, 200);
  assert.deepEqual(bought.body.data, { coins: 400, quantity: 1, trophies: [] });
  assert.equal(profile.body.data.coins, 400);
  assert.equal((await inventory(token))[FANCY_LAMP], 1);
});

test('buying is refused without enough coins and nothing changes', async () => {
  const token = await register();
  await giveCoins(599);

  const bought = await call(app, 'POST', '/shop/buy', { token, body: { itemId: FANCY_LAMP } });

  assert.equal(bought.status, 409);
  assert.equal(bought.body.error, 'Not enough coins');
  assert.equal((await inventory(token))[FANCY_LAMP], undefined);
  assert.equal((await call(app, 'GET', '/profile', { token })).body.data.coins, 599);
});

test('only items sold for coins can be bought', async () => {
  const token = await register();
  await giveCoins(100000);

  for (const itemId of [AWARD, CASH_ONLY, 999]) {
    const bought = await call(app, 'POST', '/shop/buy', { token, body: { itemId } });
    assert.equal(bought.status, 404, String(itemId));
  }
  assert.equal((await call(app, 'GET', '/profile', { token })).body.data.coins, 100000);
});

test('selling a spare item pays a third of its price', async () => {
  const token = await register();
  await giveCoins(200);
  await call(app, 'POST', '/shop/buy', { token, body: { itemId: CHAIR } });

  const sold = await call(app, 'POST', '/shop/sell', { token, body: { itemId: CHAIR } });

  assert.equal(sold.status, 200);
  assert.deepEqual(sold.body.data, { coins: 66, quantity: 3 });
  assert.equal((await inventory(token))[CHAIR], 3);
});

test('the last copy of an item disappears from the inventory when sold', async () => {
  const token = await register();
  await giveCoins(600);
  await call(app, 'POST', '/shop/buy', { token, body: { itemId: FANCY_LAMP } });

  const sold = await call(app, 'POST', '/shop/sell', { token, body: { itemId: FANCY_LAMP } });

  assert.deepEqual(sold.body.data, { coins: 200, quantity: 0 });
  assert.equal((await inventory(token))[FANCY_LAMP], undefined);
});

test('an item that is not owned cannot be sold', async () => {
  const token = await register();

  const sold = await call(app, 'POST', '/shop/sell', { token, body: { itemId: FANCY_LAMP } });

  assert.equal(sold.status, 409);
  assert.equal((await call(app, 'GET', '/profile', { token })).body.data.coins, 0);
});

test('an item placed in the restaurant cannot be sold until it is put away', async () => {
  const token = await register();

  // All three starting chairs stand in the starting layout.
  const sold = await call(app, 'POST', '/shop/sell', { token, body: { itemId: CHAIR } });

  assert.equal(sold.status, 409);
  assert.equal((await inventory(token))[CHAIR], 3);
});

test('a layout may only place items the player owns', async () => {
  const token = await register();
  const owned = { items: [{ id: CHAIR, x: 2, y: 3, rotation: 1 }], floor: 3050000, wallpaper: 3060016 };
  const notOwned = { ...owned, items: [{ id: FANCY_LAMP, x: 2, y: 3, rotation: 0 }] };
  const tooMany = { ...owned, items: [1, 2, 3, 4].map((x) => ({ id: CHAIR, x, y: 3, rotation: 0 })) };
  const unownedFloor = { ...owned, floor: 3050001 };

  const saved = await call(app, 'PUT', '/profile', { token, body: { version: 0, data: { layout: owned } } });
  const refused = [];
  for (const layout of [notOwned, tooMany, unownedFloor]) {
    refused.push((await call(app, 'PUT', '/profile', { token, body: { version: 1, data: { layout } } })).status);
  }

  assert.equal(saved.status, 200);
  assert.deepEqual(refused, [409, 409, 409]);
  assert.deepEqual((await call(app, 'GET', '/profile', { token })).body.data.data.layout, owned);
});

test('a malformed layout is rejected', async () => {
  const token = await register();
  const item = { id: CHAIR, x: 2, y: 3, rotation: 0 };

  for (const layout of [
    { items: [{ ...item, x: -1 }], floor: 3050000, wallpaper: 3060016 },
    { items: [{ ...item, rotation: 4 }], floor: 3050000, wallpaper: 3060016 },
    { items: [{ ...item, extra: true }], floor: 3050000, wallpaper: 3060016 },
    { items: 'chairs', floor: 3050000, wallpaper: 3060016 },
    { items: [item] },
  ]) {
    const saved = await call(app, 'PUT', '/profile', { token, body: { version: 0, data: { layout } } });
    assert.equal(saved.status, 400, JSON.stringify(layout));
  }
});

test('the shop requires a session', async () => {
  assert.equal((await call(app, 'GET', '/shop/inventory')).status, 401);
  assert.equal((await call(app, 'POST', '/shop/buy', { body: { itemId: CHAIR } })).status, 401);
  assert.equal((await call(app, 'POST', '/shop/sell', { body: { itemId: CHAIR } })).status, 401);
});

test('auth endpoints are rate limited', async () => {
  const limited = createApp({ sql, catalog, authRateLimit: { limit: 2, windowMs: 60_000 } });
  const attempt = () => call(limited, 'POST', '/auth/login', { body: { username: 'nobody_here', password: PASSWORD } });

  const statuses = [(await attempt()).status, (await attempt()).status, (await attempt()).status];

  assert.deepEqual(statuses, [401, 401, 429]);
});

test('an unexpected failure returns 500 without leaking details', async () => {
  const closedSql = connect(databaseUrl);
  await closedSql.end();
  const broken = createApp({ sql: closedSql, catalog, authRateLimit: NO_RATE_LIMIT });

  const response = await call(broken, 'GET', '/health');

  assert.equal(response.status, 500);
  assert.deepEqual(response.body, { success: false, data: null, error: 'Internal server error' });
});
