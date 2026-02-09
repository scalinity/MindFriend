---
description: "Instructions for Supabase Edge Functions"
applyTo: "supabase/functions/**/*.ts"
---

# Edge Functions Guidelines

## Standard Function Structure

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  // CORS handling
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    // Initialize Supabase client with service role
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Validate JWT token
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }

    // Parse request body
    const body = await req.json();

    // Business logic here
    const result = await processRequest(supabase, user, body);

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Function error:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Internal server error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
```

## Authentication

### JWT Validation (Required)
```typescript
// Always validate the JWT token
const authHeader = req.headers.get("Authorization");
if (!authHeader) {
  return new Response("Unauthorized", { status: 401 });
}

const token = authHeader.replace("Bearer ", "");
const {
  data: { user },
  error,
} = await supabase.auth.getUser(token);

if (error || !user) {
  return new Response("Unauthorized", { status: 401 });
}
```

### Service Role vs Anon Key
```typescript
// For user-scoped operations, use service role with RLS
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// RLS will still be enforced when you pass the user's token
const { data } = await supabase
  .from("table")
  .select()
  .eq("user_id", user.id);
```

## Database Operations

### Query Patterns
```typescript
// Select with filters
const { data: quests, error } = await supabase
  .from("quests")
  .select("*, quest_templates(*)")
  .eq("user_id", userId)
  .order("created_at", { ascending: false })
  .limit(10);

if (error) throw error;

// Insert
const { data: newMood, error: insertError } = await supabase
  .from("moods")
  .insert({
    user_id: userId,
    rating: 4,
    notes: "Feeling good",
  })
  .select()
  .single();

// Update
const { error: updateError } = await supabase
  .from("quests")
  .update({ completed: true, completed_at: new Date().toISOString() })
  .eq("id", questId)
  .eq("user_id", userId); // Always scope to user for security

// Upsert
const { error: upsertError } = await supabase
  .from("user_settings")
  .upsert({
    user_id: userId,
    notifications_enabled: true,
  })
  .eq("user_id", userId);
```

### Transactions
```typescript
// Use RPC for transactions
const { data, error } = await supabase.rpc("complete_quest_with_streak", {
  p_quest_id: questId,
  p_user_id: userId,
});
```

## AI Integration

### xAI (Grok) API Calls
```typescript
const XAI_API_KEY = Deno.env.get("XAI_API_KEY");

async function callGrok(messages: any[]) {
  const response = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${XAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: "grok-beta",
      messages,
      stream: false, // or true for streaming
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Grok API error: ${error}`);
  }

  return await response.json();
}
```

### Safety and Guardrails
```typescript
import { detectSelfHarm } from "../_shared/pattern-detection.ts";

// Check for crisis content BEFORE calling AI
if (detectSelfHarm(userMessage)) {
  // Log crisis event
  await supabase.from("crisis_events").insert({
    user_id: userId,
    trigger_type: "self_harm_detected",
    message_content: userMessage,
    created_at: new Date().toISOString(),
  });

  // Return crisis template response
  return {
    response: "I'm concerned about what you've shared...",
    is_crisis_response: true,
  };
}
```

## Push Notifications

### APNs Integration
```typescript
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID");
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID");
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY"); // base64 encoded

async function sendAPNs(deviceToken: string, payload: any) {
  const jwt = await generateAPNsJWT();

  const response = await fetch(
    `https://api.push.apple.com/3/device/${deviceToken}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwt}`,
        "apns-topic": "com.mindfriend.app",
        "apns-priority": "10",
      },
      body: JSON.stringify(payload),
    }
  );

  if (!response.ok) {
    throw new Error(`APNs error: ${response.statusText}`);
  }
}
```

### Notification Scheduling
```typescript
// Check quiet hours before sending
const { data: settings } = await supabase
  .from("user_settings")
  .select("quiet_hours_start, quiet_hours_end")
  .eq("user_id", userId)
  .single();

const now = new Date();
const hour = now.getHours();

if (settings) {
  const start = parseInt(settings.quiet_hours_start);
  const end = parseInt(settings.quiet_hours_end);

  if (hour >= start || hour < end) {
    console.log("Within quiet hours, skipping notification");
    return;
  }
}

await sendNotification(userId, message);
```

## StoreKit Verification

### App Store Server API
```typescript
const APP_STORE_ISSUER_ID = Deno.env.get("APP_STORE_ISSUER_ID");
const APP_STORE_KEY_ID = Deno.env.get("APP_STORE_KEY_ID");
const APP_STORE_PRIVATE_KEY = Deno.env.get("APP_STORE_PRIVATE_KEY");

async function verifyTransaction(originalTransactionId: string) {
  const jwt = await generateAppStoreJWT();

  const response = await fetch(
    `https://api.storekit.itunes.apple.com/inApps/v1/transactions/${originalTransactionId}`,
    {
      headers: {
        Authorization: `Bearer ${jwt}`,
      },
    }
  );

  if (!response.ok) {
    throw new Error("Transaction verification failed");
  }

  const data = await response.json();
  return data;
}
```

### Update Subscription Status
```typescript
const transactionInfo = await verifyTransaction(originalTransactionId);

// Update or insert subscription
await supabase.from("subscriptions").upsert({
  user_id: userId,
  original_transaction_id: originalTransactionId,
  product_id: transactionInfo.productId,
  expires_at: new Date(transactionInfo.expiresDate),
  is_active: true,
  updated_at: new Date().toISOString(),
});
```

## Error Handling

### Structured Error Responses
```typescript
interface ErrorResponse {
  error: string;
  code?: string;
  details?: any;
}

function errorResponse(
  message: string,
  status: number = 500,
  code?: string
): Response {
  return new Response(
    JSON.stringify({
      error: message,
      code,
    } as ErrorResponse),
    {
      status,
      headers: { "Content-Type": "application/json" },
    }
  );
}

// Usage
if (!body.conversationId) {
  return errorResponse("Missing conversationId", 400, "MISSING_PARAM");
}
```

### Logging
```typescript
// Use console for logging (appears in Supabase logs)
console.log("Processing request for user:", user.id);
console.error("Database error:", error);

// Include context in errors
try {
  await processData();
} catch (error) {
  console.error("Failed to process data", {
    userId: user.id,
    error: error.message,
    stack: error.stack,
  });
  throw error;
}
```

## Testing

### Test File Structure
```typescript
// supabase/functions/my-function/test.ts
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

Deno.test("Function name - should do something", async () => {
  // Arrange
  const mockRequest = new Request("http://localhost", {
    method: "POST",
    headers: {
      Authorization: "Bearer mock-token",
    },
    body: JSON.stringify({ test: "data" }),
  });

  // Act
  const response = await handler(mockRequest);

  // Assert
  assertEquals(response.status, 200);
  const data = await response.json();
  assertEquals(data.success, true);
});
```

### Mocking Supabase
```typescript
// Create mock Supabase client
const mockSupabase = {
  auth: {
    getUser: () => Promise.resolve({ data: { user: { id: "test-user" } } }),
  },
  from: (table: string) => ({
    select: () => ({
      eq: () => ({
        single: () => Promise.resolve({ data: mockData, error: null }),
      }),
    }),
  }),
};
```

## Shared Utilities

### Use _shared Directory
```typescript
// supabase/functions/_shared/auth.ts
export async function validateUser(req: Request, supabase: any) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    throw new Error("Missing authorization");
  }

  const token = authHeader.replace("Bearer ", "");
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser(token);

  if (error || !user) {
    throw new Error("Invalid token");
  }

  return user;
}

// Usage in function
import { validateUser } from "../_shared/auth.ts";

const user = await validateUser(req, supabase);
```

## Performance

### Database Connection Pooling
```typescript
// Supabase client handles connection pooling automatically
// Reuse the same client instance when possible
let supabaseClient: any;

function getSupabaseClient() {
  if (!supabaseClient) {
    supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
  }
  return supabaseClient;
}
```

### Batch Operations
```typescript
// Insert multiple records at once
const { error } = await supabase.from("notifications").insert([
  { user_id: user1, message: "..." },
  { user_id: user2, message: "..." },
  { user_id: user3, message: "..." },
]);
```

## Common Pitfalls to Avoid

- ❌ Don't expose service role key to clients
- ❌ Don't skip JWT validation
- ❌ Don't forget to handle CORS preflight requests
- ❌ Don't return sensitive data (passwords, tokens) in responses
- ❌ Don't perform heavy computations synchronously (use background tasks)
- ❌ Don't hardcode user IDs (always get from validated JWT)
- ❌ Don't skip error handling for external API calls

## Environment Variables

### Required Variables
```typescript
// Always validate required environment variables
const XAI_API_KEY = Deno.env.get("XAI_API_KEY");
if (!XAI_API_KEY) {
  throw new Error("XAI_API_KEY environment variable is required");
}
```

### Secrets Management
- Store secrets in Supabase Dashboard (Settings → Edge Functions → Secrets)
- Never commit secrets to code
- Use base64 encoding for multi-line secrets (private keys)

## Remember

- **Always** validate JWT tokens
- **Never** expose service role key to clients
- **Test** edge cases and error conditions
- **Log** errors with sufficient context
- **Handle** CORS properly for browser requests
- **Validate** input data before processing
