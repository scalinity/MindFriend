"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SkipThrottle = exports.ThrottleStrict = exports.ThrottleDefault = exports.ThrottleChat = exports.ThrottleAuth = void 0;
const throttler_1 = require("@nestjs/throttler");
Object.defineProperty(exports, "SkipThrottle", { enumerable: true, get: function () { return throttler_1.SkipThrottle; } });
const ThrottleAuth = () => (0, throttler_1.Throttle)({ auth: { limit: 10, ttl: 60000 } });
exports.ThrottleAuth = ThrottleAuth;
const ThrottleChat = () => (0, throttler_1.Throttle)({ chat: { limit: 60, ttl: 60000 } });
exports.ThrottleChat = ThrottleChat;
const ThrottleDefault = () => (0, throttler_1.Throttle)({ default: { limit: 100, ttl: 60000 } });
exports.ThrottleDefault = ThrottleDefault;
const ThrottleStrict = () => (0, throttler_1.Throttle)({ default: { limit: 5, ttl: 60000 } });
exports.ThrottleStrict = ThrottleStrict;
//# sourceMappingURL=throttle.decorators.js.map