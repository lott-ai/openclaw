import type { IncomingMessage, ServerResponse } from "node:http";
import { resolveAgentWorkspaceDir, resolveDefaultAgentId } from "../agents/agent-scope.js";
import { listChannelPlugins } from "../channels/plugins/index.js";
import { loadConfig } from "../config/config.js";
import { buildConfigSchema } from "../config/schema.js";
import { loadOpenClawPlugins } from "../plugins/loader.js";

const SCHEMA_PATH = "/openclaw.schema.json";

function sendJson(res: ServerResponse, status: number, body: unknown) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify(body));
}

/**
 * Handles GET /openclaw.schema.json — returns raw JSON Schema for $schema references.
 * Config files can use `"$schema": "http://localhost:18789/openclaw.schema.json"` for editor validation.
 */
export function handleConfigSchemaHttpRequest(req: IncomingMessage, res: ServerResponse): boolean {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return false;
  }

  const url = new URL(req.url ?? "/", "http://localhost");
  if (url.pathname !== SCHEMA_PATH) {
    return false;
  }

  if (req.method === "HEAD") {
    res.statusCode = 200;
    res.setHeader("Content-Type", "application/json; charset=utf-8");
    res.end();
    return true;
  }

  try {
    const cfg = loadConfig();
    const workspaceDir = resolveAgentWorkspaceDir(cfg, resolveDefaultAgentId(cfg));
    const pluginRegistry = loadOpenClawPlugins({
      config: cfg,
      workspaceDir,
      logger: {
        info: () => {},
        warn: () => {},
        error: () => {},
        debug: () => {},
      },
    });
    const result = buildConfigSchema({
      plugins: pluginRegistry.plugins.map((plugin) => ({
        id: plugin.id,
        name: plugin.name,
        description: plugin.description,
        configUiHints: plugin.configUiHints,
        configSchema: plugin.configJsonSchema,
      })),
      channels: listChannelPlugins().map((entry) => ({
        id: entry.id,
        label: entry.meta.label,
        description: entry.meta.blurb,
        configSchema: entry.configSchema?.schema,
        configUiHints: entry.configSchema?.uiHints,
      })),
    });
    sendJson(res, 200, result.schema);
  } catch (err) {
    sendJson(res, 500, { error: String(err instanceof Error ? err.message : err) });
  }
  return true;
}
