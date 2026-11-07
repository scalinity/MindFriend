// Account records remain available for a retry until every owned object is gone.
const PAGE_SIZE = 100;
const USER_BUCKETS = new Set([
  "profile-pictures", "creative-works", "capsule-media", "mood-photos",
  "capsules", "voice-synthesis", "audio", "generated-audio",
]);

type Result<T> = { data: T | null; error: unknown };
type Entry = { name: string; id: string | null };
interface Bucket {
  list(path: string, options: {
    limit: number; offset: number; sortBy: { column: string; order: "asc" };
  }): Promise<Result<Entry[]>>;
  remove(paths: string[]): Promise<{ error: unknown }>;
}
export interface AccountStorage {
  listBuckets(options: { limit: number; offset: number }): Promise<Result<{ id: string }[]>>;
  from(bucket: string): Bucket;
}

async function listDirectory(bucket: Bucket, path: string): Promise<Entry[]> {
  const entries: Entry[] = [];
  for (let offset = 0;; offset += PAGE_SIZE) {
    const { data, error } = await bucket.list(path, {
      limit: PAGE_SIZE, offset, sortBy: { column: "name", order: "asc" },
    });
    if (error || !data) throw new Error("Account media listing failed");
    entries.push(...data);
    if (data.length < PAGE_SIZE) return entries;
  }
}

async function ownedPaths(bucket: Bucket, userId: string): Promise<string[]> {
  // Discover the actual prefix rather than guessing UUID casing. Existing iOS
  // uploads use uppercase UUIDs while server uploads normally use lowercase.
  const roots = await listDirectory(bucket, "");
  const directories = roots.filter((entry) =>
    entry.id === null && entry.name.toLowerCase() === userId.toLowerCase()
  ).map((entry) => entry.name);
  const files: string[] = [];
  while (directories.length) {
    const path = directories.pop()!;
    for (const entry of await listDirectory(bucket, path)) {
      const child = `${path}/${entry.name}`;
      if (entry.id === null) directories.push(child);
      else files.push(child);
    }
  }
  return files;
}

export async function deleteAccountMedia(storage: AccountStorage, userId: string): Promise<void> {
  const buckets: string[] = [];
  for (let offset = 0;; offset += PAGE_SIZE) {
    const { data, error } = await storage.listBuckets({ limit: PAGE_SIZE, offset });
    if (error || !data) throw new Error("Account media bucket listing failed");
    buckets.push(...data.filter((bucket) => USER_BUCKETS.has(bucket.id)).map((bucket) => bucket.id));
    if (data.length < PAGE_SIZE) break;
  }

  // Complete enumeration before mutating objects: deleting while paging by
  // offset would shift subsequent pages and silently skip files.
  const manifests = [];
  for (const name of buckets) {
    manifests.push({ bucket: storage.from(name), paths: await ownedPaths(storage.from(name), userId) });
  }
  for (const { bucket, paths } of manifests) {
    for (let offset = 0; offset < paths.length; offset += PAGE_SIZE) {
      const { error } = await bucket.remove(paths.slice(offset, offset + PAGE_SIZE));
      if (error) throw new Error("Account media removal failed");
    }
    if ((await ownedPaths(bucket, userId)).length !== 0) {
      throw new Error("Account media cleanup incomplete; retry deletion");
    }
  }
}
