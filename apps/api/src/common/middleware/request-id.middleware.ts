import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';
import { randomUUID } from 'crypto';

export const REQUEST_ID_HEADER = 'X-Request-ID';

// Extend Express Request to include requestId
declare global {
  namespace Express {
    interface Request {
      requestId: string;
    }
  }
}

/**
 * Middleware that generates or propagates request IDs for tracing.
 *
 * - Checks for existing X-Request-ID header from client/upstream
 * - Generates a new UUID v4 if not present
 * - Attaches requestId to request object for use in logging/handlers
 * - Sets X-Request-ID header on response for client correlation
 */
@Injectable()
export class RequestIdMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    // Get existing request ID from header or generate new one
    const existingId = req.get(REQUEST_ID_HEADER);
    const requestId =
      existingId && this.isValidUUID(existingId) ? existingId : randomUUID();

    // Attach to request object for use throughout the request lifecycle
    req.requestId = requestId;

    // Set response header so client can correlate
    res.setHeader(REQUEST_ID_HEADER, requestId);

    next();
  }

  private isValidUUID(str: string): boolean {
    const uuidRegex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    return uuidRegex.test(str);
  }
}
