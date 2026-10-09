import { Hono } from 'hono';
import type postgres from 'postgres';
import { z } from 'zod';
import { requireAuth, type AuthEnv } from './auth.ts';
import type { Catalog } from './catalog.ts';
import type { Sql } from './db.ts';
import { ApiError, ok, parseBody } from './http.ts';

/**
 * Cash is the paid currency. Only the server changes it, and every change is written to
 * cash_ledger with the balance after it, so any balance can be accounted for.
 */
export async function spendCash(transaction: postgres.TransactionSql, userId: string, amount: number, reason: string): Promise<number> {
  const paid = await transaction<{ cash: string }[]>`
    update profiles set cash = cash - ${amount} where user_id = ${userId} and cash >= ${amount} returning cash`;
  if (paid.length === 0) {
    throw new ApiError(409, 'Not enough cash');
  }
  const balance = Number(paid[0].cash);
  await transaction`
    insert into cash_ledger (user_id, amount, balance, reason) values (${userId}, ${-amount}, ${balance}, ${reason})`;
  return balance;
}

/** Adds cash: what a payment bought, or an admin grant. */
export async function grantCash(transaction: postgres.TransactionSql, userId: string, amount: number, reason: string): Promise<number> {
  if (!Number.isSafeInteger(amount) || amount <= 0) {
    throw new Error(`A cash grant must be a positive whole number, got ${amount}`);
  }
  const rows = await transaction<{ cash: string }[]>`
    update profiles set cash = cash + ${amount} where user_id = ${userId} returning cash`;
  if (rows.length === 0) {
    throw new Error(`No profile for user ${userId}`);
  }
  const balance = Number(rows[0].cash);
  await transaction`
    insert into cash_ledger (user_id, amount, balance, reason) values (${userId}, ${amount}, ${balance}, ${reason})`;
  return balance;
}

const itemBody = z.strictObject({ itemId: z.number().int().min(1) });

export function cashRoutes(sql: Sql, catalog: Catalog): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();
  routes.use(requireAuth(sql));

  routes.get('/', async (c) => {
    const rows = await sql<{ cash: string }[]>`select cash from profiles where user_id = ${c.get('userId')}`;
    return ok(c, { cash: Number(rows[0]?.cash ?? 0), checkout: false });
  });

  // The money bags of the CoinsToPfCash group: cash turned into coins.
  routes.post('/exchange', async (c) => {
    const { itemId } = await parseBody(c, itemBody);
    const bag = catalog.get(itemId);
    if (!bag?.coinsForCash || !bag.cashPrice) {
      throw new ApiError(404, 'That is not a money bag');
    }
    const price = bag.cashPrice;
    const coinsGiven = bag.coinsForCash;
    const userId = c.get('userId');
    const result = await sql.begin(async (transaction) => {
      const cash = await spendCash(transaction, userId, price, `exchange:${itemId}`);
      const rows = await transaction<{ coins: string }[]>`
        update profiles set coins = coins + ${coinsGiven} where user_id = ${userId} returning coins`;
      return { cash, coins: Number(rows[0].coins) };
    });
    return ok(c, result);
  });

  // ponytail: cash cannot be bought yet. Stripe Checkout goes here: create a session for a
  // package, and grant the cash from its webhook with grantCash, never from the client.
  routes.post('/checkout', () => {
    throw new ApiError(501, 'Buying cash is not available yet');
  });

  return routes;
}
