import { SkipThrottle } from '@nestjs/throttler';
export declare const ThrottleAuth: () => MethodDecorator & ClassDecorator;
export declare const ThrottleChat: () => MethodDecorator & ClassDecorator;
export declare const ThrottleDefault: () => MethodDecorator & ClassDecorator;
export declare const ThrottleStrict: () => MethodDecorator & ClassDecorator;
export { SkipThrottle };
