# Grok Voice Agent API Documentation

Technical reference for implementing real-time voice conversations using the xAI Grok Voice Agent API.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Authentication](#authentication)
4. [Quick Start](#quick-start)
5. [Session Configuration](#session-configuration)
6. [Voice Options](#voice-options)
7. [Audio Formats](#audio-formats)
8. [Message Protocol](#message-protocol)
9. [Tool Integration](#tool-integration)
10. [Custom Functions](#custom-functions)
11. [Turn Detection](#turn-detection)
12. [Implementation Examples](#implementation-examples)
13. [Architecture Patterns](#architecture-patterns)
14. [Best Practices](#best-practices)
15. [Troubleshooting](#troubleshooting)
16. [API Reference](#api-reference)

---

## Overview

The Grok Voice Agent API enables real-time bidirectional voice conversations through WebSocket connections. The API accepts both audio and text inputs and delivers synchronized text and audio responses.

### Key Capabilities

- **Real-time voice conversations** - Minimal latency for natural dialogue flow
- **Multilingual support** - 100+ languages with automatic language detection
- **Tool integration** - Web search, X (Twitter) search, document collections, and custom functions
- **Voice personalities** - Five distinct voice options for different use cases
- **Flexible audio formats** - PCM and G.711 codec support with configurable sample rates
- **Turn detection** - Server-side VAD (Voice Activity Detection) or manual control

### WebSocket Endpoint

```
wss://api.x.ai/v1/realtime
```

---

## Prerequisites

Before implementing the Grok Voice Agent API, ensure you have:

1. **xAI API Key** - Obtain from the [xAI Developer Portal](https://console.x.ai)
2. **WebSocket Client** - Native browser WebSocket or a library like `ws` for Node.js
3. **Audio Handling** - Ability to capture and play audio in your target platform
4. **HTTPS/WSS Environment** - Secure connections required for production

### Development Environment

```bash
# Node.js (for server-side implementations)
npm install ws

# Browser applications
# Native WebSocket API available - no installation required
```

---

## Authentication

The API supports two authentication methods. Choose based on your architecture.

### Method 1: Ephemeral Tokens (Recommended for Client-Side)

Generate temporary access credentials for client-side applications. This prevents exposing your API key to end users.

**Step 1: Request an ephemeral token from your backend**

```typescript
// Server-side: Generate ephemeral token
async function generateEphemeralToken(): Promise<string> {
  const response = await fetch("https://api.x.ai/v1/realtime/client_secrets", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.XAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      expires_in: 300, // Token valid for 5 minutes
    }),
  });

  if (!response.ok) {
    throw new Error(`Token generation failed: ${response.status}`);
  }

  const data = await response.json();
  return data.client_secret;
}
```

**Step 2: Use the ephemeral token in WebSocket connection**

```typescript
// Client-side: Connect using ephemeral token
const token = await fetchTokenFromBackend(); // Your API endpoint
const ws = new WebSocket(`wss://api.x.ai/v1/realtime?token=${token}`);
```

**Ephemeral Token Response Schema:**

```json
{
  "client_secret": "eph_xxxxxxxxxxxxxxxxxxxx",
  "expires_at": "2024-01-15T10:05:00Z"
}
```

### Method 2: Direct API Key (Server-Only)

For server-side applications where the API key remains secure.

```typescript
// Server-side only - NEVER expose in client code
const ws = new WebSocket("wss://api.x.ai/v1/realtime", {
  headers: {
    Authorization: `Bearer ${process.env.XAI_API_KEY}`,
  },
});
```

> **Security Warning:** Never embed your xAI API key in client-side code, mobile applications, or any code that ships to end users. Use ephemeral tokens for all client-facing implementations.

---

## Quick Start

Minimal working example to establish a voice session and exchange messages.

```typescript
// quick-start.ts
const WebSocket = require("ws");

async function startVoiceSession() {
  // Connect to the API
  const ws = new WebSocket("wss://api.x.ai/v1/realtime", {
    headers: {
      Authorization: `Bearer ${process.env.XAI_API_KEY}`,
    },
  });

  ws.on("open", () => {
    console.log("Connected to Grok Voice Agent");

    // Configure the session
    ws.send(
      JSON.stringify({
        type: "session.update",
        session: {
          instructions: "You are a helpful voice assistant.",
          voice: "ara",
          turn_detection: {
            type: "server_vad",
          },
          audio: {
            input: {
              format: { type: "audio/pcm", rate: 24000 },
            },
            output: {
              format: { type: "audio/pcm", rate: 24000 },
            },
          },
        },
      }),
    );
  });

  ws.on("message", (data: Buffer) => {
    const event = JSON.parse(data.toString());

    switch (event.type) {
      case "session.updated":
        console.log("Session configured successfully");
        break;
      case "response.output_audio.delta":
        // Handle audio chunk (base64 encoded)
        handleAudioChunk(event.delta);
        break;
      case "response.output_audio_transcript.delta":
        // Handle transcription text
        console.log("Transcript:", event.delta);
        break;
      case "error":
        console.error("Error:", event.error);
        break;
    }
  });

  ws.on("error", (error: Error) => {
    console.error("WebSocket error:", error);
  });

  ws.on("close", () => {
    console.log("Connection closed");
  });

  return ws;
}

function handleAudioChunk(base64Audio: string) {
  const audioBuffer = Buffer.from(base64Audio, "base64");
  // Process or play the audio buffer
}

startVoiceSession();
```

---

## Session Configuration

Configure session parameters using the `session.update` message. All parameters are optional; unspecified values use defaults.

### Configuration Schema

```json
{
  "type": "session.update",
  "session": {
    "instructions": "string",
    "voice": "ara | rex | sal | eve | leo",
    "turn_detection": {
      "type": "server_vad | null"
    },
    "audio": {
      "input": {
        "format": {
          "type": "audio/pcm | audio/pcmu | audio/pcma",
          "rate": 8000 | 16000 | 21050 | 24000 | 32000 | 44100 | 48000
        }
      },
      "output": {
        "format": {
          "type": "audio/pcm | audio/pcmu | audio/pcma",
          "rate": 8000 | 16000 | 21050 | 24000 | 32000 | 44100 | 48000
        }
      }
    },
    "tools": []
  }
}
```

### Parameter Reference

| Parameter                  | Type           | Default        | Description                               |
| -------------------------- | -------------- | -------------- | ----------------------------------------- |
| `instructions`             | string         | `""`           | System prompt defining assistant behavior |
| `voice`                    | string         | `"ara"`        | Voice personality identifier              |
| `turn_detection.type`      | string \| null | `"server_vad"` | Turn detection mode                       |
| `audio.input.format.type`  | string         | `"audio/pcm"`  | Input audio codec                         |
| `audio.input.format.rate`  | number         | `24000`        | Input sample rate (Hz)                    |
| `audio.output.format.type` | string         | `"audio/pcm"`  | Output audio codec                        |
| `audio.output.format.rate` | number         | `24000`        | Output sample rate (Hz)                   |
| `tools`                    | array          | `[]`           | Enabled tools and functions               |

### Example: Detailed Session Configuration

```typescript
const sessionConfig = {
  type: "session.update",
  session: {
    instructions: `You are a friendly customer service agent for a software company.
      - Be concise and helpful
      - Ask clarifying questions when needed
      - Escalate to human support for billing issues`,
    voice: "ara",
    turn_detection: {
      type: "server_vad",
    },
    audio: {
      input: {
        format: { type: "audio/pcm", rate: 16000 },
      },
      output: {
        format: { type: "audio/pcm", rate: 24000 },
      },
    },
    tools: [
      { type: "web_search" },
      {
        type: "function",
        function: {
          name: "lookup_order",
          description: "Look up order status by order ID",
          parameters: {
            type: "object",
            properties: {
              order_id: { type: "string", description: "The order ID" },
            },
            required: ["order_id"],
          },
        },
      },
    ],
  },
};

ws.send(JSON.stringify(sessionConfig));
```

---

## Voice Options

Five distinct voice personalities are available. Select using the `voice` parameter in session configuration.

| Voice   | Gender  | Profile                                | Best For                               |
| ------- | ------- | -------------------------------------- | -------------------------------------- |
| **ara** | Female  | Warm, conversational, approachable     | General assistance, customer service   |
| **rex** | Male    | Professional, clear, confident         | Business applications, formal contexts |
| **sal** | Neutral | Balanced, calm, measured               | Technical support, accessibility       |
| **eve** | Female  | Energetic, upbeat, engaging            | Entertainment, interactive experiences |
| **leo** | Male    | Authoritative, commanding, trustworthy | Instructions, educational content      |

### Voice Selection Example

```typescript
// Change voice mid-session
ws.send(
  JSON.stringify({
    type: "session.update",
    session: {
      voice: "rex",
    },
  }),
);
```

> **Note:** Voice changes take effect on the next response. In-progress audio streams continue with the previously selected voice.

---

## Audio Formats

The API supports multiple audio formats to accommodate different platforms and bandwidth requirements.

### Format Comparison

| Format           | Type String  | Sample Rates    | Bit Depth | Use Case                  |
| ---------------- | ------------ | --------------- | --------- | ------------------------- |
| **PCM**          | `audio/pcm`  | 8000-48000 Hz   | 16-bit    | High quality, low latency |
| **G.711 mu-law** | `audio/pcmu` | 8000 Hz (fixed) | 8-bit     | Telephony (North America) |
| **G.711 A-law**  | `audio/pcma` | 8000 Hz (fixed) | 8-bit     | Telephony (International) |

### PCM Format Details

- **Encoding:** Linear PCM (Linear16)
- **Byte Order:** Little-endian
- **Channels:** Mono (single channel)
- **Sample Rates:** 8000, 16000, 21050, 24000 (default), 32000, 44100, 48000 Hz

### Sample Rate Selection Guide

| Sample Rate | Bandwidth | Quality   | Recommended Use                     |
| ----------- | --------- | --------- | ----------------------------------- |
| 8000 Hz     | ~64 kbps  | Telephone | Telephony integrations              |
| 16000 Hz    | ~128 kbps | Good      | Voice assistants, bandwidth-limited |
| 24000 Hz    | ~192 kbps | High      | Default, balanced quality/bandwidth |
| 44100 Hz    | ~352 kbps | CD        | Music applications                  |
| 48000 Hz    | ~384 kbps | Studio    | Professional audio                  |

### Audio Encoding/Decoding

```typescript
// Encoding PCM audio to base64 for transmission
function encodeAudio(pcmBuffer: Buffer): string {
  return pcmBuffer.toString("base64");
}

// Decoding received base64 audio
function decodeAudio(base64Audio: string): Buffer {
  return Buffer.from(base64Audio, "base64");
}

// Converting Float32Array (Web Audio API) to Int16 PCM
function float32ToInt16(float32Array: Float32Array): Int16Array {
  const int16Array = new Int16Array(float32Array.length);
  for (let i = 0; i < float32Array.length; i++) {
    const s = Math.max(-1, Math.min(1, float32Array[i]));
    int16Array[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
  }
  return int16Array;
}

// Converting Int16 PCM to Float32Array for playback
function int16ToFloat32(int16Array: Int16Array): Float32Array {
  const float32Array = new Float32Array(int16Array.length);
  for (let i = 0; i < int16Array.length; i++) {
    float32Array[i] = int16Array[i] / (int16Array[i] < 0 ? 0x8000 : 0x7fff);
  }
  return float32Array;
}
```

---

## Message Protocol

The API uses a bidirectional message protocol over WebSocket. All messages are JSON-encoded.

### Client to Server Events

| Event Type                  | Purpose                      | When to Send                                   |
| --------------------------- | ---------------------------- | ---------------------------------------------- |
| `session.update`            | Modify session configuration | After connection, when config changes needed   |
| `conversation.item.create`  | Add message to conversation  | User text input, function results              |
| `input_audio_buffer.append` | Stream audio data            | During user speech                             |
| `input_audio_buffer.commit` | Finalize audio input         | End of user speech (manual mode)               |
| `response.create`           | Request assistant response   | After committing input, after function results |

### Server to Client Events

| Event Type                               | Purpose                     | Expected Response             |
| ---------------------------------------- | --------------------------- | ----------------------------- |
| `session.created`                        | Connection established      | Send `session.update`         |
| `session.updated`                        | Configuration confirmed     | None                          |
| `conversation.item.added`                | Message added to history    | None                          |
| `input_audio_buffer.speech_started`      | VAD detected speech start   | None                          |
| `input_audio_buffer.speech_stopped`      | VAD detected speech end     | None                          |
| `response.created`                       | Response generation started | None                          |
| `response.output_audio.delta`            | Audio chunk available       | Play/buffer audio             |
| `response.output_audio_transcript.delta` | Transcript text chunk       | Display text                  |
| `response.output_audio.done`             | Audio stream complete       | None                          |
| `response.function_call_arguments.done`  | Function call requested     | Execute function, send result |
| `response.done`                          | Response complete           | None                          |
| `error`                                  | Error occurred              | Handle error                  |

### Message Schemas

#### session.update

```json
{
  "type": "session.update",
  "session": {
    "instructions": "string",
    "voice": "string",
    "turn_detection": { "type": "string | null" },
    "audio": {
      "input": { "format": { "type": "string", "rate": "number" } },
      "output": { "format": { "type": "string", "rate": "number" } }
    },
    "tools": []
  }
}
```

#### conversation.item.create

```json
{
  "type": "conversation.item.create",
  "item": {
    "type": "message",
    "role": "user | assistant | system",
    "content": [
      {
        "type": "text | input_audio",
        "text": "string",
        "audio": "base64-encoded-string"
      }
    ]
  }
}
```

#### input_audio_buffer.append

```json
{
  "type": "input_audio_buffer.append",
  "audio": "base64-encoded-audio-chunk"
}
```

#### input_audio_buffer.commit

```json
{
  "type": "input_audio_buffer.commit"
}
```

#### response.create

```json
{
  "type": "response.create",
  "response": {
    "modalities": ["text", "audio"]
  }
}
```

#### response.output_audio.delta (Server)

```json
{
  "type": "response.output_audio.delta",
  "response_id": "string",
  "item_id": "string",
  "output_index": 0,
  "content_index": 0,
  "delta": "base64-encoded-audio-chunk"
}
```

#### response.function_call_arguments.done (Server)

```json
{
  "type": "response.function_call_arguments.done",
  "response_id": "string",
  "item_id": "string",
  "output_index": 0,
  "call_id": "string",
  "name": "function_name",
  "arguments": "{\"param\": \"value\"}"
}
```

#### error (Server)

```json
{
  "type": "error",
  "error": {
    "type": "string",
    "code": "string",
    "message": "string"
  }
}
```

---

## Tool Integration

The API supports four types of tools that extend the assistant's capabilities.

### Tool Types

| Tool        | Type String   | Purpose                       |
| ----------- | ------------- | ----------------------------- |
| Web Search  | `web_search`  | Query current web information |
| X Search    | `x_search`    | Search Twitter/X content      |
| File Search | `file_search` | Query document collections    |
| Function    | `function`    | Execute custom functions      |

### Web Search

Enable the assistant to search the web for current information.

```typescript
const sessionConfig = {
  type: "session.update",
  session: {
    tools: [{ type: "web_search" }],
  },
};
```

### X Search

Search Twitter/X posts with optional handle filtering.

```typescript
const sessionConfig = {
  type: "session.update",
  session: {
    tools: [
      {
        type: "x_search",
        handles: ["elonmusk", "xai"], // Optional: limit to specific handles
      },
    ],
  },
};
```

### File Search

Query pre-configured vector stores containing documents.

```typescript
const sessionConfig = {
  type: "session.update",
  session: {
    tools: [
      {
        type: "file_search",
        vector_store_ids: ["vs_abc123", "vs_def456"],
      },
    ],
  },
};
```

### Function Tools

Define custom functions the assistant can invoke. See [Custom Functions](#custom-functions) for detailed implementation.

```typescript
const sessionConfig = {
  type: "session.update",
  session: {
    tools: [
      {
        type: "function",
        function: {
          name: "get_weather",
          description: "Get current weather for a location",
          parameters: {
            type: "object",
            properties: {
              location: {
                type: "string",
                description: "City name or coordinates",
              },
              units: {
                type: "string",
                enum: ["celsius", "fahrenheit"],
                description: "Temperature units",
              },
            },
            required: ["location"],
          },
        },
      },
    ],
  },
};
```

---

## Custom Functions

Custom functions enable the assistant to invoke your application logic during conversations.

### Function Definition

Define functions with JSON Schema parameters:

```typescript
interface FunctionDefinition {
  type: "function";
  function: {
    name: string; // Unique function identifier
    description: string; // What the function does (used by AI)
    parameters: {
      type: "object";
      properties: {
        [key: string]: {
          type: string;
          description?: string;
          enum?: string[];
        };
      };
      required?: string[];
    };
  };
}
```

### Complete Function Call Flow

```typescript
// Step 1: Define and register functions
const tools = [
  {
    type: "function",
    function: {
      name: "lookup_order",
      description: "Look up order status and details by order ID",
      parameters: {
        type: "object",
        properties: {
          order_id: {
            type: "string",
            description: "The order ID (format: ORD-XXXXX)",
          },
        },
        required: ["order_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "create_support_ticket",
      description: "Create a support ticket for customer issues",
      parameters: {
        type: "object",
        properties: {
          subject: {
            type: "string",
            description: "Brief description of the issue",
          },
          priority: {
            type: "string",
            enum: ["low", "medium", "high"],
            description: "Ticket priority level",
          },
          category: {
            type: "string",
            enum: ["billing", "technical", "shipping", "other"],
            description: "Issue category",
          },
        },
        required: ["subject", "category"],
      },
    },
  },
];

ws.send(
  JSON.stringify({
    type: "session.update",
    session: { tools },
  }),
);

// Step 2: Handle function calls from the server
ws.on("message", async (data: Buffer) => {
  const event = JSON.parse(data.toString());

  if (event.type === "response.function_call_arguments.done") {
    const { call_id, name, arguments: args } = event;
    const parsedArgs = JSON.parse(args);

    // Execute the appropriate function
    let result: any;
    try {
      switch (name) {
        case "lookup_order":
          result = await lookupOrder(parsedArgs.order_id);
          break;
        case "create_support_ticket":
          result = await createSupportTicket(parsedArgs);
          break;
        default:
          result = { error: `Unknown function: ${name}` };
      }
    } catch (error) {
      result = { error: error.message };
    }

    // Step 3: Send function result back
    ws.send(
      JSON.stringify({
        type: "conversation.item.create",
        item: {
          type: "function_call_output",
          call_id: call_id,
          output: JSON.stringify(result),
        },
      }),
    );

    // Step 4: Request continuation of the response
    ws.send(
      JSON.stringify({
        type: "response.create",
      }),
    );
  }
});

// Example function implementations
async function lookupOrder(orderId: string): Promise<object> {
  // Your order lookup logic
  return {
    order_id: orderId,
    status: "shipped",
    tracking_number: "TRK123456789",
    estimated_delivery: "2024-01-20",
  };
}

async function createSupportTicket(params: {
  subject: string;
  priority?: string;
  category: string;
}): Promise<object> {
  // Your ticket creation logic
  return {
    ticket_id: "TKT-12345",
    created_at: new Date().toISOString(),
    status: "open",
  };
}
```

### Function Call Sequence Diagram

```
Client                          Server
  |                               |
  |-- session.update (tools) ---->|
  |<-- session.updated -----------|
  |                               |
  |-- input_audio_buffer.append ->|
  |-- input_audio_buffer.commit ->|
  |                               |
  |<-- response.created ----------|
  |<-- response.function_call_arguments.done
  |                               |
  |   [Execute function locally]  |
  |                               |
  |-- conversation.item.create -->|
  |   (function_call_output)      |
  |-- response.create ----------->|
  |                               |
  |<-- response.output_audio.delta|
  |<-- response.done -------------|
```

---

## Turn Detection

Control how the system detects when the user has finished speaking.

### Server VAD Mode (Automatic)

The server uses Voice Activity Detection to automatically detect speech boundaries.

```typescript
ws.send(
  JSON.stringify({
    type: "session.update",
    session: {
      turn_detection: {
        type: "server_vad",
      },
    },
  }),
);

// Handle VAD events
ws.on("message", (data: Buffer) => {
  const event = JSON.parse(data.toString());

  switch (event.type) {
    case "input_audio_buffer.speech_started":
      console.log("User started speaking");
      // Optionally pause playback
      break;
    case "input_audio_buffer.speech_stopped":
      console.log("User stopped speaking");
      // Response will be generated automatically
      break;
  }
});
```

**Server VAD Use Cases:**

- Natural conversation flow
- Hands-free applications
- When latency is prioritized over control

### Manual Mode

Client explicitly signals when user input is complete.

```typescript
ws.send(
  JSON.stringify({
    type: "session.update",
    session: {
      turn_detection: {
        type: null, // Disable automatic detection
      },
    },
  }),
);

// Manually control turn taking
function onUserFinishedSpeaking() {
  // Commit the audio buffer
  ws.send(
    JSON.stringify({
      type: "input_audio_buffer.commit",
    }),
  );

  // Request a response
  ws.send(
    JSON.stringify({
      type: "response.create",
    }),
  );
}
```

**Manual Mode Use Cases:**

- Push-to-talk interfaces
- Noisy environments
- Precise control over turn boundaries
- Integration with external VAD systems

### Comparison

| Aspect                    | Server VAD              | Manual                    |
| ------------------------- | ----------------------- | ------------------------- |
| User experience           | Natural, conversational | Controlled, explicit      |
| Implementation complexity | Lower                   | Higher                    |
| Control                   | Less                    | Full                      |
| Background noise handling | Automatic               | Application-controlled    |
| Latency                   | Optimized               | Depends on implementation |

---

## Implementation Examples

### Browser Implementation with Web Audio API

```typescript
// browser-voice-client.ts

class VoiceClient {
  private ws: WebSocket;
  private audioContext: AudioContext;
  private mediaStream: MediaStream | null = null;
  private audioWorklet: AudioWorkletNode | null = null;
  private playbackQueue: Float32Array[] = [];
  private isPlaying = false;

  constructor(private token: string) {
    this.audioContext = new AudioContext({ sampleRate: 24000 });
  }

  async connect(): Promise<void> {
    this.ws = new WebSocket(`wss://api.x.ai/v1/realtime?token=${this.token}`);

    this.ws.onopen = () => {
      this.configureSession();
    };

    this.ws.onmessage = (event) => {
      this.handleMessage(JSON.parse(event.data));
    };

    this.ws.onerror = (error) => {
      console.error("WebSocket error:", error);
    };

    this.ws.onclose = () => {
      this.cleanup();
    };
  }

  private configureSession(): void {
    this.ws.send(
      JSON.stringify({
        type: "session.update",
        session: {
          instructions: "You are a helpful voice assistant.",
          voice: "ara",
          turn_detection: { type: "server_vad" },
          audio: {
            input: { format: { type: "audio/pcm", rate: 24000 } },
            output: { format: { type: "audio/pcm", rate: 24000 } },
          },
        },
      }),
    );
  }

  async startRecording(): Promise<void> {
    // Request microphone access
    this.mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        sampleRate: 24000,
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
      },
    });

    // Load audio worklet for processing
    await this.audioContext.audioWorklet.addModule("/audio-processor.js");

    const source = this.audioContext.createMediaStreamSource(this.mediaStream);
    this.audioWorklet = new AudioWorkletNode(
      this.audioContext,
      "audio-processor",
    );

    this.audioWorklet.port.onmessage = (event) => {
      const pcmData = event.data;
      this.sendAudio(pcmData);
    };

    source.connect(this.audioWorklet);
  }

  private sendAudio(pcmData: Int16Array): void {
    const base64 = this.int16ArrayToBase64(pcmData);
    this.ws.send(
      JSON.stringify({
        type: "input_audio_buffer.append",
        audio: base64,
      }),
    );
  }

  private handleMessage(event: any): void {
    switch (event.type) {
      case "session.updated":
        console.log("Session configured");
        break;

      case "response.output_audio.delta":
        this.queueAudioForPlayback(event.delta);
        break;

      case "response.output_audio_transcript.delta":
        this.onTranscript?.(event.delta);
        break;

      case "input_audio_buffer.speech_started":
        this.pausePlayback();
        break;

      case "error":
        console.error("API Error:", event.error);
        break;
    }
  }

  private queueAudioForPlayback(base64Audio: string): void {
    const pcmData = this.base64ToInt16Array(base64Audio);
    const floatData = this.int16ToFloat32(pcmData);
    this.playbackQueue.push(floatData);

    if (!this.isPlaying) {
      this.playNextChunk();
    }
  }

  private playNextChunk(): void {
    if (this.playbackQueue.length === 0) {
      this.isPlaying = false;
      return;
    }

    this.isPlaying = true;
    const floatData = this.playbackQueue.shift()!;

    const buffer = this.audioContext.createBuffer(1, floatData.length, 24000);
    buffer.copyToChannel(floatData, 0);

    const source = this.audioContext.createBufferSource();
    source.buffer = buffer;
    source.connect(this.audioContext.destination);
    source.onended = () => this.playNextChunk();
    source.start();
  }

  private pausePlayback(): void {
    this.playbackQueue = [];
    this.isPlaying = false;
  }

  stopRecording(): void {
    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach((track) => track.stop());
      this.mediaStream = null;
    }
    if (this.audioWorklet) {
      this.audioWorklet.disconnect();
      this.audioWorklet = null;
    }
  }

  disconnect(): void {
    this.stopRecording();
    if (this.ws) {
      this.ws.close();
    }
  }

  private cleanup(): void {
    this.stopRecording();
    this.audioContext.close();
  }

  // Utility methods
  private int16ArrayToBase64(int16Array: Int16Array): string {
    const bytes = new Uint8Array(int16Array.buffer);
    let binary = "";
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  private base64ToInt16Array(base64: string): Int16Array {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return new Int16Array(bytes.buffer);
  }

  private int16ToFloat32(int16Array: Int16Array): Float32Array {
    const float32Array = new Float32Array(int16Array.length);
    for (let i = 0; i < int16Array.length; i++) {
      float32Array[i] = int16Array[i] / (int16Array[i] < 0 ? 0x8000 : 0x7fff);
    }
    return float32Array;
  }

  // Event callbacks
  onTranscript?: (text: string) => void;
}

// Audio Worklet Processor (save as audio-processor.js)
/*
class AudioProcessor extends AudioWorkletProcessor {
  process(inputs, outputs, parameters) {
    const input = inputs[0];
    if (input && input[0]) {
      const float32Data = input[0];
      const int16Data = new Int16Array(float32Data.length);
      for (let i = 0; i < float32Data.length; i++) {
        const s = Math.max(-1, Math.min(1, float32Data[i]));
        int16Data[i] = s < 0 ? s * 0x8000 : s * 0x7FFF;
      }
      this.port.postMessage(int16Data);
    }
    return true;
  }
}
registerProcessor('audio-processor', AudioProcessor);
*/
```

### Node.js Server Implementation

```typescript
// server-voice-handler.ts
import WebSocket from "ws";
import { EventEmitter } from "events";

interface VoiceSessionConfig {
  apiKey: string;
  voice?: string;
  instructions?: string;
  tools?: any[];
}

class VoiceSession extends EventEmitter {
  private ws: WebSocket;
  private isConnected = false;

  constructor(private config: VoiceSessionConfig) {
    super();
  }

  async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket("wss://api.x.ai/v1/realtime", {
        headers: {
          Authorization: `Bearer ${this.config.apiKey}`,
        },
      });

      this.ws.on("open", () => {
        this.isConnected = true;
        this.initializeSession();
        resolve();
      });

      this.ws.on("message", (data: Buffer) => {
        const event = JSON.parse(data.toString());
        this.handleEvent(event);
      });

      this.ws.on("error", (error) => {
        this.emit("error", error);
        reject(error);
      });

      this.ws.on("close", () => {
        this.isConnected = false;
        this.emit("disconnected");
      });
    });
  }

  private initializeSession(): void {
    this.send({
      type: "session.update",
      session: {
        instructions:
          this.config.instructions || "You are a helpful assistant.",
        voice: this.config.voice || "ara",
        turn_detection: { type: "server_vad" },
        audio: {
          input: { format: { type: "audio/pcm", rate: 24000 } },
          output: { format: { type: "audio/pcm", rate: 24000 } },
        },
        tools: this.config.tools || [],
      },
    });
  }

  private handleEvent(event: any): void {
    switch (event.type) {
      case "session.updated":
        this.emit("ready");
        break;

      case "response.output_audio.delta":
        this.emit("audio", Buffer.from(event.delta, "base64"));
        break;

      case "response.output_audio_transcript.delta":
        this.emit("transcript", event.delta);
        break;

      case "response.function_call_arguments.done":
        this.emit("function_call", {
          callId: event.call_id,
          name: event.name,
          arguments: JSON.parse(event.arguments),
        });
        break;

      case "input_audio_buffer.speech_started":
        this.emit("speech_started");
        break;

      case "input_audio_buffer.speech_stopped":
        this.emit("speech_stopped");
        break;

      case "response.done":
        this.emit("response_complete");
        break;

      case "error":
        this.emit("error", new Error(event.error.message));
        break;

      default:
        this.emit("event", event);
    }
  }

  sendAudio(pcmBuffer: Buffer): void {
    if (!this.isConnected) return;

    this.send({
      type: "input_audio_buffer.append",
      audio: pcmBuffer.toString("base64"),
    });
  }

  commitAudio(): void {
    this.send({ type: "input_audio_buffer.commit" });
  }

  requestResponse(): void {
    this.send({ type: "response.create" });
  }

  sendFunctionResult(callId: string, result: any): void {
    this.send({
      type: "conversation.item.create",
      item: {
        type: "function_call_output",
        call_id: callId,
        output: JSON.stringify(result),
      },
    });
    this.requestResponse();
  }

  sendTextMessage(text: string): void {
    this.send({
      type: "conversation.item.create",
      item: {
        type: "message",
        role: "user",
        content: [{ type: "text", text }],
      },
    });
    this.requestResponse();
  }

  private send(message: any): void {
    if (this.isConnected) {
      this.ws.send(JSON.stringify(message));
    }
  }

  disconnect(): void {
    if (this.ws) {
      this.ws.close();
    }
  }
}

// Usage example
async function main() {
  const session = new VoiceSession({
    apiKey: process.env.XAI_API_KEY!,
    voice: "ara",
    instructions: "You are a helpful customer service agent.",
    tools: [
      {
        type: "function",
        function: {
          name: "get_account_balance",
          description: "Get the current account balance",
          parameters: {
            type: "object",
            properties: {
              account_id: { type: "string" },
            },
            required: ["account_id"],
          },
        },
      },
    ],
  });

  session.on("ready", () => console.log("Session ready"));
  session.on("audio", (buffer) => {
    // Handle audio output (e.g., stream to client)
  });
  session.on("transcript", (text) => console.log("Assistant:", text));
  session.on("function_call", async ({ callId, name, arguments: args }) => {
    console.log(`Function call: ${name}`, args);

    // Execute function
    const result = await executeFunction(name, args);
    session.sendFunctionResult(callId, result);
  });
  session.on("error", (err) => console.error("Error:", err));

  await session.connect();
}

async function executeFunction(name: string, args: any): Promise<any> {
  // Implement your function logic
  switch (name) {
    case "get_account_balance":
      return { balance: 1250.0, currency: "USD" };
    default:
      return { error: "Unknown function" };
  }
}
```

### React Hook Implementation

```typescript
// useVoiceAgent.ts
import { useState, useCallback, useRef, useEffect } from "react";

interface UseVoiceAgentOptions {
  onTranscript?: (text: string) => void;
  onError?: (error: Error) => void;
}

interface VoiceAgentState {
  isConnected: boolean;
  isRecording: boolean;
  isProcessing: boolean;
}

export function useVoiceAgent(options: UseVoiceAgentOptions = {}) {
  const [state, setState] = useState<VoiceAgentState>({
    isConnected: false,
    isRecording: false,
    isProcessing: false,
  });

  const wsRef = useRef<WebSocket | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);

  const connect = useCallback(
    async (token: string) => {
      try {
        const ws = new WebSocket(`wss://api.x.ai/v1/realtime?token=${token}`);
        wsRef.current = ws;

        ws.onopen = () => {
          setState((prev) => ({ ...prev, isConnected: true }));

          ws.send(
            JSON.stringify({
              type: "session.update",
              session: {
                voice: "ara",
                turn_detection: { type: "server_vad" },
                audio: {
                  input: { format: { type: "audio/pcm", rate: 24000 } },
                  output: { format: { type: "audio/pcm", rate: 24000 } },
                },
              },
            }),
          );
        };

        ws.onmessage = (event) => {
          const data = JSON.parse(event.data);
          handleMessage(data);
        };

        ws.onerror = () => {
          options.onError?.(new Error("WebSocket connection failed"));
        };

        ws.onclose = () => {
          setState((prev) => ({ ...prev, isConnected: false }));
        };
      } catch (error) {
        options.onError?.(error as Error);
      }
    },
    [options],
  );

  const handleMessage = useCallback(
    (event: any) => {
      switch (event.type) {
        case "response.output_audio_transcript.delta":
          options.onTranscript?.(event.delta);
          break;
        case "input_audio_buffer.speech_started":
          setState((prev) => ({ ...prev, isProcessing: true }));
          break;
        case "response.done":
          setState((prev) => ({ ...prev, isProcessing: false }));
          break;
        case "error":
          options.onError?.(new Error(event.error.message));
          break;
      }
    },
    [options],
  );

  const startRecording = useCallback(async () => {
    try {
      audioContextRef.current = new AudioContext({ sampleRate: 24000 });
      mediaStreamRef.current = await navigator.mediaDevices.getUserMedia({
        audio: { sampleRate: 24000, channelCount: 1 },
      });

      const source = audioContextRef.current.createMediaStreamSource(
        mediaStreamRef.current,
      );

      const processor = audioContextRef.current.createScriptProcessor(
        4096,
        1,
        1,
      );
      processor.onaudioprocess = (e) => {
        const inputData = e.inputBuffer.getChannelData(0);
        const pcm16 = float32ToPcm16(inputData);
        sendAudio(pcm16);
      };

      source.connect(processor);
      processor.connect(audioContextRef.current.destination);

      setState((prev) => ({ ...prev, isRecording: true }));
    } catch (error) {
      options.onError?.(error as Error);
    }
  }, [options]);

  const stopRecording = useCallback(() => {
    if (mediaStreamRef.current) {
      mediaStreamRef.current.getTracks().forEach((track) => track.stop());
      mediaStreamRef.current = null;
    }
    if (audioContextRef.current) {
      audioContextRef.current.close();
      audioContextRef.current = null;
    }
    setState((prev) => ({ ...prev, isRecording: false }));
  }, []);

  const sendAudio = useCallback((pcmData: Int16Array) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      const base64 = btoa(
        String.fromCharCode(...new Uint8Array(pcmData.buffer)),
      );
      wsRef.current.send(
        JSON.stringify({
          type: "input_audio_buffer.append",
          audio: base64,
        }),
      );
    }
  }, []);

  const disconnect = useCallback(() => {
    stopRecording();
    wsRef.current?.close();
    wsRef.current = null;
  }, [stopRecording]);

  useEffect(() => {
    return () => {
      disconnect();
    };
  }, [disconnect]);

  return {
    ...state,
    connect,
    startRecording,
    stopRecording,
    disconnect,
  };
}

function float32ToPcm16(float32: Float32Array): Int16Array {
  const pcm16 = new Int16Array(float32.length);
  for (let i = 0; i < float32.length; i++) {
    const s = Math.max(-1, Math.min(1, float32[i]));
    pcm16[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
  }
  return pcm16;
}
```

---

## Architecture Patterns

### Web Application Architecture

```
+------------------+     +-------------------+     +----------------+
|                  |     |                   |     |                |
|  Browser Client  |<--->|  Backend Server   |<--->|  xAI API       |
|  (React/Vue/etc) |     |  (FastAPI/Express)|     |  (WebSocket)   |
|                  |     |                   |     |                |
+------------------+     +-------------------+     +----------------+
       |                         |
       | WebSocket/HTTP          | API Key (secure)
       | Ephemeral token         |
       v                         v
  [Microphone]              [Database]
  [Speaker]                 [Function Logic]
```

**Implementation Notes:**

- Backend generates ephemeral tokens for client authentication
- Audio can flow through backend (proxied) or directly to xAI (with token)
- Function calls execute on backend with access to databases and services
- Backend handles business logic, rate limiting, and logging

### Telephony Architecture (Twilio Integration)

```
+----------+     +------------+     +---------------+     +----------+
|          |     |            |     |               |     |          |
|  Phone   |<--->|  Twilio    |<--->|  Node.js      |<--->|  xAI API |
|          |     |  Media     |     |  Server       |     |          |
|          |     |  Streams   |     |               |     |          |
+----------+     +------------+     +---------------+     +----------+
                      |                    |
                      | WebSocket          | WebSocket
                      | (G.711 audio)      | (PCM/G.711)
                      v                    v
                 [TwiML Config]       [Call State]
                                     [Function Logic]
```

```typescript
// Twilio Media Streams integration example
import Twilio from "twilio";
import WebSocket from "ws";
import express from "express";

const app = express();
const server = app.listen(3000);
const wss = new WebSocket.Server({ server, path: "/media-stream" });

// TwiML endpoint for incoming calls
app.post("/voice", (req, res) => {
  const twiml = new Twilio.twiml.VoiceResponse();
  const connect = twiml.connect();
  connect.stream({ url: `wss://${req.headers.host}/media-stream` });
  res.type("text/xml");
  res.send(twiml.toString());
});

// WebSocket handler for media streams
wss.on("connection", (twilioWs) => {
  let xaiWs: WebSocket | null = null;
  let streamSid: string | null = null;

  twilioWs.on("message", async (message) => {
    const data = JSON.parse(message.toString());

    switch (data.event) {
      case "start":
        streamSid = data.start.streamSid;
        xaiWs = await connectToXai();
        break;

      case "media":
        // Forward Twilio audio to xAI
        if (xaiWs?.readyState === WebSocket.OPEN) {
          xaiWs.send(
            JSON.stringify({
              type: "input_audio_buffer.append",
              audio: data.media.payload, // Already base64 mu-law
            }),
          );
        }
        break;

      case "stop":
        xaiWs?.close();
        break;
    }
  });

  async function connectToXai(): Promise<WebSocket> {
    const ws = new WebSocket("wss://api.x.ai/v1/realtime", {
      headers: { Authorization: `Bearer ${process.env.XAI_API_KEY}` },
    });

    ws.on("open", () => {
      ws.send(
        JSON.stringify({
          type: "session.update",
          session: {
            voice: "ara",
            turn_detection: { type: "server_vad" },
            audio: {
              input: { format: { type: "audio/pcmu" } }, // G.711 mu-law
              output: { format: { type: "audio/pcmu" } },
            },
          },
        }),
      );
    });

    ws.on("message", (msg) => {
      const event = JSON.parse(msg.toString());

      if (event.type === "response.output_audio.delta") {
        // Send audio back to Twilio
        twilioWs.send(
          JSON.stringify({
            event: "media",
            streamSid,
            media: { payload: event.delta },
          }),
        );
      }
    });

    return ws;
  }
});
```

### WebRTC Architecture

> **Note:** Direct WebRTC connections to xAI are not available. Audio must be relayed through a backend server.

```
+------------------+     +-------------------+     +----------------+
|                  |     |                   |     |                |
|  Browser Client  |<--->|  Media Server     |<--->|  xAI API       |
|  (WebRTC)        |     |  (Express + WS)   |     |  (WebSocket)   |
|                  |     |                   |     |                |
+------------------+     +-------------------+     +----------------+
       |                         |
       | WebRTC                  | WebSocket
       | (OPUS -> PCM)           | (PCM)
       v                         v
  [getUserMedia]            [Transcoding]
```

---

## Best Practices

### Security

1. **Never expose API keys client-side**
   - Always use ephemeral tokens for browser/mobile applications
   - Store API keys in environment variables on the server

2. **Validate ephemeral token requests**
   - Authenticate users before generating tokens
   - Use short expiration times (5-10 minutes)

3. **Implement rate limiting**
   - Limit token generation per user
   - Monitor for unusual usage patterns

```typescript
// Example: Token generation with rate limiting
const tokenBuckets = new Map<string, number>();

async function generateToken(userId: string): Promise<string> {
  const bucket = tokenBuckets.get(userId) || 0;
  if (bucket >= 10) {
    // Max 10 tokens per hour
    throw new Error("Rate limit exceeded");
  }

  tokenBuckets.set(userId, bucket + 1);
  setTimeout(() => {
    tokenBuckets.set(userId, (tokenBuckets.get(userId) || 1) - 1);
  }, 3600000); // Reset after 1 hour

  // Generate token...
}
```

### Performance

1. **Audio buffering**
   - Buffer incoming audio chunks before playback
   - Use 100-200ms buffer to handle network jitter

2. **Efficient audio encoding**
   - Process audio in chunks (4096-8192 samples)
   - Avoid blocking the main thread with Web Workers

3. **Connection management**
   - Implement reconnection logic with exponential backoff
   - Keep connections alive for conversation sessions

```typescript
// Reconnection with exponential backoff
async function connectWithRetry(maxRetries = 5): Promise<WebSocket> {
  let retries = 0;

  while (retries < maxRetries) {
    try {
      const ws = await connect();
      return ws;
    } catch (error) {
      retries++;
      const delay = Math.min(1000 * Math.pow(2, retries), 30000);
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  throw new Error("Max retries exceeded");
}
```

### Error Handling

1. **Graceful degradation**
   - Fall back to text input if audio fails
   - Handle microphone permission denials

2. **User feedback**
   - Show connection status indicators
   - Display error messages clearly

3. **Logging and monitoring**
   - Log all errors with context
   - Track session metrics (duration, error rates)

```typescript
// Comprehensive error handling
class VoiceSession {
  private handleError(error: any, context: string): void {
    const errorInfo = {
      timestamp: new Date().toISOString(),
      context,
      message: error.message,
      code: error.code,
      stack: error.stack,
    };

    console.error("Voice session error:", errorInfo);

    // Emit to application error handler
    this.emit("error", {
      type: this.categorizeError(error),
      message: this.getUserFriendlyMessage(error),
      recoverable: this.isRecoverable(error),
    });
  }

  private categorizeError(error: any): string {
    if (error.code === "ECONNREFUSED") return "connection";
    if (error.message?.includes("audio")) return "audio";
    if (error.message?.includes("auth")) return "authentication";
    return "unknown";
  }

  private isRecoverable(error: any): boolean {
    const nonRecoverable = ["authentication", "invalid_api_key"];
    return !nonRecoverable.includes(error.code);
  }
}
```

---

## Troubleshooting

### Common Issues

#### Connection Failures

| Symptom                       | Cause                            | Solution                                      |
| ----------------------------- | -------------------------------- | --------------------------------------------- |
| `401 Unauthorized`            | Invalid or expired API key/token | Verify API key; regenerate ephemeral token    |
| `WebSocket connection failed` | Network/firewall blocking WSS    | Check firewall rules; verify HTTPS support    |
| Connection drops frequently   | Network instability              | Implement reconnection logic; increase buffer |

#### Audio Issues

| Symptom          | Cause                 | Solution                                     |
| ---------------- | --------------------- | -------------------------------------------- |
| No audio output  | Incorrect sample rate | Match input/output sample rates              |
| Distorted audio  | Wrong audio format    | Verify PCM encoding (little-endian, 16-bit)  |
| Audio delay/echo | Processing latency    | Reduce buffer size; enable echo cancellation |
| Choppy audio     | Network jitter        | Increase playback buffer                     |

#### Function Call Issues

| Symptom                           | Cause                   | Solution                                          |
| --------------------------------- | ----------------------- | ------------------------------------------------- |
| Function not called               | Invalid schema          | Validate JSON schema; check required fields       |
| `Unknown function` error          | Function not registered | Include function in session.update tools          |
| Conversation stops after function | Missing response.create | Always send response.create after function result |

### Debug Mode

Enable verbose logging for troubleshooting:

```typescript
class DebugVoiceSession {
  private debug = true;

  private send(message: any): void {
    if (this.debug) {
      console.log("[SEND]", JSON.stringify(message, null, 2));
    }
    this.ws.send(JSON.stringify(message));
  }

  private handleMessage(event: any): void {
    if (this.debug) {
      // Don't log full audio data
      const logEvent =
        event.type === "response.output_audio.delta"
          ? { ...event, delta: `[${event.delta.length} bytes]` }
          : event;
      console.log("[RECV]", JSON.stringify(logEvent, null, 2));
    }
    // Handle event...
  }
}
```

### Diagnostic Checklist

1. **Connection Phase**
   - [ ] API key/token is valid
   - [ ] WebSocket URL is correct (`wss://api.x.ai/v1/realtime`)
   - [ ] Network allows WebSocket connections

2. **Session Configuration**
   - [ ] `session.update` sent after connection
   - [ ] `session.updated` received in response
   - [ ] Audio formats match client capabilities

3. **Audio Streaming**
   - [ ] Microphone permissions granted
   - [ ] Audio context initialized with correct sample rate
   - [ ] Audio chunks encoded correctly (base64, little-endian)

4. **Response Handling**
   - [ ] Listening for all relevant event types
   - [ ] Audio chunks decoded and buffered
   - [ ] Playback queue managed correctly

---

## API Reference

### Quick Reference: Client to Server Events

| Event                       | Required Fields                                  | Optional Fields       |
| --------------------------- | ------------------------------------------------ | --------------------- |
| `session.update`            | `type`                                           | `session.*`           |
| `conversation.item.create`  | `type`, `item.type`, `item.role`, `item.content` | -                     |
| `input_audio_buffer.append` | `type`, `audio`                                  | -                     |
| `input_audio_buffer.commit` | `type`                                           | -                     |
| `response.create`           | `type`                                           | `response.modalities` |

### Quick Reference: Server to Client Events

| Event                                    | Key Fields                     | Description                 |
| ---------------------------------------- | ------------------------------ | --------------------------- |
| `session.created`                        | -                              | Connection established      |
| `session.updated`                        | `session`                      | Configuration confirmed     |
| `conversation.item.added`                | `item`                         | Message added to history    |
| `input_audio_buffer.speech_started`      | -                              | VAD detected speech         |
| `input_audio_buffer.speech_stopped`      | -                              | VAD detected silence        |
| `response.created`                       | `response_id`                  | Response generation started |
| `response.output_audio.delta`            | `delta`, `response_id`         | Audio chunk                 |
| `response.output_audio_transcript.delta` | `delta`                        | Transcript chunk            |
| `response.output_audio.done`             | `response_id`                  | Audio complete              |
| `response.function_call_arguments.done`  | `call_id`, `name`, `arguments` | Function invocation         |
| `response.done`                          | `response_id`                  | Response complete           |
| `error`                                  | `error.type`, `error.message`  | Error occurred              |

### Audio Format Reference

| Format       | Type String  | Sample Rate   | Bit Depth | Encoding      |
| ------------ | ------------ | ------------- | --------- | ------------- |
| PCM          | `audio/pcm`  | 8000-48000 Hz | 16-bit    | Little-endian |
| G.711 mu-law | `audio/pcmu` | 8000 Hz       | 8-bit     | mu-law        |
| G.711 A-law  | `audio/pcma` | 8000 Hz       | 8-bit     | A-law         |

### Voice Reference

| Voice ID | Gender  | Tone                      |
| -------- | ------- | ------------------------- |
| `ara`    | Female  | Warm, conversational      |
| `rex`    | Male    | Professional, clear       |
| `sal`    | Neutral | Balanced, calm            |
| `eve`    | Female  | Energetic, upbeat         |
| `leo`    | Male    | Authoritative, commanding |

### Tool Type Reference

| Tool        | Type String   | Configuration                                 |
| ----------- | ------------- | --------------------------------------------- |
| Web Search  | `web_search`  | None                                          |
| X Search    | `x_search`    | `handles?: string[]`                          |
| File Search | `file_search` | `vector_store_ids: string[]`                  |
| Function    | `function`    | `function: { name, description, parameters }` |

---

## Changelog

| Version | Date       | Changes               |
| ------- | ---------- | --------------------- |
| 1.0.0   | 2024-01-15 | Initial documentation |

---

## Additional Resources

- [xAI Developer Portal](https://console.x.ai)
- [xAI API Documentation](https://docs.x.ai)
- [WebSocket API (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket)
- [Web Audio API (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API)
