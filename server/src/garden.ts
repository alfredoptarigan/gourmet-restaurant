import { randomInt } from 'node:crypto';
import { Hono } from 'hono';
import { z } from 'zod';
import { requireAuth, type AuthEnv } from './auth.ts';
import type { Sql } from './db.ts';
import { ApiError, ok, parseBody } from './http.ts';
import type { Cookbook } from './kitchen.ts';
import { levelFor } from './levels.ts';

// GardenPlot: a plant needs 48 wet hours, a watering keeps the soil wet for 3 hours, the soil
// holds at most 9 hours of water, and a seed costs 2000 coins.
export const GROW_SECONDS = 48 * 60 * 60;
const SECONDS_PER_WATER = 3 * 60 * 60;
const MAX_WET_SECONDS = 9 * 60 * 60;
const SEED_COST = 2000;
// GameWorld.LEVEL_THRESHOLDS gardenPlots: how many plots each level has, from level 1.
const PLOTS_PER_LEVEL = [
  0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8,
];
const MAX_PLOTS = 9;

export function plotsFor(level: number): number {
  return PLOTS_PER_LEVEL[level - 1] ?? MAX_PLOTS;
}

type PlotRow = { plot: number; ingredient_id: number; grown_seconds: number; since: number; wet_for: number };

/** A plot as it stands now: growth only counted while the soil was wet. */
function standing(row: PlotRow) {
  const grown = Math.min(GROW_SECONDS, row.grown_seconds + Math.max(0, Math.min(row.since, row.wet_for)));
  return {
    plot: row.plot,
    ingredientId: row.ingredient_id,
    grownSeconds: Math.round(grown),
    wetSeconds: Math.round(Math.max(0, row.wet_for - row.since)),
    ripe: grown >= GROW_SECONDS,
  };
}

const plotBody = z.strictObject({ plot: z.number().int().min(0).max(MAX_PLOTS - 1) });

export function gardenRoutes(sql: Sql, cookbook: Cookbook): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();
  routes.use(requireAuth(sql));
  const seeds = [...cookbook.plantable];

  async function plotsOf(userId: string) {
    const rows = await sql<PlotRow[]>`
      select plot, ingredient_id, grown_seconds,
             extract(epoch from now() - checked_at)::float8 as since,
             extract(epoch from wet_until - checked_at)::float8 as wet_for
      from garden_plots where user_id = ${userId} order by plot`;
    return rows.map(standing);
  }

  async function garden(userId: string) {
    const rows = await sql<{ gourmet_points: number }[]>`select gourmet_points from profiles where user_id = ${userId}`;
    return { plotCount: plotsFor(levelFor(rows[0]?.gourmet_points ?? 0)), plots: await plotsOf(userId) };
  }

  async function plotOf(userId: string, plot: number) {
    return (await plotsOf(userId)).find((entry) => entry.plot === plot);
  }

  routes.get('/', async (c) => ok(c, await garden(c.get('userId'))));

  // GardenPlot.plantSeed: a random plant, with the soil wet for one watering.
  routes.post('/plant', async (c) => {
    const { plot } = await parseBody(c, plotBody);
    const userId = c.get('userId');
    if (seeds.length === 0) {
      throw new ApiError(503, 'The garden is closed: the server has no plants');
    }
    if (plot >= (await garden(userId)).plotCount) {
      throw new ApiError(409, 'Your level does not have that plot yet');
    }
    await sql.begin(async (transaction) => {
      const paid = await transaction`
        update profiles set coins = coins - ${SEED_COST} where user_id = ${userId} and coins >= ${SEED_COST} returning coins`;
      if (paid.length === 0) {
        throw new ApiError(409, 'Not enough coins');
      }
      const planted = await transaction`
        insert into garden_plots (user_id, plot, ingredient_id, wet_until)
        values (${userId}, ${plot}, ${seeds[randomInt(seeds.length)]}, now() + make_interval(secs => ${SECONDS_PER_WATER}))
        on conflict do nothing returning plot`;
      if (planted.length === 0) {
        throw new ApiError(409, 'Something already grows there');
      }
    });
    return ok(c, await garden(userId));
  });

  routes.post('/water', async (c) => {
    const { plot } = await parseBody(c, plotBody);
    const userId = c.get('userId');
    const current = await plotOf(userId, plot);
    if (!current) {
      throw new ApiError(409, 'Nothing grows there');
    }
    // Growth so far is banked, and the wetness left gains one watering, up to the most the soil holds.
    const wet = Math.min(MAX_WET_SECONDS, current.wetSeconds + SECONDS_PER_WATER);
    await sql`
      update garden_plots
      set grown_seconds = ${current.grownSeconds}, checked_at = now(), wet_until = now() + make_interval(secs => ${wet})
      where user_id = ${userId} and plot = ${plot}`;
    return ok(c, await garden(userId));
  });

  // GardenPlot.harvest: a ripe plant becomes one of its ingredient.
  routes.post('/harvest', async (c) => {
    const { plot } = await parseBody(c, plotBody);
    const userId = c.get('userId');
    const harvested = await sql.begin(async (transaction) => {
      const current = await plotOf(userId, plot);
      if (!current?.ripe) {
        throw new ApiError(409, 'Nothing is ready to harvest there');
      }
      const removed = await transaction`delete from garden_plots where user_id = ${userId} and plot = ${plot} returning plot`;
      if (removed.length === 0) {
        throw new ApiError(409, 'Nothing is ready to harvest there');
      }
      await transaction`
        insert into owned_ingredients (user_id, ingredient_id, quantity) values (${userId}, ${current.ingredientId}, 1)
        on conflict (user_id, ingredient_id) do update set quantity = owned_ingredients.quantity + 1`;
      return current.ingredientId;
    });
    return ok(c, { ingredientId: harvested, ...(await garden(userId)) });
  });

  return routes;
}
