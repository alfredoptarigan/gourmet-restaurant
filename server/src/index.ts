import { serve } from '@hono/node-server';
import { createApp } from './app.ts';
import { loadConfig } from './config.ts';
import { connect, migrate } from './db.ts';

const config = loadConfig();
const sql = connect(config.databaseUrl);

// ponytail: migrations run at startup, which is fine for a single instance.
// Make it a separate deploy step before running several instances at once.
for (const name of await migrate(sql)) {
  console.log(`Applied migration ${name}`);
}

serve({ fetch: createApp({ sql }).fetch, port: config.port }, (info) => {
  console.log(`Gourmet Street server listening on http://localhost:${info.port}`);
});
