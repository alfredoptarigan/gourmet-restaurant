import { readdir, readFile } from 'node:fs/promises';
import postgres from 'postgres';

export type Sql = postgres.Sql;

const MIGRATIONS_DIR = new URL('../migrations/', import.meta.url);

export function connect(databaseUrl: string): Sql {
  return postgres(databaseUrl, { onnotice: () => {} });
}

/** Applies migrations/*.sql in name order, each in its own transaction. Returns the names it applied. */
export async function migrate(sql: Sql): Promise<string[]> {
  await sql`
    create table if not exists schema_migrations (
      name text primary key,
      applied_at timestamptz not null default now()
    )`;
  const appliedRows = await sql<{ name: string }[]>`select name from schema_migrations`;
  const applied = new Set(appliedRows.map((row) => row.name));
  const fileNames = await readdir(MIGRATIONS_DIR);
  const pending = fileNames.filter((name) => name.endsWith('.sql') && !applied.has(name)).sort();
  for (const name of pending) {
    const statements = await readFile(new URL(name, MIGRATIONS_DIR), 'utf8');
    await sql.begin(async (transaction) => {
      await transaction.unsafe(statements);
      await transaction`insert into schema_migrations (name) values (${name})`;
    });
  }
  return pending;
}
