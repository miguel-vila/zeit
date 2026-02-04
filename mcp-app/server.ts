import {
  registerAppResource,
  registerAppTool,
  RESOURCE_MIME_TYPE,
} from "@modelcontextprotocol/ext-apps/server";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type {
  CallToolResult,
  ReadResourceResult,
} from "@modelcontextprotocol/sdk/types.js";
import { execSync } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import Database from "better-sqlite3";
import { z } from "zod";

// Path to zeit CLI - can be overridden via environment
const ZEIT_CLI = process.env.ZEIT_CLI || "zeit";

interface ActivityStat {
  activity: string;
  count: number;
  percentage: number;
  category: "work" | "personal" | "system";
}

interface DayStats {
  date: string;
  total_samples: number;
  activities: ActivityStat[];
  work_percentage: number;
  personal_percentage: number;
  idle_percentage: number;
  work_count: number;
  personal_count: number;
  idle_count: number;
}

interface AppData {
  date: string;
  totalActivities: number;
  activities: ActivityStat[];
  workPercentage: number;
  personalPercentage: number;
  idlePercentage: number;
  availableDates: string[];
}

/**
 * Get activity stats for a day by calling zeit CLI.
 * Uses the same logic as `zeit stats --json`.
 */
function getDayStats(dateStr: string): DayStats | null {
  const cmd = `${ZEIT_CLI} stats ${dateStr} --json`;
  console.log(`[getDayStats] Running: ${cmd}`);
  try {
    const output = execSync(cmd, {
      encoding: "utf-8",
      timeout: 30000,
      cwd: process.env.ZEIT_CWD || undefined,
    });
    console.log(`[getDayStats] Output length: ${output.length}`);
    console.log(`[getDayStats] Output: ${JSON.stringify(JSON.parse(output), null, 2)}`);
    return JSON.parse(output) as DayStats;
  } catch (err) {
    console.error(`[getDayStats] Error:`, err);
    return null;
  }
}

/**
 * Get list of available dates from zeit database.
 */
function getAvailableDates(): string[] {
  const dbPath = path.join(os.homedir(), ".local", "share", "zeit", "zeit.db");

  try {
    const db = new Database(dbPath, { readonly: true });
    const rows = db
      .prepare("SELECT date FROM daily_activities ORDER BY date DESC")
      .all() as { date: string }[];
    db.close();
    return rows.map((r: { date: string }) => r.date);
  } catch {
    return [];
  }
}

/**
 * Transform DayStats from CLI to AppData for the UI.
 */
function toAppData(stats: DayStats, availableDates: string[]): AppData {
  return {
    date: stats.date,
    totalActivities: stats.total_samples,
    activities: stats.activities,
    workPercentage: stats.work_percentage,
    personalPercentage: stats.personal_percentage,
    idlePercentage: stats.idle_percentage,
    availableDates,
  };
}

// Works both from source (server.ts) and compiled (dist/server.js)
const DIST_DIR = import.meta.filename.endsWith(".ts")
  ? path.join(import.meta.dirname, "dist")
  : import.meta.dirname;

export function createServer(): McpServer {
  const server = new McpServer({
    name: "Zeit Activity Visualizer",
    version: "1.0.0",
  });

  const resourceUri = "ui://zeit-activity/mcp-app.html";

  // Register the visualization tool
  registerAppTool(
    server,
    "zeit-activity-viz",
    {
      title: "Zeit Activity Visualization",
      description:
        "Visualize activity type percentages for a specific day from Zeit tracker data. Shows a pie chart of how time was spent.",
      inputSchema: z.object({
        date: z
          .string()
          .optional()
          .describe(
            "Date in YYYY-MM-DD format. If not provided, shows today's data."
          ),
      }),
      outputSchema: {
        date: z.string(),
        totalActivities: z.number(),
        activities: z.array(
          z.object({
            activity: z.string(),
            count: z.number(),
            percentage: z.number(),
            category: z.enum(["work", "personal", "system"]),
          })
        ),
        workPercentage: z.number(),
        personalPercentage: z.number(),
        idlePercentage: z.number(),
        availableDates: z.array(z.string()),
      },
      _meta: { ui: { resourceUri } },
    },
    async (args: { date?: string }): Promise<CallToolResult> => {
      const dateStr = args.date || new Date().toISOString().split("T")[0];
      const stats = getDayStats(dateStr);
      const availableDates = getAvailableDates();

      if (!stats || stats.total_samples === 0) {
        console.log(`[zeit-activity-viz] No data for date ${dateStr}`);
        return {
          content: [
            {
              type: "text",
              text: `No activity data found for ${dateStr}. Available dates: ${availableDates.join(", ") || "none"}`,
            },
          ],
          structuredContent: {
            date: dateStr,
            totalActivities: 0,
            activities: [],
            workPercentage: 0,
            personalPercentage: 0,
            idlePercentage: 0,
            availableDates,
          } as unknown as Record<string, unknown>,
        };
      }

      const appData = toAppData(stats, availableDates);
      const summary = appData.activities
        .slice(0, 5)
        .map((a) => `${a.activity}: ${a.percentage.toFixed(1)}%`)
        .join(", ");

      return {
        content: [
          {
            type: "text",
            text: `Activity breakdown for ${dateStr}: ${appData.totalActivities} samples. Work: ${appData.workPercentage.toFixed(1)}%, Personal: ${appData.personalPercentage.toFixed(1)}%, Idle: ${appData.idlePercentage.toFixed(1)}%. Top activities: ${summary}`,
          },
        ],
        structuredContent: appData as unknown as Record<string, unknown>,
      };
    }
  );

  // Register the resource
  registerAppResource(
    server,
    resourceUri,
    resourceUri,
    { mimeType: RESOURCE_MIME_TYPE },
    async (): Promise<ReadResourceResult> => {
      const html = await fs.readFile(
        path.join(DIST_DIR, "mcp-app.html"),
        "utf-8"
      );
      return {
        contents: [
          { uri: resourceUri, mimeType: RESOURCE_MIME_TYPE, text: html },
        ],
      };
    }
  );

  return server;
}
