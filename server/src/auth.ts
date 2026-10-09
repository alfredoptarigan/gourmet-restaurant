import { createHash, randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { Hono, type MiddlewareHandler } from 'hono';
import postgres from 'postgres';
import { z } from 'zod';
import type { Sql } from './db.ts';
import { ApiError, ok, parseBody } from './http.ts';

const PASSWORD_SCHEME = 'scrypt';
const SALT_BYTES = 16;
const KEY_BYTES = 64;
const TOKEN_BYTES = 32;
const SESSION_TTL_DAYS = 30;
const UNIQUE_VIOLATION = '23505';

const deriveKey = promisify(scrypt) as (password: string, salt: Buffer, keyLength: number) => Promise<Buffer>;

export type AuthEnv = { Variables: { userId: string; tokenHash: Buffer } };

const credentialsSchema = z.strictObject({
  username: z.string().regex(/^[A-Za-z0-9_]{3,20}$/, 'must be 3-20 letters, digits, or underscores'),
  password: z.string().min(8, 'must be at least 8 characters').max(128, 'must be at most 128 characters'),
});

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(SALT_BYTES);
  const key = await deriveKey(password, salt, KEY_BYTES);
  return [PASSWORD_SCHEME, salt.toString('base64'), key.toString('base64')].join('$');
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [scheme, salt, key] = stored.split('$');
  if (scheme !== PASSWORD_SCHEME || !salt || !key) {
    return false;
  }
  const expected = Buffer.from(key, 'base64');
  // A truncated hash must fail here: comparing two empty buffers would otherwise succeed.
  if (expected.length !== KEY_BYTES) {
    return false;
  }
  const actual = await deriveKey(password, Buffer.from(salt, 'base64'), KEY_BYTES);
  return timingSafeEqual(actual, expected);
}

// Checked when the username is unknown, so login takes the same time either way
// and does not reveal which usernames exist.
const unknownUserHash = hashPassword(randomBytes(TOKEN_BYTES).toString('hex'));

function hashToken(token: string): Buffer {
  return createHash('sha256').update(token).digest();
}

async function createSession(sql: Sql, userId: string): Promise<string> {
  const token = randomBytes(TOKEN_BYTES).toString('base64url');
  await sql`
    insert into sessions (token_hash, user_id, expires_at)
    values (${hashToken(token)}, ${userId}, now() + make_interval(days => ${SESSION_TTL_DAYS}))`;
  return token;
}

function isUniqueViolation(error: unknown): boolean {
  return error instanceof postgres.PostgresError && error.code === UNIQUE_VIOLATION;
}

export function requireAuth(sql: Sql): MiddlewareHandler<AuthEnv> {
  return async (c, next) => {
    const token = c.req.header('Authorization')?.match(/^Bearer (.+)$/)?.[1];
    if (!token) {
      throw new ApiError(401, 'Sign in required');
    }
    const tokenHash = hashToken(token);
    const sessions = await sql<{ user_id: string }[]>`
      select user_id from sessions where token_hash = ${tokenHash} and expires_at > now()`;
    const session: { user_id: string } | undefined = sessions[0];
    if (!session) {
      throw new ApiError(401, 'Session expired, sign in again');
    }
    c.set('userId', session.user_id);
    c.set('tokenHash', tokenHash);
    await next();
  };
}

export function authRoutes(sql: Sql): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();

  routes.post('/register', async (c) => {
    const { username, password } = await parseBody(c, credentialsSchema);
    const passwordHash = await hashPassword(password);
    const userId = await sql
      .begin(async (transaction) => {
        const users = await transaction<{ id: string }[]>`
          insert into users (username, password_hash) values (${username}, ${passwordHash}) returning id`;
        await transaction`insert into profiles (user_id) values (${users[0].id})`;
        return users[0].id;
      })
      .catch((error: unknown) => {
        if (isUniqueViolation(error)) {
          throw new ApiError(409, 'Username is already taken');
        }
        throw error;
      });
    return ok(c, { token: await createSession(sql, userId) }, 201);
  });

  routes.post('/login', async (c) => {
    const { username, password } = await parseBody(c, credentialsSchema);
    const users = await sql<{ id: string; password_hash: string }[]>`
      select id, password_hash from users where lower(username) = lower(${username})`;
    const user: { id: string; password_hash: string } | undefined = users[0];
    const passwordMatches = await verifyPassword(password, user?.password_hash ?? (await unknownUserHash));
    if (!user || !passwordMatches) {
      throw new ApiError(401, 'Wrong username or password');
    }
    await sql`delete from sessions where user_id = ${user.id} and expires_at <= now()`;
    return ok(c, { token: await createSession(sql, user.id) });
  });

  routes.post('/logout', requireAuth(sql), async (c) => {
    await sql`delete from sessions where token_hash = ${c.get('tokenHash')}`;
    return ok(c, { signedOut: true });
  });

  return routes;
}
