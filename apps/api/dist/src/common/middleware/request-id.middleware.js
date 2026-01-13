"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.RequestIdMiddleware = exports.REQUEST_ID_HEADER = void 0;
const common_1 = require("@nestjs/common");
const crypto_1 = require("crypto");
exports.REQUEST_ID_HEADER = 'X-Request-ID';
let RequestIdMiddleware = class RequestIdMiddleware {
    use(req, res, next) {
        const existingId = req.get(exports.REQUEST_ID_HEADER);
        const requestId = existingId && this.isValidUUID(existingId) ? existingId : (0, crypto_1.randomUUID)();
        req.requestId = requestId;
        res.setHeader(exports.REQUEST_ID_HEADER, requestId);
        next();
    }
    isValidUUID(str) {
        const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
        return uuidRegex.test(str);
    }
};
exports.RequestIdMiddleware = RequestIdMiddleware;
exports.RequestIdMiddleware = RequestIdMiddleware = __decorate([
    (0, common_1.Injectable)()
], RequestIdMiddleware);
//# sourceMappingURL=request-id.middleware.js.map