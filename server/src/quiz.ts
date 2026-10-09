import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Hono } from 'hono';
import { z } from 'zod';
import { requireAuth, type AuthEnv } from './auth.ts';
import type { Sql } from './db.ts';
import { ApiError, describeIssues, ok, parseBody } from './http.ts';

export type Question = { question: string; choices: string[]; correct: number; rewardIngredientId: number };

const quizItemSchema = z.object({
  question: z.string().min(1),
  reward: z.string().optional(),
  children: z.array(z.object({ attributes: z.object({ text: z.string(), correct: z.string().optional() }) })).min(2),
});
const groupsSchema = z.array(z.object({ items: z.array(z.unknown()) }));
const ingredientsSchema = z.array(z.object({ items: z.array(z.object({ id: z.string(), name: z.string() })) }));

/** quiz.json's questions, with each reward ingredient's name turned into its id. */
export function parseQuiz(quizGroups: unknown, ingredientGroups: unknown): Question[] {
  const idByName = new Map(ingredientsSchema.parse(ingredientGroups).flatMap((group) => group.items).map((item) => [item.name, Number(item.id)]));
  const questions: Question[] = [];
  for (const raw of groupsSchema.parse(quizGroups).flatMap((group) => group.items)) {
    const parsed = quizItemSchema.safeParse(raw);
    if (!parsed.success) {
      throw new Error(`A quiz question is not in the expected shape. ${describeIssues(parsed.error)}`);
    }
    const correct = parsed.data.children.findIndex((choice) => choice.attributes.correct === 'true');
    const rewardIngredientId = parsed.data.reward === undefined ? undefined : idByName.get(parsed.data.reward);
    // A question with no right answer or an unknown reward could never be answered fairly.
    if (correct !== -1 && rewardIngredientId !== undefined) {
      questions.push({
        question: parsed.data.question,
        choices: parsed.data.children.map((choice) => choice.attributes.text),
        correct,
        rewardIngredientId,
      });
    }
  }
  return questions;
}

export async function loadQuiz(dir: string): Promise<Question[]> {
  try {
    const [quiz, ingredients] = await Promise.all(
      ['quiz.json', 'ingredient.json'].map(async (name) => JSON.parse(await readFile(join(dir, name), 'utf8'))),
    );
    return parseQuiz(quiz, ingredients);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      console.warn(`No quiz in ${dir}. Run tools/extract_data.py.`);
      return [];
    }
    throw error;
  }
}

const answerBody = z.strictObject({ choice: z.number().int().min(0) });

/**
 * The daily quiz: one question a day, the same all day for a player, and a right answer pays
 * the question's ingredient. Days follow the server's clock in UTC.
 */
export function quizRoutes(sql: Sql, questions: readonly Question[]): Hono<AuthEnv> {
  const routes = new Hono<AuthEnv>();
  routes.use(requireAuth(sql));

  async function today(userId: string) {
    if (questions.length === 0) {
      throw new ApiError(503, 'There is no quiz on this server');
    }
    const rows = await sql<{ day: number; answered: boolean }[]>`
      select (current_date - date '2000-01-01') as day, coalesce(quiz_answered_on = current_date, false) as answered
      from profiles where user_id = ${userId}`;
    const { day, answered } = rows[0];
    // Players see different questions on the same day, and a new one each day.
    return { question: questions[(day + Number(userId) * 31) % questions.length], answered };
  }

  routes.get('/', async (c) => {
    const { question, answered } = await today(c.get('userId'));
    return ok(c, { question: question.question, choices: question.choices, rewardIngredientId: question.rewardIngredientId, answered });
  });

  routes.post('/answer', async (c) => {
    const { choice } = await parseBody(c, answerBody);
    const userId = c.get('userId');
    const { question } = await today(userId);
    if (choice >= question.choices.length) {
      throw new ApiError(400, 'choice: there is no such answer');
    }
    const correct = choice === question.correct;
    await sql.begin(async (transaction) => {
      // Only the first answer of the day counts, right or wrong.
      const marked = await transaction`
        update profiles set quiz_answered_on = current_date
        where user_id = ${userId} and quiz_answered_on is distinct from current_date
        returning user_id`;
      if (marked.length === 0) {
        throw new ApiError(409, "You have already answered today's question");
      }
      if (correct) {
        await transaction`
          insert into owned_ingredients (user_id, ingredient_id, quantity) values (${userId}, ${question.rewardIngredientId}, 1)
          on conflict (user_id, ingredient_id) do update set quantity = owned_ingredients.quantity + 1`;
      }
    });
    return ok(c, { correct, correctChoice: question.correct, rewardIngredientId: correct ? question.rewardIngredientId : null });
  });

  return routes;
}
