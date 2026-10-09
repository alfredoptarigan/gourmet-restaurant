import { readFile } from 'node:fs/promises';
import { z } from 'zod';
import { describeIssues } from './http.ts';

export type CatalogItem = { cost: number; purchasable: boolean; unlockLevel: number; consumable: boolean; outdoor: boolean };
/**
 * Item id -> its price in coins, whether the shop sells it for coins to keep, from which
 * level, and whether it is instead used up on the spot (food that restores staff energy).
 */
export type Catalog = ReadonlyMap<number, CatalogItem>;

// The shape tools/extract_data.py writes: groups of items whose numbers are strings.
const groupsSchema = z.array(
  z.object({
    types: z.array(z.string()).optional(),
    items: z.array(
      z.object({
        id: z.string().regex(/^\d+$/),
        cost: z.string().regex(/^-?\d+$/),
        cash: z.string().regex(/^\d+$/).optional(),
        invisible: z.boolean().optional(),
        unlockLevel: z.string().regex(/^\d+$/).optional(),
        workTime: z.string().regex(/^\d+$/).optional(),
        types: z.array(z.string()).optional(),
      }),
    ),
  }),
);

export function parseCatalog(groups: unknown): Catalog {
  const result = groupsSchema.safeParse(groups);
  if (!result.success) {
    throw new Error(`Item catalog is not in the expected shape. ${describeIssues(result.error)}`);
  }
  const catalog = new Map<number, CatalogItem>();
  for (const group of result.data) {
    for (const item of group.items) {
      const cost = Number(item.cost);
      // Awards cost nothing, some items are cash-only, and hidden items are never sold.
      const forCoins = cost > 0 && Number(item.cash ?? '0') === 0 && item.invisible !== true;
      const consumable = forCoins && Number(item.workTime ?? '0') > 0;
      catalog.set(Number(item.id), {
        cost,
        purchasable: forCoins && !consumable,
        unlockLevel: Number(item.unlockLevel ?? '0'),
        consumable,
        outdoor: [...(group.types ?? []), ...(item.types ?? [])].includes('outdoor'),
      });
    }
  }
  return catalog;
}

/**
 * Reads the catalog from the files the game data was extracted to (furniture, perks). The
 * data is not distributed with the repository, so a missing file is not fatal: with none of
 * them the server runs with an empty catalog and the shop reports that it is closed.
 */
export async function loadCatalog(...paths: string[]): Promise<Catalog> {
  const groups: unknown[] = [];
  for (const path of paths) {
    let text: string;
    try {
      text = await readFile(path, 'utf8');
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        console.warn(`No item catalog at ${path}. Run tools/extract_data.py to create it.`);
        continue;
      }
      throw error;
    }
    const parsed: unknown = JSON.parse(text);
    if (!Array.isArray(parsed)) {
      throw new Error(`Item catalog ${path} is not a list of groups`);
    }
    groups.push(...parsed);
  }
  return parseCatalog(groups);
}
