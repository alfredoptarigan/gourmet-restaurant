import { Hono } from 'hono';
import { authRoutes } from './auth.ts';
import { awardRoutes } from './awards.ts';
import type { Catalog } from './catalog.ts';
import type { Sql } from './db.ts';
import { foodKingRoutes, type Reward } from './foodking.ts';
import { gardenRoutes } from './garden.ts';
import { ApiError, fail, ok } from './http.ts';
import { kitchenRoutes, type Cookbook } from './kitchen.ts';
import { profileRoutes } from './profile.ts';
import { quizRoutes, type Question } from './quiz.ts';
import { rateLimit } from './rate-limit.ts';
import { shopRoutes } from './shop.ts';
import { mailRoutes, socialRoutes } from './social.ts';

const DEFAULT_AUTH_RATE_LIMIT = { limit: 10, windowMs: 60_000 };

const EMPTY_COOKBOOK: Cookbook = { recipes: new Map(), ingredients: new Map(), plantable: new Set() };

export type AppOptions = {
  sql: Sql;
  catalog: Catalog;
  cookbook?: Cookbook;
  quiz?: readonly Question[];
  foodKingRewards?: readonly Reward[];
  /** One Food King visit in this many player-days. */
  foodKingChance?: number;
  authRateLimit?: { limit: number; windowMs: number };
};

export function createApp({ sql, catalog, cookbook = EMPTY_COOKBOOK, quiz = [], foodKingRewards = [], foodKingChance, authRateLimit = DEFAULT_AUTH_RATE_LIMIT }: AppOptions): Hono {
  const app = new Hono();

  app.onError((error, c) => {
    if (error instanceof ApiError) {
      return fail(c, error.status, error.message);
    }
    // Details go to the server log only; the client gets a generic message.
    console.error(`${c.req.method} ${c.req.path} failed:`, error);
    return fail(c, 500, 'Internal server error');
  });
  app.notFound((c) => fail(c, 404, 'Not found'));

  app.get('/health', async (c) => {
    await sql`select 1`;
    return ok(c, { status: 'ok' });
  });
  app.get('/time', (c) => ok(c, { now: Date.now() }));

  app.use('/auth/*', rateLimit(authRateLimit.limit, authRateLimit.windowMs));
  app.route('/auth', authRoutes(sql));
  app.route('/profile', profileRoutes(sql));
  app.route('/shop', shopRoutes(sql, catalog));
  app.route('/kitchen', kitchenRoutes(sql, cookbook));
  app.route('/garden', gardenRoutes(sql, cookbook));
  app.route('/awards', awardRoutes(sql));
  app.route('/quiz', quizRoutes(sql, quiz));
  app.route('/friends', socialRoutes(sql));
  app.route('/mail', mailRoutes(sql));
  app.route('/foodking', foodKingRoutes(sql, foodKingRewards, foodKingChance));

  return app;
}
