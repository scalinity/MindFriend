import { refreshPremiumAccess } from "./entitlement.ts";

Deno.test("premium access trusts only a successful boolean entitlement result", async () => {
  for (const value of [true, false]) {
    const actual = await refreshPremiumAccess({ rpc(name, args) {
      if (name !== "refresh_user_entitlement" || args.p_user_id !== "owner") throw new Error("wrong RPC");
      return Promise.resolve({ data: value, error: null });
    } }, "owner");
    if (actual !== value) throw new Error("incorrect access");
  }
  for (const result of [{ data: true, error: {} }, { data: null, error: null }, { data: "true", error: null }, { data: [true], error: null }]) {
    let rejected = false;
    try { await refreshPremiumAccess({ rpc: () => Promise.resolve(result) }, "owner"); }
    catch { rejected = true; }
    if (!rejected) throw new Error("unverified result granted access");
  }
});
