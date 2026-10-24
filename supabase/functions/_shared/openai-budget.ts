import {
  type MonthlyAIBudgetAdmin,
  reserveMonthlyAIBudget,
} from "./monthly-ai-budget.ts";

export function openAIBudgetReservation(
  client: MonthlyAIBudgetAdmin,
  userId: string,
  feature: "chat.response" | "chat.title" | "chat.memory",
  signal?: AbortSignal,
) {
  return async (microdollars: number): Promise<boolean> => {
    // Each callback invocation precedes a distinct submission, even on a new
    // client attempt. Chat receipt UUIDs must never authorize provider replay.
    await reserveMonthlyAIBudget(client, {
      requestId: crypto.randomUUID(),
      userId,
      feature,
      reserveMicrodollars: microdollars,
    }, signal);
    return true;
  };
}
