import "dotenv/config";
import { buildApp } from "./app.js";

const port = Number.parseInt(process.env.PORT ?? "3000", 10);
const host = process.env.HOST ?? "127.0.0.1";

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("PORT must be an integer between 1 and 65535");
}

const app = await buildApp();

try {
  await app.listen({ host, port });
} catch (error) {
  app.log.error({ err: error }, "Unable to start server");
  process.exitCode = 1;
}
