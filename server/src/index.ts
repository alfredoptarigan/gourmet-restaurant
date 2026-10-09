import { dirname, join } from 'node:path';
import { serve } from '@hono/node-server';
import { createApp } from './app.ts';
import { loadCatalog } from './catalog.ts';
import { loadConfig } from './config.ts';
import { loadCookbook } from './kitchen.ts';
import { loadQuiz } from './quiz.ts';
import { connect, migrate } from './db.ts';

const config = loadConfig();
const sql = connect(config.databaseUrl);

// ponytail: migrations run at startup, which is fine for a single instance.
// Make it a separate deploy step before running several instances at once.
for (const name of await migrate(sql)) {
  console.log(`Applied migration ${name}`);
}

// Perks (food for the staff) are extracted next to the furniture catalog.
const catalog = await loadCatalog(config.itemCatalogPath, join(dirname(config.itemCatalogPath), 'perk.json'));
console.log(`Item catalog: ${catalog.size} items`);
const cookbook = await loadCookbook(dirname(config.itemCatalogPath));
const quiz = await loadQuiz(dirname(config.itemCatalogPath));
console.log(`Quiz: ${quiz.length} questions`);
console.log(`Cookbook: ${cookbook.recipes.size} recipes, ${cookbook.ingredients.size} ingredients`);

serve({ fetch: createApp({ sql, catalog, cookbook, quiz }).fetch, port: config.port }, (info) => {
  console.log(`Gourmet Street server listening on http://localhost:${info.port}`);
});
