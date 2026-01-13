import { createParamDecorator, ExecutionContext } from '@nestjs/common';

/**
 * Decorator to extract the request ID from the current request.
 * The request ID is set by the RequestIdMiddleware.
 *
 * Usage:
 * ```
 * @Get()
 * async myEndpoint(@RequestId() requestId: string) {
 *   console.log(`Processing request ${requestId}`);
 * }
 * ```
 */
export const RequestId = createParamDecorator(
  (data: unknown, ctx: ExecutionContext): string => {
    const request = ctx.switchToHttp().getRequest();
    return request.requestId;
  },
);
