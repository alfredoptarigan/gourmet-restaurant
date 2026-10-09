import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import type postgres from 'postgres';
import { z } from 'zod';
import { requireAuth, type AuthEnv } from './auth.ts';
import type { Sql } from './db.ts';
import { ApiError, describeIssues, fail, ok, parseBody } from './http.ts';
import { levelFor, rewardBetween } from './levels.ts';
import { activePerks, assertLayoutIsOwned, grantStarterItems, layoutSchema, STARTER_LAYOUT } from './shop.ts';

const MAX_SAVE_BYTES = 256 * 1024;

// Strict on purpose: coins and cash are not accepted here. Only the server changes currency.
const saveSchema = z.strictObject({
  version: z.number().int().min(0),
  data: z.record(z.string(), z.unknown()),
});

// Every recipe in the game sells for 2 coins (GameWorld.COST_PER_DISH).
const COINS_PER_DISH = 2;
// The busiest a restaurant can get: GameWorld.MAX_DEMAND (550) x 0.05 customers a minute.
const MAX_DISHES_PER_MINUTE = 28;
// Allowance stops building after this long without a report, so time away is not a jackpot.
const MAX_ALLOWANCE_SECONDS = 600;
const MAX_REPORTED_DISHES = 1000;
// GameWorld.GOURMET_POINTS_PER_DISH, for a level 1 recipe.
const GOURMET_POINTS_PER_DISH = 1;
// GameWorld.COINS_PAYOUT_FUNCTIONAL_ITEMS and GOURMET_POINTS_PER_FUNCTIONAL_ITEM_PAYOUT.
const COINS_PER_EXTRA = 1;
const GOURMET_POINTS_PER_EXTRA = 1;

// The client says how many dishes were paid for, never how many coins that is worth.
// Extras are the small payouts that are not meals: a customer playing an arcade machine.
const earningsSchema = z
  .strictObject({
    dishes: z.number().int().min(0).max(MAX_REPORTED_DISHES),
    extras: z.number().int().min(0).max(MAX_REPORTED_DISHES).default(0),
  })
  .refine((report) => report.dishes + report.extras > 0, { message: 'Report at least one dish or extra' });

type ProfileRow = {
  username: string;
  coins: string;
  cash: string;
  gourmet_points: number;
  data: Record<string, unknown>;
  version: number;
};

function toProfile(row: ProfileRow) {
  return {
    username: row.username,
    // bigint columns arrive as strings; game currency stays far below 2^53.
    coins: Number(row.coins),
    cash: Number(row.cash),
    gourmetPoints: row.gourmet_points,
    level: levelFor(row.gourmet_points),
    version: row.version,
    data: row.data,
  };
}

export function profileRoutes(sql: Sql): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();
  routes.use(requireAuth(sql));

  routes.get('/', async (c) => {
    const rows = await sql<ProfileRow[]>`
      select u.username, p.coins, p.cash, p.gourmet_points, p.data, p.version
      from profiles p join users u on u.id = p.user_id
      where p.user_id = ${c.get('userId')}`;
    const row: ProfileRow | undefined = rows[0];
    if (!row) {
      throw new ApiError(404, 'Profile not found');
    }
    if (row.data.layout !== undefined) {
      return ok(c, toProfile(row));
    }
    // An account made before the shop existed has no layout and owns nothing. Give it the
    // starting restaurant now, keeping whatever else its data holds.
    const data = { ...row.data, layout: STARTER_LAYOUT };
    await sql.begin(async (transaction) => {
      await grantStarterItems(transaction, c.get('userId'));
      await transaction`
        update profiles set data = ${transaction.json(data as postgres.JSONValue)}
        where user_id = ${c.get('userId')}`;
    });
    return ok(c, toProfile({ ...row, data }));
  });

  routes.put(
    '/',
    bodyLimit({ maxSize: MAX_SAVE_BYTES, onError: (c) => fail(c, 413, 'Profile is too large to save') }),
    async (c) => {
      const { version, data } = await parseBody(c, saveSchema);
      // The rest of `data` is free-form, but a layout must be well-formed and use only
      // furniture the player owns: that is what stops the shop from being skipped.
      if (data.layout !== undefined) {
        const layout = layoutSchema.safeParse(data.layout);
        if (!layout.success) {
          throw new ApiError(400, describeIssues(layout.error));
        }
        await assertLayoutIsOwned(sql, c.get('userId'), layout.data);
      }
      // A save that says nothing about the layout keeps the one already stored: leaving it
      // out must not quietly reset the restaurant.
      // The version check makes a save from a stale copy (second device, retried request) fail
      // instead of silently overwriting newer data.
      const rows = await sql<{ version: number }[]>`
        update profiles
        set data = ${sql.json(data as postgres.JSONValue)} || case
              when ${data.layout !== undefined} or not (data ? 'layout') then '{}'::jsonb
              else jsonb_build_object('layout', data -> 'layout')
            end,
            version = version + 1, updated_at = now()
        where user_id = ${c.get('userId')} and version = ${version}
        returning version`;
      const saved: { version: number } | undefined = rows[0];
      if (!saved) {
        throw new ApiError(409, 'Profile was changed elsewhere. Reload it and try again');
      }
      return ok(c, { version: saved.version });
    },
  );

  routes.post('/earnings', async (c) => {
    const { dishes, extras } = await parseBody(c, earningsSchema);
    const userId = c.get('userId');
    // The row is locked for the whole read-decide-write, so two reports arriving together
    // cannot both spend the same allowance or both collect the same level-up reward.
    const earned = await sql.begin(async (transaction) => {
      const rows = await transaction<{ coins: string; gourmet_points: number; elapsed: string }[]>`
        select coins, gourmet_points, extract(epoch from now() - last_earned_at) as elapsed
        from profiles where user_id = ${userId} for update`;
      const before: { coins: string; gourmet_points: number; elapsed: string } | undefined = rows[0];
      if (!before) {
        throw new ApiError(404, 'Profile not found');
      }
      const allowance = Math.floor((Math.min(Number(before.elapsed), MAX_ALLOWANCE_SECONDS) * MAX_DISHES_PER_MINUTE) / 60);
      // Dishes and extras draw on the same allowance, dishes first.
      const credited = Math.max(0, Math.min(dishes, allowance));
      const creditedExtras = Math.max(0, Math.min(extras, allowance - credited));
      // The Hire Consultant perk multiplies the experience gained.
      const multiplier = (await activePerks(transaction, userId)).gourmet?.value ?? 1;
      const gourmetPoints =
        before.gourmet_points + (credited * GOURMET_POINTS_PER_DISH + creditedExtras * GOURMET_POINTS_PER_EXTRA) * multiplier;
      const level = levelFor(gourmetPoints);
      const levelUpReward = rewardBetween(levelFor(before.gourmet_points), level);
      const coins =
        Number(before.coins) + credited * COINS_PER_DISH + creditedExtras * COINS_PER_EXTRA + levelUpReward;
      // The clock only restarts when something was credited: a report that came too early
      // must not push the next payout further away.
      if (credited + creditedExtras > 0) {
        await transaction`
          update profiles
          set coins = ${coins}, gourmet_points = ${gourmetPoints}, last_earned_at = now()
          where user_id = ${userId}`;
      }
      return { credited, creditedExtras, coins, gourmetPoints, level, levelUpReward };
    });
    return ok(c, earned);
  });

  return routes;
}
