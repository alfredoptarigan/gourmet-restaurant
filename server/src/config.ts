import { z } from 'zod';
import { describeIssues } from './http.ts';

const DEFAULT_PORT = 3000;
// Written by tools/extract_data.py, one folder above server/.
const DEFAULT_ITEM_CATALOG_PATH = '../data/restaurant.json';

const environmentSchema = z.object({
  DATABASE_URL: z.string({ error: 'is required' }).regex(/^postgres(ql)?:\/\//, 'must be a postgres:// URL'),
  PORT: z.coerce.number({ error: 'must be a number' }).int().min(1).max(65535).default(DEFAULT_PORT),
  ITEM_CATALOG_PATH: z.string().min(1).default(DEFAULT_ITEM_CATALOG_PATH),
});

export type Config = { databaseUrl: string; port: number; itemCatalogPath: string };

export function loadConfig(environment: Record<string, string | undefined> = process.env): Config {
  const result = environmentSchema.safeParse(environment);
  if (!result.success) {
    throw new Error(`Invalid configuration. ${describeIssues(result.error)}. See .env.example.`);
  }
  return { databaseUrl: result.data.DATABASE_URL, port: result.data.PORT, itemCatalogPath: result.data.ITEM_CATALOG_PATH };
}
