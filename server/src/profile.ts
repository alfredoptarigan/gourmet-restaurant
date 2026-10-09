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

  return routes;
}
