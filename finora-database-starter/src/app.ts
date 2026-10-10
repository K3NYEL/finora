import Fastify, { type FastifyInstance } from "fastify";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";

function parseAllowedOrigins(raw: string | undefined): Set<string> {
  return new Set(
    (raw ?? "")
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean),
  );
}

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      redact: [
        "req.headers.authorization",
        "req.headers.cookie",
        "req.headers['set-cookie']",
        "*.password",
        "*.token",
        "*.secret",
      ],
    },
    bodyLimit: 64 * 1024,
    requestTimeout: 10_000,
    disableRequestLogging: true,
  });

  await app.register(helmet);
  await app.register(rateLimit, {
    max: 100,
    timeWindow: "1 minute",
  });

  const allowedOrigins = parseAllowedOrigins(process.env.CORS_ORIGINS);
  app.addHook("onRequest", async (request, reply) => {
    const origin = request.headers.origin;
    if (origin && !allowedOrigins.has(origin)) {
      return reply.code(403).send({
        error: { code: "ORIGIN_NOT_ALLOWED", message: "Origin not allowed" },
      });
    }
    if (origin) {
      reply.header("Access-Control-Allow-Origin", origin);
      reply.header("Vary", "Origin");
      reply.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
      reply.header("Access-Control-Allow-Headers", "Content-Type, Authorization");
    }
  });

  app.options("/*", async (_request, reply) => reply.code(204).send());

  app.get("/api/v1/health", {
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
  }, async () => ({
    status: "ok",
    service: "finora-database-api",
  }));

  app.setNotFoundHandler(async (_request, reply) => {
    return reply.code(404).send({
      error: { code: "NOT_FOUND", message: "Resource not found" },
    });
  });

  app.setErrorHandler(async (error, request, reply) => {
    request.log.error({ err: error }, "Request failed");
    const statusCode = error.statusCode && error.statusCode >= 400 && error.statusCode < 500
      ? error.statusCode
      : 500;
    return reply.code(statusCode).send({
      error: {
        code: statusCode === 500 ? "INTERNAL_ERROR" : "BAD_REQUEST",
        message: statusCode === 500 ? "An unexpected error occurred" : "Request could not be processed",
      },
    });
  });

  return app;
}
