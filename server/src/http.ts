import type { Context } from 'hono';
import type { ContentfulStatusCode } from 'hono/utils/http-status';
import type { z } from 'zod';

/** An error whose message is safe to show to the client. Anything else becomes a 500. */
export class ApiError extends Error {
  status: ContentfulStatusCode;

  constructor(status: ContentfulStatusCode, message: string) {
    super(message);
    this.status = status;
  }
}

// Every response uses the same envelope: { success, data, error }.
export function ok<T>(c: Context, data: T, status: ContentfulStatusCode = 200) {
  return c.json({ success: true, data, error: null }, status);
}

export function fail(c: Context, status: ContentfulStatusCode, error: string) {
  return c.json({ success: false, data: null, error }, status);
}

export async function parseBody<Schema extends z.ZodType>(c: Context, schema: Schema): Promise<z.infer<Schema>> {
  // Malformed JSON becomes undefined, which the schema then rejects like any other bad body.
  const body: unknown = await c.req.json().catch(() => undefined);
  const result = schema.safeParse(body);
  if (!result.success) {
    throw new ApiError(400, describeIssues(result.error));
  }
  return result.data;
}

export function describeIssues(error: z.ZodError): string {
  return error.issues.map((issue) => `${issue.path.join('.') || 'body'}: ${issue.message}`).join('; ');
}
