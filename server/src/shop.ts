import { Hono } from 'hono';
import type postgres from 'postgres';
import { z } from 'zod';
import { requireAuth, type AuthEnv } from './auth.ts';
import type { Catalog } from './catalog.ts';
import type { Sql } from './db.ts';
import { ApiError, ok, parseBody } from './http.ts';
import { levelFor } from './levels.ts';

// GameWorld.getSellPrice: an item sells for a third of what it cost.
const SELL_PRICE_DIVISOR = 3;
const MAX_LAYOUT_ITEMS = 500;
// WorldRestaurant.MAX_NUM_TILES_X / Y bound where anything can stand.
const MAX_TILE_X = 19;
const MAX_TILE_Y = 39;

const placedItemSchema = z.strictObject({
  id: z.number().int().min(1),
  x: z.number().int().min(0).max(MAX_TILE_X),
  y: z.number().int().min(0).max(MAX_TILE_Y),
  rotation: z.number().int().min(0).max(3),
});

export const layoutSchema = z.strictObject({
  items: z.array(placedItemSchema).max(MAX_LAYOUT_ITEMS),
  floor: z.number().int().min(1),
  wallpaper: z.number().int().min(1),
});

export type Layout = z.infer<typeof layoutSchema>;

// WorldRestaurant.DEFAULT_RESTAURANT_ITEMS: the restaurant every new player starts with.
const STOVE = 3070000;
const DOOR = 3010000;
const WINDOW = 3000011;
const CHAIR = 3040001;
const TABLE = 3030010;
const ACHIEVEMENT_PANEL = 3200000;
const LETTER_BOX = 3300000;
const MENU_HOLDER = 3100000;
const BUSH = 3020003;
const WOOD_FLOOR = 3050000;
const BLUE_WALLPAPER = 3060016;

export const STARTER_LAYOUT: Layout = {
  items: [
    { id: STOVE, x: 6, y: 2, rotation: 3 },
    { id: DOOR, x: 0, y: 4, rotation: 0 },
    { id: WINDOW, x: 0, y: 2, rotation: 0 },
    { id: WINDOW, x: 0, y: 6, rotation: 0 },
    { id: CHAIR, x: 2, y: 3, rotation: 0 },
    { id: CHAIR, x: 2, y: 5, rotation: 0 },
    { id: CHAIR, x: 5, y: 5, rotation: 0 },
    { id: TABLE, x: 3, y: 3, rotation: 0 },
    { id: TABLE, x: 3, y: 5, rotation: 0 },
    { id: TABLE, x: 6, y: 5, rotation: 0 },
    { id: ACHIEVEMENT_PANEL, x: 2, y: 0, rotation: 1 },
    { id: LETTER_BOX, x: 1, y: 7, rotation: 0 },
    { id: MENU_HOLDER, x: 4, y: 0, rotation: 1 },
    { id: BUSH, x: 1, y: 1, rotation: 0 },
    { id: BUSH, x: 7, y: 1, rotation: 0 },
    { id: BUSH, x: 7, y: 7, rotation: 0 },
  ],
  floor: WOOD_FLOOR,
  wallpaper: BLUE_WALLPAPER,
};

/** How many of each item a layout uses, counting its floor and its wallpaper once each. */
export function countPlaced(layout: Layout): Map<number, number> {
  const placed = new Map<number, number>();
  for (const id of [...layout.items.map((item) => item.id), layout.floor, layout.wallpaper]) {
    placed.set(id, (placed.get(id) ?? 0) + 1);
  }
  return placed;
}

/** Gives a new player everything the starting restaurant is furnished with. */
export async function grantStarterItems(transaction: postgres.TransactionSql, userId: string): Promise<void> {
  const rows = [...countPlaced(STARTER_LAYOUT)].map(([itemId, quantity]) => ({
    user_id: userId,
    item_id: itemId,
    quantity,
  }));
  await transaction`insert into owned_items ${transaction(rows)} on conflict (user_id, item_id) do nothing`;
}

async function ownedQuantities(sql: Sql | postgres.TransactionSql, userId: string): Promise<Map<number, number>> {
  const rows = await sql<{ item_id: number; quantity: number }[]>`
    select item_id, quantity from owned_items where user_id = ${userId}`;
  return new Map(rows.map((row) => [row.item_id, row.quantity]));
}

/** Throws unless the player owns every item the layout places. */
export async function assertLayoutIsOwned(sql: Sql | postgres.TransactionSql, userId: string, layout: Layout): Promise<void> {
  const owned = await ownedQuantities(sql, userId);
  for (const [itemId, placed] of countPlaced(layout)) {
    if (placed > (owned.get(itemId) ?? 0)) {
      throw new ApiError(409, `The layout uses item ${itemId} more often than you own it`);
    }
  }
}

const itemSchema = z.strictObject({ itemId: z.number().int().min(1) });

export function shopRoutes(sql: Sql, catalog: Catalog): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();
  routes.use(requireAuth(sql));

  function priced(itemId: number) {
    if (catalog.size === 0) {
      throw new ApiError(503, 'The shop is closed: the server has no item catalog');
    }
    const item = catalog.get(itemId);
    if (!item) {
      throw new ApiError(404, 'No such item');
    }
    return item;
  }

  routes.get('/inventory', async (c) => {
    const owned = await ownedQuantities(sql, c.get('userId'));
    return ok(c, { items: Object.fromEntries(owned) });
  });

  routes.post('/buy', async (c) => {
    const { itemId } = await parseBody(c, itemSchema);
    const item = priced(itemId);
    if (!item.purchasable) {
      throw new ApiError(404, 'This item is not for sale');
    }
    const userId = c.get('userId');
    const result = await sql.begin(async (transaction) => {
      if (item.unlockLevel > 1) {
        const rows = await transaction<{ gourmet_points: number }[]>`
          select gourmet_points from profiles where user_id = ${userId}`;
        if (levelFor(rows[0]?.gourmet_points ?? 0) < item.unlockLevel) {
          throw new ApiError(409, `Reach level ${item.unlockLevel} to buy this`);
        }
      }
      // The price is taken only if the balance covers it; no row back means it did not.
      const paid = await transaction<{ coins: string }[]>`
        update profiles set coins = coins - ${item.cost}
        where user_id = ${userId} and coins >= ${item.cost}
        returning coins`;
      if (paid.length === 0) {
        throw new ApiError(409, 'Not enough coins');
      }
      const owned = await transaction<{ quantity: number }[]>`
        insert into owned_items (user_id, item_id, quantity) values (${userId}, ${itemId}, 1)
        on conflict (user_id, item_id) do update set quantity = owned_items.quantity + 1
        returning quantity`;
      return { coins: Number(paid[0].coins), quantity: owned[0].quantity };
    });
    return ok(c, result);
  });

  // Food for the staff is paid for and used up at once: nothing is added to the inventory.
  // The energy it restores lives in the client's simulation, like the staff themselves.
  routes.post('/use', async (c) => {
    const { itemId } = await parseBody(c, itemSchema);
    const item = priced(itemId);
    if (!item.consumable) {
      throw new ApiError(404, 'This item cannot be used');
    }
    const paid = await sql<{ coins: string }[]>`
      update profiles set coins = coins - ${item.cost}
      where user_id = ${c.get('userId')} and coins >= ${item.cost}
      returning coins`;
    if (paid.length === 0) {
      throw new ApiError(409, 'Not enough coins');
    }
    return ok(c, { coins: Number(paid[0].coins) });
  });

  routes.post('/sell', async (c) => {
    const { itemId } = await parseBody(c, itemSchema);
    const item = priced(itemId);
    const userId = c.get('userId');
    const result = await sql.begin(async (transaction) => {
      const profiles = await transaction<{ layout: unknown }[]>`
        select data -> 'layout' as layout from profiles where user_id = ${userId} for update`;
      const layout = layoutSchema.safeParse(profiles[0]?.layout);
      const placed = layout.success ? (countPlaced(layout.data).get(itemId) ?? 0) : 0;
      const owned = (await ownedQuantities(transaction, userId)).get(itemId) ?? 0;
      if (owned === 0) {
        throw new ApiError(409, 'You do not own this item');
      }
      if (owned <= placed) {
        throw new ApiError(409, 'Put the item away before selling it');
      }
      if (owned === 1) {
        await transaction`delete from owned_items where user_id = ${userId} and item_id = ${itemId}`;
      } else {
        await transaction`
          update owned_items set quantity = quantity - 1 where user_id = ${userId} and item_id = ${itemId}`;
      }
      const paid = await transaction<{ coins: string }[]>`
        update profiles set coins = coins + ${Math.floor(item.cost / SELL_PRICE_DIVISOR)}
        where user_id = ${userId}
        returning coins`;
      return { coins: Number(paid[0].coins), quantity: owned - 1 };
    });
    return ok(c, result);
  });

  return routes;
}
