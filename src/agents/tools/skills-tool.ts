import { Type } from "@sinclair/typebox";
import { stringEnum } from "../schema/typebox.js";
import { type AnyAgentTool, jsonResult, readStringParam } from "./common.js";
import { callGatewayTool, type GatewayCallOptions } from "./gateway.js";

const SKILLS_ACTIONS = ["status", "install", "update", "bins"] as const;

const SkillsToolSchema = Type.Object({
  action: stringEnum(SKILLS_ACTIONS),
  gatewayUrl: Type.Optional(Type.String()),
  gatewayToken: Type.Optional(Type.String()),
  timeoutMs: Type.Optional(Type.Number()),
  agentId: Type.Optional(Type.String()),
  name: Type.Optional(Type.String()),
  installId: Type.Optional(Type.String()),
  skillKey: Type.Optional(Type.String()),
  enabled: Type.Optional(Type.Boolean()),
  apiKey: Type.Optional(Type.String()),
  env: Type.Optional(Type.Object({}, { additionalProperties: true })),
});

export function createSkillsTool(): AnyAgentTool {
  return {
    label: "Skills",
    name: "skills",
    description: `Manage agent skills (status/install/update/bins).

ACTIONS:
- status: List all skills with eligibility and configuration status. Optional agentId to target a specific agent (defaults to the default agent).
- install: Install a skill dependency (requires name and installId from the status report).
- update: Update skill configuration (requires skillKey; optional enabled, apiKey, env).
- bins: List all binary dependencies required by skills across all agent workspaces.

EXAMPLES:
- List skills: { "action": "status" }
- List skills for agent: { "action": "status", "agentId": "my-agent" }
- Install a skill dep: { "action": "install", "name": "ffmpeg", "installId": "brew-ffmpeg" }
- Enable a skill: { "action": "update", "skillKey": "my-skill", "enabled": true }
- Set skill API key: { "action": "update", "skillKey": "my-skill", "apiKey": "sk-..." }
- Set skill env vars: { "action": "update", "skillKey": "my-skill", "env": { "MY_VAR": "value" } }
- Clear an env var: { "action": "update", "skillKey": "my-skill", "env": { "MY_VAR": "" } }
- List required bins: { "action": "bins" }`,
    parameters: SkillsToolSchema,
    execute: async (_toolCallId, args) => {
      const params = args as Record<string, unknown>;
      const action = readStringParam(params, "action", { required: true });
      const gatewayOpts: GatewayCallOptions = {
        gatewayUrl: readStringParam(params, "gatewayUrl", { trim: false }),
        gatewayToken: readStringParam(params, "gatewayToken", { trim: false }),
        timeoutMs: typeof params.timeoutMs === "number" ? params.timeoutMs : 60_000,
      };

      switch (action) {
        case "status": {
          const agentId = readStringParam(params, "agentId");
          const statusParams: Record<string, unknown> = {};
          if (agentId) {
            statusParams.agentId = agentId;
          }
          return jsonResult(await callGatewayTool("skills.status", gatewayOpts, statusParams));
        }
        case "install": {
          const name = readStringParam(params, "name", { required: true });
          const installId = readStringParam(params, "installId", { required: true });
          const timeoutMs =
            typeof params.timeoutMs === "number" && Number.isFinite(params.timeoutMs)
              ? Math.max(1000, Math.floor(params.timeoutMs))
              : undefined;
          return jsonResult(
            await callGatewayTool("skills.install", gatewayOpts, {
              name,
              installId,
              ...(timeoutMs ? { timeoutMs } : {}),
            }),
          );
        }
        case "update": {
          const skillKey = readStringParam(params, "skillKey", { required: true });
          const payload: Record<string, unknown> = { skillKey };
          if (typeof params.enabled === "boolean") {
            payload.enabled = params.enabled;
          }
          if (typeof params.apiKey === "string") {
            payload.apiKey = params.apiKey;
          }
          if (params.env && typeof params.env === "object" && !Array.isArray(params.env)) {
            payload.env = params.env;
          }
          return jsonResult(await callGatewayTool("skills.update", gatewayOpts, payload));
        }
        case "bins":
          return jsonResult(await callGatewayTool("skills.bins", gatewayOpts, {}));
        default:
          throw new Error(`Unknown action: ${action}`);
      }
    },
  };
}
