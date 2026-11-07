// The service client reconciles cached profile flags from current paid access.
// RPC errors never fall back to a formerly premium profile or client metadata.
export async function refreshPremiumAccess(
  client: { rpc: (name: string, args: { p_user_id: string }) => PromiseLike<{ data: unknown; error: unknown }> },
  userId: string,
): Promise<boolean> {
  const { data, error } = await client.rpc("refresh_user_entitlement", { p_user_id: userId });
  if (error || typeof data !== "boolean") throw new Error("Unable to verify subscription access");
  return data;
}
