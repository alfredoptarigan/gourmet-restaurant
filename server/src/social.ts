import { randomInt } from 'node:crypto';
import { Hono } from 'hono';
import type postgres from 'postgres';
import { z } from 'zod';
import { requireAuth, type AuthEnv } from './auth.ts';
import { Award, addAward } from './awards.ts';
import type { Sql } from './db.ts';
import { plotsOf, plotsFor, waterPlot } from './garden.ts';
import { ApiError, ok, parseBody } from './http.ts';
import { STARTER_INGREDIENTS } from './kitchen.ts';
import { levelFor } from './levels.ts';

// GameWorld.WATER_FRIENDS_PLOT: a friend who waters a plot earns a coin.
const COINS_PER_FRIEND_WATERING = 1;
const MAX_MESSAGE_LENGTH = 200;
// The free daily gift is one of the everyday ingredients (the reference server's gift pool).
const GIFT_POOL = [...STARTER_INGREDIENTS.keys()];

const usernameBody = z.strictObject({ username: z.string().min(1).max(40) });
const userBody = z.strictObject({ userId: z.number().int().min(1) });
const plotBody = z.strictObject({ plot: z.number().int().min(0).max(8) });
const sendBody = z.discriminatedUnion('kind', [
  z.strictObject({ to: z.number().int().min(1), kind: z.literal('gift') }),
  z.strictObject({ to: z.number().int().min(1), kind: z.literal('ingredient'), itemId: z.number().int().min(1) }),
  z.strictObject({ to: z.number().int().min(1), kind: z.literal('message'), text: z.string().trim().min(1).max(MAX_MESSAGE_LENGTH) }),
]);

type Db = Sql | postgres.TransactionSql;

function pair(one: string | number, other: string | number): [string, string] {
  return Number(one) < Number(other) ? [String(one), String(other)] : [String(other), String(one)];
}

export async function areFriends(sql: Db, one: string | number, other: string | number): Promise<boolean> {
  const [a, b] = pair(one, other);
  const rows = await sql`select 1 from friendships where user_a = ${a} and user_b = ${b}`;
  return rows.length > 0;
}

async function befriend(sql: Db, one: string | number, other: string | number): Promise<void> {
  const [a, b] = pair(one, other);
  await sql`insert into friendships (user_a, user_b) values (${a}, ${b}) on conflict do nothing`;
  await sql`
    delete from friend_requests
    where (from_id = ${one} and to_id = ${other}) or (from_id = ${other} and to_id = ${one})`;
}

/** The friend's id from the path, after checking that they are a friend. */
async function friendFrom(sql: Sql, userId: string, raw: string): Promise<string> {
  if (!/^\d{1,18}$/.test(raw)) {
    throw new ApiError(404, 'No such friend');
  }
  if (!(await areFriends(sql, userId, raw))) {
    throw new ApiError(403, 'Only friends can do that');
  }
  return raw;
}

type PlayerRow = { id: string; username: string; gourmet_points: number; data: Record<string, unknown> };

/** What friends may see of a player: their name, level, looks, and building. */
function publicPlayer(row: PlayerRow) {
  return {
    id: Number(row.id),
    username: row.username,
    level: levelFor(row.gourmet_points),
    avatar: row.data.avatar ?? null,
    building: row.data.building ?? null,
  };
}

/**
 * Friends: requests, the friends list, visiting a friend's restaurant, and helping in it.
 * ponytail: friends are found by exact username. The original pulled them from Facebook.
 */
export function socialRoutes(sql: Sql): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();
  routes.use(requireAuth(sql));

  routes.get('/', async (c) => {
    const userId = c.get('userId');
    const friends = await sql<PlayerRow[]>`
      select u.id, u.username, p.gourmet_points, p.data
      from friendships f
      join users u on u.id = case when f.user_a = ${userId} then f.user_b else f.user_a end
      join profiles p on p.user_id = u.id
      where f.user_a = ${userId} or f.user_b = ${userId}
      order by lower(u.username)`;
    const incoming = await sql<{ id: string; username: string }[]>`
      select u.id, u.username from friend_requests r join users u on u.id = r.from_id
      where r.to_id = ${userId} order by r.created_at`;
    const outgoing = await sql<{ id: string; username: string }[]>`
      select u.id, u.username from friend_requests r join users u on u.id = r.to_id
      where r.from_id = ${userId} order by r.created_at`;
    const short = (row: { id: string; username: string }) => ({ id: Number(row.id), username: row.username });
    return ok(c, { friends: friends.map(publicPlayer), incoming: incoming.map(short), outgoing: outgoing.map(short) });
  });

  // Asking a player who has already asked you makes you friends at once.
  routes.post('/request', async (c) => {
    const { username } = await parseBody(c, usernameBody);
    const userId = c.get('userId');
    const found = await sql<{ id: string }[]>`select id from users where lower(username) = lower(${username})`;
    const other = found[0]?.id;
    if (!other) {
      throw new ApiError(404, 'No player has that name');
    }
    if (other === userId) {
      throw new ApiError(400, 'You cannot befriend yourself');
    }
    if (await areFriends(sql, userId, other)) {
      throw new ApiError(409, 'You are already friends');
    }
    const status = await sql.begin(async (transaction) => {
      const asked = await transaction`select 1 from friend_requests where from_id = ${other} and to_id = ${userId}`;
      if (asked.length > 0) {
        await befriend(transaction, userId, other);
        return 'friends';
      }
      await transaction`insert into friend_requests (from_id, to_id) values (${userId}, ${other}) on conflict do nothing`;
      return 'requested';
    });
    return ok(c, { status });
  });

  routes.post('/accept', async (c) => {
    const { userId: other } = await parseBody(c, userBody);
    const userId = c.get('userId');
    await sql.begin(async (transaction) => {
      const asked = await transaction`select 1 from friend_requests where from_id = ${other} and to_id = ${userId}`;
      if (asked.length === 0) {
        throw new ApiError(404, 'That player has not asked to be your friend');
      }
      await befriend(transaction, userId, other);
    });
    return ok(c, { status: 'friends' });
  });

  // Ends a friendship, or withdraws or declines a request.
  routes.post('/remove', async (c) => {
    const { userId: other } = await parseBody(c, userBody);
    const userId = c.get('userId');
    const [a, b] = pair(userId, other);
    await sql.begin(async (transaction) => {
      await transaction`delete from friendships where user_a = ${a} and user_b = ${b}`;
      await transaction`
        delete from friend_requests
        where (from_id = ${userId} and to_id = ${other}) or (from_id = ${other} and to_id = ${userId})`;
    });
    return ok(c, { status: 'removed' });
  });

  // A friend's restaurant as a visitor sees it.
  routes.get('/:id/restaurant', async (c) => {
    const friendId = await friendFrom(sql, c.get('userId'), c.req.param('id'));
    const rows = await sql<PlayerRow[]>`
      select u.id, u.username, p.gourmet_points, p.data
      from users u join profiles p on p.user_id = u.id where u.id = ${friendId}`;
    const row = rows[0];
    return ok(c, {
      ...publicPlayer(row),
      layout: row.data.layout ?? null,
      menu: row.data.menu ?? null,
      jobs: row.data.jobs ?? null,
      plotCount: plotsFor(levelFor(row.gourmet_points)),
      plots: await plotsOf(sql, friendId),
    });
  });

  // WorldRestaurantPlay's visit: the first visit to a friend each day counts towards an award.
  routes.post('/:id/visit', async (c) => {
    const userId = c.get('userId');
    const friendId = await friendFrom(sql, userId, c.req.param('id'));
    const counted = await sql.begin(async (transaction) => {
      const added = await transaction`
        insert into friend_visits (visitor_id, host_id) values (${userId}, ${friendId})
        on conflict do nothing returning host_id`;
      if (added.length > 0) {
        await addAward(transaction, userId, Award.VISIT, 1);
      }
      return added.length > 0;
    });
    return ok(c, { counted });
  });

  // GardenPlotActor: watering a friend's plot helps it grow and earns the helper a coin,
  // once per plot per day.
  routes.post('/:id/water', async (c) => {
    const userId = c.get('userId');
    const friendId = await friendFrom(sql, userId, c.req.param('id'));
    const { plot } = await parseBody(c, plotBody);
    if (!(await plotsOf(sql, friendId)).some((entry) => entry.plot === plot)) {
      throw new ApiError(409, 'Nothing grows there');
    }
    const coins = await sql.begin(async (transaction) => {
      const first = await transaction`
        insert into friend_waterings (visitor_id, host_id, plot) values (${userId}, ${friendId}, ${plot})
        on conflict do nothing returning plot`;
      if (first.length === 0) {
        throw new ApiError(409, 'You have already watered that plot today');
      }
      const paid = await transaction<{ coins: string }[]>`
        update profiles set coins = coins + ${COINS_PER_FRIEND_WATERING} where user_id = ${userId} returning coins`;
      await addAward(transaction, userId, Award.TASK_HELP_FRIEND, 1);
      return Number(paid[0].coins);
    });
    await waterPlot(sql, friendId, plot);
    return ok(c, { coins });
  });

  return routes;
}

/** Mail between friends: gifts, ingredients, and messages. */
export function mailRoutes(sql: Sql): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();
  routes.use(requireAuth(sql));

  routes.get('/', async (c) => {
    const rows = await sql<{ id: string; kind: string; item_id: number | null; text: string; from_name: string | null; created_at: Date }[]>`
      select m.id, m.kind, m.item_id, m.text, u.username as from_name, m.created_at
      from mail m left join users u on u.id = m.from_id
      where m.to_id = ${c.get('userId')} and m.opened_at is null
      order by m.created_at`;
    return ok(c, {
      mail: rows.map((row) => ({
        id: Number(row.id),
        kind: row.kind,
        itemId: row.item_id,
        text: row.text,
        from: row.from_name,
        sentAt: row.created_at.toISOString(),
      })),
    });
  });

  routes.post('/send', async (c) => {
    const body = await parseBody(c, sendBody);
    const userId = c.get('userId');
    if (!(await areFriends(sql, userId, body.to))) {
      throw new ApiError(403, 'Only friends can do that');
    }
    await sql.begin(async (transaction) => {
      if (body.kind === 'gift') {
        // GiftPopUp: one free gift to each friend a day.
        const today = await transaction`
          select 1 from mail
          where from_id = ${userId} and to_id = ${body.to} and kind = 'gift' and created_at >= current_date`;
        if (today.length > 0) {
          throw new ApiError(409, 'You have already sent this friend a gift today');
        }
        const gift = GIFT_POOL[randomInt(GIFT_POOL.length)];
        await transaction`insert into mail (to_id, from_id, kind, item_id) values (${body.to}, ${userId}, 'gift', ${gift})`;
        await addAward(transaction, userId, Award.GIFT, 1);
      } else if (body.kind === 'ingredient') {
        // A trade: the ingredient leaves the sender's stock now.
        const used = await transaction`
          delete from owned_ingredients
          where user_id = ${userId} and ingredient_id = ${body.itemId} and quantity = 1 returning quantity`;
        const left = used.length > 0 ? used : await transaction`
          update owned_ingredients set quantity = quantity - 1
          where user_id = ${userId} and ingredient_id = ${body.itemId} and quantity > 1 returning quantity`;
        if (left.length === 0) {
          throw new ApiError(409, 'You do not have that ingredient');
        }
        await transaction`insert into mail (to_id, from_id, kind, item_id) values (${body.to}, ${userId}, 'ingredient', ${body.itemId})`;
        await addAward(transaction, userId, Award.TRADE, 1);
      } else {
        await transaction`insert into mail (to_id, from_id, kind, text) values (${body.to}, ${userId}, 'message', ${body.text})`;
      }
    });
    return ok(c, { sent: true });
  });

  // Opening a gift or an ingredient adds it to the recipient's ingredients.
  routes.post('/:id/open', async (c) => {
    const raw = c.req.param('id');
    if (!/^\d{1,18}$/.test(raw)) {
      throw new ApiError(404, 'No such mail');
    }
    const userId = c.get('userId');
    const opened = await sql.begin(async (transaction) => {
      const rows = await transaction<{ kind: string; item_id: number | null }[]>`
        update mail set opened_at = now()
        where id = ${raw} and to_id = ${userId} and opened_at is null
        returning kind, item_id`;
      const mail = rows[0];
      if (!mail) {
        throw new ApiError(404, 'No such mail');
      }
      if (mail.item_id !== null && mail.kind !== 'message') {
        await transaction`
          insert into owned_ingredients (user_id, ingredient_id, quantity) values (${userId}, ${mail.item_id}, 1)
          on conflict (user_id, ingredient_id) do update set quantity = owned_ingredients.quantity + 1`;
      }
      return { kind: mail.kind, itemId: mail.item_id };
    });
    return ok(c, opened);
  });

  return routes;
}
