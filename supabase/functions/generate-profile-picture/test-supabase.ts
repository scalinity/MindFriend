// Function-local SDK boundary: all Auth/RPC calls are synthetic, and Storage
// passes through the test's fetch interceptor. No native SDK or network is loaded.
export const owner = "11111111-1111-4111-8111-111111111111";
export const other = "22222222-2222-4222-8222-222222222222";
type Row = Record<string, any>;
type Result = { data: any; error: any };
type Options = {
  global?: { headers?: Record<string, string>; fetch?: typeof fetch };
};

export const fixture = {
  user: { id: owner, is_anonymous: false } as Row | null,
  authError: null as unknown,
  quotaError: null as unknown,
  quotaCount: 0,
  quotaLimit: 5,
  budget: "reserved",
  atomic: true as unknown,
  atomicError: null as unknown,
  calls: [] as { name: string; admin: boolean; params?: Row }[],
  uploads: [] as {
    admin: boolean;
    key: string;
    path: string;
    bucket: string;
    options: Row;
    bytes: Uint8Array;
    headers?: Record<string, string>;
  }[],
  quotaReads: 0,
};

export function reset() {
  fixture.user = { id: owner, is_anonymous: false };
  fixture.authError = fixture.quotaError = fixture.atomicError = null;
  fixture.quotaCount = fixture.quotaReads = 0;
  fixture.quotaLimit = 5;
  fixture.budget = "reserved";
  fixture.atomic = true;
  fixture.calls = [];
  fixture.uploads = [];
}

export function createClient(url: string, key: string, options: Options = {}) {
  const admin = key === "synthetic-service-role";
  return {
    auth: {
      getUser(_token: string) {
        fixture.calls.push({ name: "auth", admin });
        return Promise.resolve({
          data: { user: fixture.user },
          error: fixture.authError,
        });
      },
    },
    rpc(name: string, params?: Row) {
      fixture.calls.push({ name, admin, params });
      let result: Result;
      if (name === "get_creative_quota") {
        fixture.quotaReads++;
        result = {
          data: [{
            ai_art_count: fixture.quotaCount,
            ai_art_limit: fixture.quotaLimit,
            is_premium: false,
          }],
          error: fixture.quotaError,
        };
      } else if (name === "reserve_ai_image_quota") {
        if (fixture.atomic === true && !fixture.atomicError) {
          fixture.quotaCount++;
        }
        result = { data: fixture.atomic, error: fixture.atomicError };
      } else if (name === "reserve_monthly_ai_budget") {
        if (!admin || params?.p_user_id !== owner) {
          throw new Error("Unexpected budget principal");
        }
        const exhausted = fixture.budget === "exhausted";
        result = fixture.budget === "error"
          ? { data: null, error: { message: "synthetic budget failure" } }
          : {
            data: {
              allowed: !exhausted,
              reason: fixture.budget,
              request_id: params.p_request_id,
              user_id: params.p_user_id,
              feature: params.p_feature,
              reserve_microdollars: params.p_reserve_microdollars,
              month_start: "2026-10-01",
              reserved_microdollars: exhausted
                ? 10_000_000
                : params.p_reserve_microdollars,
              limit_microdollars: 10_000_000,
              remaining_microdollars: exhausted
                ? 0
                : 10_000_000 - params.p_reserve_microdollars,
            },
            error: null,
          };
      } else throw new Error(`Unexpected RPC: ${name}`);
      const request = Promise.resolve(result);
      return Object.assign(request, {
        abortSignal(signal: AbortSignal) {
          signal.throwIfAborted();
          return request;
        },
      });
    },
    storage: {
      from(bucket: string) {
        return {
          async upload(path: string, bytes: Uint8Array, uploadOptions: Row) {
            fixture.uploads.push({
              admin,
              key,
              path,
              bucket,
              bytes,
              options: uploadOptions,
              headers: options.global?.headers,
            });
            const response = await (options.global?.fetch ?? fetch)(
              `${url}/storage/v1/object/${bucket}/${path}`,
              {
                method: "POST",
                headers: {
                  ...options.global?.headers,
                  "content-type": uploadOptions.contentType,
                  "x-upsert": String(uploadOptions.upsert),
                },
                body: new Uint8Array(bytes).buffer,
              },
            );
            await response.body?.cancel();
            return {
              data: response.ok ? { path } : null,
              error: response.ok ? null : {
                statusCode: String(response.status),
                message: "synthetic storage failure",
              },
            };
          },
          getPublicUrl(path: string) {
            return {
              data: {
                publicUrl: `${url}/storage/v1/object/public/${bucket}/${path}`,
              },
            };
          },
        };
      },
    },
    from() {
      throw new Error("Generation must not write profiles or tables");
    },
  };
}
