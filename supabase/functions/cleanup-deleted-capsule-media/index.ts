// Cleanup Deleted Capsule Media Cron Function
// Runs daily to delete soft-deleted media files from Storage and database
// Triggered by: cron schedule (daily at 3 AM UTC)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { logError, createErrorResponse } from "../_shared/error-logger.ts";

interface DeletedMedia {
  id: string;
  storage_path: string;
  deleted_at: string;
}

serve(async (_req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Find media soft-deleted more than 30 days ago (grace period)
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

    const { data: deletedMedia, error: fetchError } = await supabase
      .from("capsule_media")
      .select("id, storage_path, deleted_at")
      .not("deleted_at", "is", null)
      .lt("deleted_at", thirtyDaysAgo.toISOString())
      .limit(100); // Process 100 per run to avoid timeouts

    if (fetchError) {
      logError(
        {
          function: "cleanup-deleted-capsule-media",
          operation: "fetch_deleted_media",
        },
        fetchError,
      );
      return createErrorResponse(fetchError);
    }

    if (!deletedMedia || deletedMedia.length === 0) {
      console.log("No orphaned media to clean up");
      return new Response(
        JSON.stringify({ cleaned: 0, message: "No orphaned media found" }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    console.log(`Processing ${deletedMedia.length} orphaned media files`);

    let successCount = 0;
    let failureCount = 0;
    const errors: Array<{ mediaId: string; error: string }> = [];

    for (const media of deletedMedia as DeletedMedia[]) {
      try {
        // Delete from Supabase Storage
        const { error: storageError } = await supabase.storage
          .from("capsule-media")
          .remove([media.storage_path]);

        if (storageError) {
          logError(
            {
              function: "cleanup-deleted-capsule-media",
              operation: "delete_storage_file",
              metadata: { mediaId: media.id, path: media.storage_path },
            },
            storageError,
          );
          errors.push({
            mediaId: media.id,
            error: `Storage deletion failed: ${storageError.message}`,
          });
          failureCount++;
          continue;
        }

        // Hard-delete database record (after successful Storage deletion)
        const { error: dbError } = await supabase
          .from("capsule_media")
          .delete()
          .eq("id", media.id);

        if (dbError) {
          logError(
            {
              function: "cleanup-deleted-capsule-media",
              operation: "delete_db_record",
              metadata: { mediaId: media.id },
            },
            dbError,
          );
          errors.push({
            mediaId: media.id,
            error: `DB deletion failed: ${dbError.message}`,
          });
          failureCount++;
          continue;
        }

        successCount++;
      } catch (error) {
        logError(
          {
            function: "cleanup-deleted-capsule-media",
            operation: "process_media_file",
            metadata: { mediaId: media.id },
          },
          error,
        );
        errors.push({
          mediaId: media.id,
          error: error instanceof Error ? error.message : "Unknown error",
        });
        failureCount++;
      }
    }

    console.log(
      `Cleanup complete: ${successCount} deleted, ${failureCount} failed`,
    );

    return new Response(
      JSON.stringify({
        cleaned: successCount,
        failed: failureCount,
        total: deletedMedia.length,
        errors: errors.length > 0 ? errors : undefined,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    logError(
      {
        function: "cleanup-deleted-capsule-media",
        operation: "cron_execution",
      },
      error,
    );
    return createErrorResponse(error);
  }
});
