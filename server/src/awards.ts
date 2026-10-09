import { Hono } from 'hono';
import type postgres from 'postgres';
import { z } from 'zod';
import { requireAuth, type AuthEnv } from './auth.ts';
import type { Sql } from './db.ts';
import { ok, parseBody } from './http.ts';

// GameAwards.AWARD_*: what each award counts.
export const Award = {
  VISIT: 0,
  REMOVE_TRASH: 1,
  GIFT: 2,
  TRADE: 3,
  SPEND_COIN: 4,
  BUY_INDOOR_ITEM: 5,
  BUY_OUTDOOR_ITEM: 6,
  BUY_AVATAR_ITEM: 7,
  RECIPE_LEVEL_10: 8,
  RATE_COUNT: 11,
  HARVEST: 12,
  TASK_CLEAR_PLATE: 13,
  TASK_FIX_TOILET: 14,
  TASK_REPAIR_ITEM: 15,
  TASK_HELP_FRIEND: 16,
} as const;

// GameAwards.AWARD_PARAMS: the bronze, silver, and gold trophy of each award, and the count
// that earns it. The trophies are items of the Award group in restaurant.json.
export const AWARD_TIERS: Readonly<Record<number, readonly { target: number; itemId: number }[]>> = {
  0: [{ target: 100, itemId: 3400002 }, { target: 1000, itemId: 3400001 }, { target: 10000, itemId: 3400000 }],
  1: [{ target: 100, itemId: 3400023 }, { target: 1000, itemId: 3400022 }, { target: 10000, itemId: 3400021 }],
  2: [{ target: 50, itemId: 3400011 }, { target: 500, itemId: 3400010 }, { target: 5000, itemId: 3400009 }],
  3: [{ target: 50, itemId: 3400029 }, { target: 100, itemId: 3400028 }, { target: 5000, itemId: 3400027 }],
  4: [{ target: 2000, itemId: 3400008 }, { target: 20000, itemId: 3400007 }, { target: 200000, itemId: 3400006 }],
  5: [{ target: 10, itemId: 3400017 }, { target: 500, itemId: 3400016 }, { target: 2000, itemId: 3400015 }],
  6: [{ target: 10, itemId: 3400014 }, { target: 200, itemId: 3400013 }, { target: 500, itemId: 3400012 }],
  7: [{ target: 10, itemId: 3400020 }, { target: 100, itemId: 3400019 }, { target: 500, itemId: 3400018 }],
  8: [{ target: 1, itemId: 3400026 }, { target: 5, itemId: 3400025 }, { target: 20, itemId: 3400024 }],
  11: [{ target: 100, itemId: 3400005 }, { target: 1000, itemId: 3400004 }, { target: 10000, itemId: 3400003 }],
  12: [{ target: 10, itemId: 3400032 }, { target: 50, itemId: 3400031 }, { target: 200, itemId: 3400030 }],
  13: [{ target: 50, itemId: 3400035 }, { target: 500, itemId: 3400034 }, { target: 2000, itemId: 3400033 }],
  14: [{ target: 20, itemId: 3400038 }, { target: 200, itemId: 3400037 }, { target: 1000, itemId: 3400036 }],
  15: [{ target: 20, itemId: 3400041 }, { target: 200, itemId: 3400040 }, { target: 1000, itemId: 3400039 }],
  16: [{ target: 50, itemId: 3400044 }, { target: 250, itemId: 3400043 }, { target: 1000, itemId: 3400042 }],
};

// What the client may report itself: things that happen only in its simulation. Trophies
// carry no coins, so a false report earns nothing but a trophy.
const REPORTABLE: readonly number[] = [Award.REMOVE_TRASH, Award.TASK_FIX_TOILET, Award.TASK_REPAIR_ITEM];
const MAX_REPORTED = 100;

/**
 * GameAwards.addValue: counts towards an award and hands out every trophy whose target the
 * count has now reached. Returns the item ids of the new trophies.
 */
export async function addAward(
  transaction: postgres.TransactionSql,
  userId: string,
  award: number,
  amount: number,
): Promise<number[]> {
  if (amount <= 0) {
    return [];
  }
  const rows = await transaction<{ value: string }[]>`
    insert into award_progress (user_id, award, value) values (${userId}, ${award}, ${amount})
    on conflict (user_id, award) do update set value = award_progress.value + ${amount}
    returning value`;
  const after = Number(rows[0].value);
  const before = after - amount;
  const reached = (AWARD_TIERS[award] ?? []).filter((tier) => before < tier.target && after >= tier.target);
  if (reached.length > 0) {
    const trophies = reached.map((tier) => ({ user_id: userId, item_id: tier.itemId, quantity: 1 }));
    await transaction`insert into owned_items ${transaction(trophies)} on conflict (user_id, item_id) do nothing`;
  }
  return reached.map((tier) => tier.itemId);
}

const reportBody = z.strictObject({
  award: z.number().int().refine((award) => REPORTABLE.includes(award), 'cannot be reported'),
  amount: z.number().int().min(1).max(MAX_REPORTED),
});

export function awardRoutes(sql: Sql): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();
  routes.use(requireAuth(sql));

  routes.get('/', async (c) => {
    const rows = await sql<{ award: number; value: string }[]>`
      select award, value from award_progress where user_id = ${c.get('userId')}`;
    return ok(c, { progress: Object.fromEntries(rows.map((row) => [row.award, Number(row.value)])) });
  });

  routes.post('/progress', async (c) => {
    const { award, amount } = await parseBody(c, reportBody);
    const trophies = await sql.begin((transaction) => addAward(transaction, c.get('userId'), award, amount));
    return ok(c, { trophies });
  });

  return routes;
}
