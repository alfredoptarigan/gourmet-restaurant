import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Hono } from 'hono';
import type postgres from 'postgres';
import { z } from 'zod';
import { requireAuth, type AuthEnv } from './auth.ts';
import type { Sql } from './db.ts';
import { ApiError, describeIssues, ok, parseBody } from './http.ts';
import { levelFor, rewardBetween } from './levels.ts';
import { Award, addAward } from './awards.ts';

// WorldRecipeMenu.RECIPE_LEVEL_NAMES runs from Simple (1) to Royal (10).
export const MAX_RECIPE_LEVEL = 10;
// GameWorld.GOURMET_POINTS_PER_LEARN_RECIPE_LEVEL: what reaching each recipe level is worth.
const POINTS_PER_RECIPE_LEVEL = [25, 50, 100, 200, 300, 400, 500, 600, 700, 800];
// The coin market of the reference server: an ingredient's cash price of 4, 6, or 8 sells
// for 1000, 1500, or 2000 coins.
const COINS_PER_CASH_PRICE = new Map([
  [4, 1000],
  [6, 1500],
  [8, 2000],
]);
// The three dishes and seven ingredients a new player starts with (the reference server's
// STARTER_RECIPES, and the ingredients flagged `initial` in ingredient.json with that count).
const STARTER_RECIPES = [5000008, 5100003, 5200000];
const STARTER_INGREDIENTS = new Map([
  [4000005, 1],
  [4000013, 2],
  [4000031, 1],
  [4000034, 2],
  [4000036, 1],
  [4000040, 2],
  [4000047, 1],
]);

export type Cookbook = {
  /** Recipe id -> ingredient id -> how many one level takes, and whether it can still be learned. */
  recipes: ReadonlyMap<number, { ingredients: ReadonlyMap<number, number>; learnable: boolean }>;
  /** Ingredient id -> its coin price, or null when the coin market does not sell it. */
  ingredients: ReadonlyMap<number, number | null>;
  /** The ingredients that grow from a garden seed. */
  plantable: ReadonlySet<number>;
};

const groupsSchema = z.array(z.object({ items: z.array(z.record(z.string(), z.unknown())) }));
const ingredientSchema = z.object({
  id: z.string().regex(/^\d+$/),
  name: z.string(),
  cash: z.string().regex(/^\d+$/),
  noCoinShop: z.boolean().optional(),
  plantClassName: z.string().optional(),
});
const recipeSchema = z.object({
  id: z.string().regex(/^\d+$/),
  ingredients: z.string(),
  invisible: z.boolean().optional(),
  expireDate: z.string().optional(),
});

function items<T extends z.ZodType>(groups: unknown, schema: T, what: string): z.infer<T>[] {
  const parsed = z.array(schema).safeParse(groupsSchema.parse(groups).flatMap((group) => group.items));
  if (!parsed.success) {
    throw new Error(`${what} are not in the expected shape. ${describeIssues(parsed.error)}`);
  }
  return parsed.data;
}

export function parseCookbook(recipeGroups: unknown, ingredientGroups: unknown): Cookbook {
  const idByName = new Map<string, number>();
  const ingredients = new Map<number, number | null>();
  const plantable = new Set<number>();
  for (const item of items(ingredientGroups, ingredientSchema, 'Ingredients')) {
    idByName.set(item.name, Number(item.id));
    if (item.plantClassName) {
      plantable.add(Number(item.id));
    }
    ingredients.set(Number(item.id), item.noCoinShop ? null : (COINS_PER_CASH_PRICE.get(Number(item.cash)) ?? null));
  }
  const recipes = new Map<number, { ingredients: Map<number, number>; learnable: boolean }>();
  for (const item of items(recipeGroups, recipeSchema, 'Recipes')) {
    const needed = new Map<number, number>();
    // Recipe's constructor: a comma-separated list, a name listed twice is needed twice, and
    // a name with no ingredient behind it is skipped.
    for (const name of item.ingredients.split(/\s*,\s*/)) {
      const id = idByName.get(name);
      if (id !== undefined) {
        needed.set(id, (needed.get(id) ?? 0) + 1);
      }
    }
    // Hidden and limited-time recipes can be kept and improved, but no longer learned.
    recipes.set(Number(item.id), { ingredients: needed, learnable: !item.invisible && !item.expireDate });
  }
  return { recipes, ingredients, plantable };
}

/** Reads recipe.json and ingredient.json from `dir`; an empty cookbook if they are missing. */
export async function loadCookbook(dir: string): Promise<Cookbook> {
  try {
    const [recipes, ingredients] = await Promise.all(
      ['recipe.json', 'ingredient.json'].map(async (name) => JSON.parse(await readFile(join(dir, name), 'utf8'))),
    );
    return parseCookbook(recipes, ingredients);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      console.warn(`No recipes or ingredients in ${dir}: the kitchen is closed. Run tools/extract_data.py.`);
      return { recipes: new Map(), ingredients: new Map(), plantable: new Set() };
    }
    throw error;
  }
}

const recipeBody = z.strictObject({ recipeId: z.number().int().min(1) });
const ingredientBody = z.strictObject({ ingredientId: z.number().int().min(1) });

type Transaction = postgres.TransactionSql;

async function kitchenOf(sql: Sql | Transaction, userId: string) {
  const recipes = await sql<{ recipe_id: number; level: number }[]>`
    select recipe_id, level from known_recipes where user_id = ${userId}`;
  const ingredients = await sql<{ ingredient_id: number; quantity: number }[]>`
    select ingredient_id, quantity from owned_ingredients where user_id = ${userId}`;
  return {
    recipes: Object.fromEntries(recipes.map((row) => [row.recipe_id, row.level])),
    ingredients: Object.fromEntries(ingredients.map((row) => [row.ingredient_id, row.quantity])),
  };
}

export function kitchenRoutes(sql: Sql, cookbook: Cookbook): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();
  routes.use(requireAuth(sql));

  function assertOpen() {
    if (cookbook.recipes.size === 0) {
      throw new ApiError(503, 'The kitchen is closed: the server has no recipes');
    }
  }

  routes.get('/', async (c) => {
    const userId = c.get('userId');
    // A player never loses recipes, so knowing none means the starting ones were never
    // given: a new account, or one made before the kitchen existed.
    await sql.begin(async (transaction) => {
      const [{ count }] = await transaction<{ count: number }[]>`
        select count(*)::int as count from known_recipes where user_id = ${userId}`;
      if (count > 0) {
        return;
      }
      const recipes = STARTER_RECIPES.map((recipe_id) => ({ user_id: userId, recipe_id, level: 1 }));
      const ingredients = [...STARTER_INGREDIENTS].map(([ingredient_id, quantity]) => ({ user_id: userId, ingredient_id, quantity }));
      await transaction`insert into known_recipes ${transaction(recipes)} on conflict do nothing`;
      await transaction`insert into owned_ingredients ${transaction(ingredients)} on conflict do nothing`;
    });
    return ok(c, await kitchenOf(sql, userId));
  });

  // WorldRecipeMenu.levelUpRecipeInPanel: one set of the recipe's ingredients learns it, or
  // takes it a level higher, and earns gourmet points.
  routes.post('/learn', async (c) => {
    assertOpen();
    const { recipeId } = await parseBody(c, recipeBody);
    const recipe = cookbook.recipes.get(recipeId);
    if (!recipe) {
      throw new ApiError(404, 'No such recipe');
    }
    const userId = c.get('userId');
    const result = await sql.begin(async (transaction) => {
      const profiles = await transaction<{ coins: string; gourmet_points: number }[]>`
        select coins, gourmet_points from profiles where user_id = ${userId} for update`;
      const before = profiles[0];
      if (!before) {
        throw new ApiError(404, 'Profile not found');
      }
      const known = await transaction<{ level: number }[]>`
        select level from known_recipes where user_id = ${userId} and recipe_id = ${recipeId}`;
      const level = (known[0]?.level ?? 0) + 1;
      if (level > MAX_RECIPE_LEVEL) {
        throw new ApiError(409, 'This recipe is already at the highest level');
      }
      if (level === 1 && !recipe.learnable) {
        throw new ApiError(409, 'This recipe can no longer be learned');
      }
      for (const [ingredientId, needed] of recipe.ingredients) {
        // The last of an ingredient removes its row: a held quantity is never zero.
        const used = await transaction`
          delete from owned_ingredients
          where user_id = ${userId} and ingredient_id = ${ingredientId} and quantity = ${needed}
          returning quantity`;
        const left = used.length > 0 ? used : await transaction`
          update owned_ingredients set quantity = quantity - ${needed}
          where user_id = ${userId} and ingredient_id = ${ingredientId} and quantity > ${needed}
          returning quantity`;
        if (left.length === 0) {
          throw new ApiError(409, 'You do not have the ingredients for this recipe');
        }
      }
      await transaction`
        insert into known_recipes (user_id, recipe_id, level) values (${userId}, ${recipeId}, ${level})
        on conflict (user_id, recipe_id) do update set level = ${level}`;
      if (level === MAX_RECIPE_LEVEL) {
        await addAward(transaction, userId, Award.RECIPE_LEVEL_10, 1);
      }
      const gourmetPoints = before.gourmet_points + POINTS_PER_RECIPE_LEVEL[level - 1];
      const levelUpReward = rewardBetween(levelFor(before.gourmet_points), levelFor(gourmetPoints));
      const coins = Number(before.coins) + levelUpReward;
      await transaction`
        update profiles set gourmet_points = ${gourmetPoints}, coins = ${coins} where user_id = ${userId}`;
      return { level, gourmetPoints, coins, playerLevel: levelFor(gourmetPoints), levelUpReward, ...(await kitchenOf(transaction, userId)) };
    });
    return ok(c, result);
  });

  // ponytail: every coin-market ingredient is on sale every day. The original market shows
  // three a day, and sells the rest for cash.
  routes.post('/buy-ingredient', async (c) => {
    assertOpen();
    const { ingredientId } = await parseBody(c, ingredientBody);
    if (!cookbook.ingredients.has(ingredientId)) {
      throw new ApiError(404, 'No such ingredient');
    }
    const price = cookbook.ingredients.get(ingredientId);
    if (price == null) {
      throw new ApiError(404, 'This ingredient is not sold for coins');
    }
    const userId = c.get('userId');
    const result = await sql.begin(async (transaction) => {
      const paid = await transaction<{ coins: string }[]>`
        update profiles set coins = coins - ${price}
        where user_id = ${userId} and coins >= ${price}
        returning coins`;
      if (paid.length === 0) {
        throw new ApiError(409, 'Not enough coins');
      }
      const owned = await transaction<{ quantity: number }[]>`
        insert into owned_ingredients (user_id, ingredient_id, quantity) values (${userId}, ${ingredientId}, 1)
        on conflict (user_id, ingredient_id) do update set quantity = owned_ingredients.quantity + 1
        returning quantity`;
      await addAward(transaction, userId, Award.SPEND_COIN, price);
      return { coins: Number(paid[0].coins), quantity: owned[0].quantity };
    });
    return ok(c, result);
  });

  return routes;
}
