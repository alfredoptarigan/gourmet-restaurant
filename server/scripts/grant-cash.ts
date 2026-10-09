// Gives a player cash, for testing or support, and writes it to the cash ledger.
// Usage: node scripts/grant-cash.ts <username> <amount> [reason]
// Reads DATABASE_URL like the server (see .env.example).
import { grantCash } from '../src/cash.ts';
import { loadConfig } from '../src/config.ts';
import { connect } from '../src/db.ts';

const [username, rawAmount, reason = 'admin grant'] = process.argv.slice(2);
const amount = Number(rawAmount);
if (!username || !Number.isSafeInteger(amount) || amount <= 0) {
  console.error('Usage: node scripts/grant-cash.ts <username> <amount> [reason]');
  process.exit(2);
}

const sql = connect(loadConfig().databaseUrl);
try {
  const users = await sql<{ id: string }[]>`select id from users where lower(username) = lower(${username})`;
  if (users.length === 0) {
    console.error(`No player named ${username}`);
    process.exitCode = 1;
  } else {
    const balance = await sql.begin((transaction) => grantCash(transaction, users[0].id, amount, `admin: ${reason}`));
    console.log(`${username} now has ${balance} cash`);
  }
} finally {
  await sql.end();
}
