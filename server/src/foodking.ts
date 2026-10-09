import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Hono } from 'hono';
import type postgres from 'postgres';
import { z } from 'zod';
import { requireAuth, type AuthEnv } from './auth.ts';
import type { Sql } from './db.ts';
import { ApiError, ok, parseBody } from './http.ts';

export type Reward = { kind: 'ingredient' | 'item' | 'recipe'; id: number };

// FoodKing.chanceOfAppearing: one visit in twenty.
export const DEFAULT_VISIT_CHANCE = 20;
const OFFERED = 3;
const groupsSchema = z.array(z.object({ items: z.array(z.object({ id: z.string(), foodKingFeed: z.boolean().optional() }).passthrough()) }));

/** The things marked `foodKingFeed` in the data: what Greg can bring. */
export function parseRewards(files: { kind: Reward['kind']; groups: unknown }[]): Reward[] {
  return files.flatMap(({ kind, groups }) =>
    groupsSchema
      .parse(groups)
      .flatMap((group) => group.items)
      .filter((item) => item.foodKingFeed)
      .map((item) => ({ kind, id: Number(item.id) })),
  );
}

export async function loadRewards(dir: string): Promise<Reward[]> {
  const files: [Reward['kind'], string][] = [
    ['item', 'restaurant.json'],
    ['ingredient', 'ingredient.json'],
    ['recipe', 'recipe.json'],
  ];
  try {
    return parseRewards(
      await Promise.all(files.map(async ([kind, name]) => ({ kind, groups: JSON.parse(await readFile(join(dir, name), 'utf8')) }))),
    );
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      console.warn(`No Food King rewards in ${dir}. Run tools/extract_data.py.`);
      return [];
    }
    throw error;
  }
}

/** A number that stays the same for a player all day and changes from day to day. */
function dailyRoll(userId: string, day: number): number {
  return Math.abs((day * 7919 + Number(userId) * 104729) % 1_000_003);
}

async function grant(transaction: postgres.TransactionSql, userId: string, reward: Reward): Promise<void> {
  if (reward.kind === 'ingredient') {
    await transaction`
      insert into owned_ingredients (user_id, ingredient_id, quantity) values (${userId}, ${reward.id}, 1)
      on conflict (user_id, ingredient_id) do update set quantity = owned_ingredients.quantity + 1`;
  } else if (reward.kind === 'item') {
    await transaction`
      insert into owned_items (user_id, item_id, quantity) values (${userId}, ${reward.id}, 1)
      on conflict (user_id, item_id) do update set quantity = owned_items.quantity + 1`;
  } else {
    // A recipe is learned at level 1; one already known stays as it is.
    await transaction`
      insert into known_recipes (user_id, recipe_id, level) values (${userId}, ${reward.id}, 1)
      on conflict do nothing`;
  }
}

const claimBody = z.strictObject({ choice: z.number().int().min(0).max(OFFERED - 1) });

/**
 * Greg, the Food King: on some days he visits a player's restaurant, and finding him lets
 * the player pick one of three rewards. Days follow the server's clock in UTC.
 */
export function foodKingRoutes(sql: Sql, rewards: readonly Reward[], visitChance = DEFAULT_VISIT_CHANCE): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();
  routes.use(requireAuth(sql));

  async function today(userId: string) {
    const rows = await sql<{ day: number; claimed: boolean }[]>`
      select (current_date - date '2000-01-01') as day, coalesce(foodking_claimed_on = current_date, false) as claimed
      from profiles where user_id = ${userId}`;
    const { day, claimed } = rows[0];
    const roll = dailyRoll(userId, day);
    const offered: Reward[] = [];
    for (let index = 0; rewards.length > 0 && offered.length < Math.min(OFFERED, rewards.length); index += 1) {
      const reward = rewards[(roll + index * 37) % rewards.length];
      if (!offered.includes(reward)) {
        offered.push(reward);
      }
    }
    return { visiting: rewards.length > 0 && roll % visitChance === 0, claimed, rewards: offered };
  }

  routes.get('/', async (c) => ok(c, await today(c.get('userId'))));

  routes.post('/claim', async (c) => {
    const { choice } = await parseBody(c, claimBody);
    const userId = c.get('userId');
    const { visiting, rewards: offered } = await today(userId);
    if (!visiting) {
      throw new ApiError(409, 'The Food King is not visiting today');
    }
    const reward = offered[choice];
    if (!reward) {
      throw new ApiError(400, 'choice: there is no such reward');
    }
    await sql.begin(async (transaction) => {
      const marked = await transaction`
        update profiles set foodking_claimed_on = current_date
        where user_id = ${userId} and foodking_claimed_on is distinct from current_date
        returning user_id`;
      if (marked.length === 0) {
        throw new ApiError(409, 'You have already found the Food King today');
      }
      await grant(transaction, userId, reward);
    });
    return ok(c, { reward });
  });

  return routes;
}
