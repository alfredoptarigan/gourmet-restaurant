import { getConnInfo } from '@hono/node-server/conninfo';
import type { Context, MiddlewareHandler } from 'hono';
import { fail } from './http.ts';

const DEFAULT_MAX_TRACKED_CLIENTS = 10_000;
const UNKNOWN_CLIENT = 'unknown';

type RequestWindow = { startedAt: number; count: number };

/** Fixed-window counter: each client gets `limit` requests per `windowMs`. */
export function createRateLimiter(
  limit: number,
  windowMs: number,
  now: () => number = Date.now,
  maxTrackedClients: number = DEFAULT_MAX_TRACKED_CLIENTS,
): (client: string) => boolean {
  // ponytail: in-memory, so the limit is per server process and resets on restart.
  // Move the counters to PostgreSQL or Redis when running more than one instance.
  const windows = new Map<string, RequestWindow>();

  function forgetEndedWindows(current: number): void {
    for (const [client, window] of windows) {
      if (current - window.startedAt >= windowMs) {
        windows.delete(client);
      }
    }
  }

  return function isAllowed(client: string): boolean {
    const current = now();
    const window = windows.get(client);
    if (window && current - window.startedAt < windowMs) {
      windows.set(client, { startedAt: window.startedAt, count: window.count + 1 });
      return window.count + 1 <= limit;
    }
    if (windows.size >= maxTrackedClients) {
      forgetEndedWindows(current);
    }
    windows.set(client, { startedAt: current, count: 1 });
    return true;
  };
}

function clientAddress(c: Context): string {
  // ponytail: this is the socket address. Behind a reverse proxy every player shares the
  // proxy's address, so read the proxy's forwarded-for header here once one is deployed.
  try {
    return getConnInfo(c).remote.address ?? UNKNOWN_CLIENT;
  } catch {
    // No socket (app.request() in tests): count all such requests as one client.
    return UNKNOWN_CLIENT;
  }
}

export function rateLimit(limit: number, windowMs: number): MiddlewareHandler {
  const isAllowed = createRateLimiter(limit, windowMs);
  return async (c, next) => {
    if (!isAllowed(clientAddress(c))) {
      return fail(c, 429, 'Too many attempts, try again in a minute');
    }
    await next();
  };
}
