export const serve = (handler: (request: Request) => Response | Promise<Response>) => Deno.serve(handler);
