import { readFile } from 'node:fs/promises';
import { z } from 'zod';
import { describeIssues } from './http.ts';

export type CatalogItem = { cost: number; purchasable: boolean };
/** Item id -> its price in coins and whether the shop sells it for coins. */
export type Catalog = ReadonlyMap<number, CatalogItem>;

// The shape tools/extract_data.py writes: groups of items whose numbers are strings.
const groupsSchema = z.array(
  z.object({
    items: z.array(
      z.object({
        id: z.string().regex(/^\d+$/),
        cost: z.string().regex(/^-?\d+$/),
        cash: z.string().regex(/^\d+$/).optional(),
        invisible: z.boolean().optional(),
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
      const purchasable = cost > 0 && Number(item.cash ?? '0') === 0 && item.invisible !== true;
      catalog.set(Number(item.id), { cost, purchasable });
    }
  }
  return catalog;
}

/**
 * Reads the catalog the game data was extracted to. The data is not distributed with the
 * repository, so a missing file is not fatal: the server runs with an empty catalog and
 * the shop reports that it is closed.
 */
export async function loadCatalog(path: string): Promise<Catalog> {
  let text: string;
  try {
    text = await readFile(path, 'utf8');
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      console.warn(`No item catalog at ${path}: the shop is closed. Run tools/extract_data.py to create it.`);
      return new Map();
    }
    throw error;
  }
  return parseCatalog(JSON.parse(text));
}
