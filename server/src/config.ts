import { z } from 'zod';
import { describeIssues } from './http.ts';

const DEFAULT_PORT = 3000;

const environmentSchema = z.object({
  DATABASE_URL: z.string({ error: 'is required' }).regex(/^postgres(ql)?:\/\//, 'must be a postgres:// URL'),
  PORT: z.coerce.number({ error: 'must be a number' }).int().min(1).max(65535).default(DEFAULT_PORT),
});

export type Config = { databaseUrl: string; port: number };

export function loadConfig(environment: Record<string, string | undefined> = process.env): Config {
  const result = environmentSchema.safeParse(environment);
  if (!result.success) {
    throw new Error(`Invalid configuration. ${describeIssues(result.error)}. See .env.example.`);
  }
  return { databaseUrl: result.data.DATABASE_URL, port: result.data.PORT };
}
