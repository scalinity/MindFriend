"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.RequestId = void 0;
const common_1 = require("@nestjs/common");
exports.RequestId = (0, common_1.createParamDecorator)((data, ctx) => {
    const request = ctx.switchToHttp().getRequest();
    return request.requestId;
});
//# sourceMappingURL=request-id.decorator.js.map