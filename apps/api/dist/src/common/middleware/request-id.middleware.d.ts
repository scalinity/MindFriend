import { NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';
export declare const REQUEST_ID_HEADER = "X-Request-ID";
declare global {
    namespace Express {
        interface Request {
            requestId: string;
        }
    }
}
export declare class RequestIdMiddleware implements NestMiddleware {
    use(req: Request, res: Response, next: NextFunction): void;
    private isValidUUID;
}
