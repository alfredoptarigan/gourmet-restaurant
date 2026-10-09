import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import type postgres from 'postgres';
import { z } from 'zod';
import { requireAuth, type AuthEnv } from './auth.ts';
import type { Sql } from './db.ts';
import { ApiError, fail, ok, parseBody } from './http.ts';

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

// The client says how many dishes were paid for, never how many coins that is worth.
const earningsSchema = z.strictObject({
  dishes: z.number().int().min(1).max(MAX_REPORTED_DISHES),
});

type ProfileRow = { username: string; coins: string; cash: string; data: Record<string, unknown>; version: number };

function toProfile(row: ProfileRow) {
  // bigint columns arrive as strings; game currency stays far below 2^53.
  return { username: row.username, coins: Number(row.coins), cash: Number(row.cash), version: row.version, data: row.data };
}

export function profileRoutes(sql: Sql): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();
  routes.use(requireAuth(sql));

  routes.get('/', async (c) => {
    const rows = await sql<ProfileRow[]>`
      select u.username, p.coins, p.cash, p.data, p.version
      from profiles p join users u on u.id = p.user_id
      where p.user_id = ${c.get('userId')}`;
    const row: ProfileRow | undefined = rows[0];
    if (!row) {
      throw new ApiError(404, 'Profile not found');
    }
    return ok(c, toProfile(row));
  });

  routes.put(
    '/',
    bodyLimit({ maxSize: MAX_SAVE_BYTES, onError: (c) => fail(c, 413, 'Profile is too large to save') }),
    async (c) => {
      const { version, data } = await parseBody(c, saveSchema);
      // The version check makes a save from a stale copy (second device, retried request) fail
      // instead of silently overwriting newer data.
      const rows = await sql<{ version: number }[]>`
        update profiles
        set data = ${sql.json(data as postgres.JSONValue)}, version = version + 1, updated_at = now()
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
    const { dishes } = await parseBody(c, earningsSchema);
    // One statement, so two reports arriving together cannot both spend the same allowance.
    // The clock only restarts when something was credited: a report that came too early
    // must not push the next payout further away.
    const rows = await sql<{ coins: string; credited: number }[]>`
      with allowance as (
        select user_id, least(
          ${dishes}::int,
          floor(
            least(extract(epoch from now() - last_earned_at), ${MAX_ALLOWANCE_SECONDS}::int)
            * ${MAX_DISHES_PER_MINUTE}::int / 60.0
          )::int
        ) as credited
        from profiles
        where user_id = ${c.get('userId')}
        for update
      )
      update profiles
      set coins = profiles.coins + allowance.credited * ${COINS_PER_DISH}::int,
          last_earned_at = case when allowance.credited > 0 then now() else profiles.last_earned_at end
      from allowance
      where profiles.user_id = allowance.user_id
      returning profiles.coins, allowance.credited`;
    const row: { coins: string; credited: number } | undefined = rows[0];
    if (!row) {
      throw new ApiError(404, 'Profile not found');
    }
    return ok(c, { credited: row.credited, coins: Number(row.coins) });
  });

  return routes;
}
