/**
 * Zeit Activity Visualization MCP App
 * Displays activity type percentages in a pie chart with detailed breakdown.
 */
import {
  App,
  applyDocumentTheme,
  applyHostFonts,
  applyHostStyleVariables,
  type McpUiHostContext,
} from "@modelcontextprotocol/ext-apps";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import "./global.css";
import "./mcp-app.css";

interface ActivityPercentage {
  activity: string;
  count: number;
  percentage: number;
  category: "work" | "personal" | "system";
}

interface ActivityData {
  date: string;
  totalActivities: number;
  activities: ActivityPercentage[];
  workPercentage: number;
  personalPercentage: number;
  idlePercentage: number;
  availableDates: string[];
}

// Color palette for activities
const COLORS: Record<string, string> = {
  // Work colors (blues)
  slack: "#1264A3",
  work_email: "#2563eb",
  zoom_meeting: "#2D8CFF",
  work_coding: "#0ea5e9",
  work_browsing: "#3b82f6",
  work_calendar: "#6366f1",
  // Personal colors (purples/pinks)
  personal_browsing: "#8b5cf6",
  social_media: "#ec4899",
  youtube_entertainment: "#ef4444",
  personal_email: "#a855f7",
  personal_ai_use: "#d946ef",
  personal_finances: "#14b8a6",
  professional_development: "#10b981",
  online_shopping: "#f97316",
  personal_calendar: "#f59e0b",
  entertainment: "#e879f9",
  // System
  idle: "#6b7280",
};

function getColor(activity: string): string {
  return COLORS[activity] || "#94a3b8";
}

function formatActivityName(name: string): string {
  return name
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

// DOM elements
const mainEl = document.querySelector(".main") as HTMLElement;
const loadingEl = document.getElementById("loading")!;
const noDataEl = document.getElementById("no-data")!;
const contentEl = document.getElementById("content")!;
const dateSelect = document.getElementById("date-select") as HTMLSelectElement;
const workPctEl = document.getElementById("work-pct")!;
const personalPctEl = document.getElementById("personal-pct")!;
const idlePctEl = document.getElementById("idle-pct")!;
const legendEl = document.getElementById("legend")!;
const activityListEl = document.getElementById("activity-list")!;
const canvas = document.getElementById("pie-chart") as HTMLCanvasElement;
const ctx = canvas.getContext("2d")!;

let currentData: ActivityData | null = null;

function drawPieChart(activities: ActivityPercentage[]): void {
  const size = 300;
  const centerX = size / 2;
  const centerY = size / 2;
  const radius = size / 2 - 10;

  // Set canvas size with device pixel ratio for sharp rendering
  const dpr = window.devicePixelRatio || 1;
  canvas.width = size * dpr;
  canvas.height = size * dpr;
  canvas.style.width = `${size}px`;
  canvas.style.height = `${size}px`;
  ctx.scale(dpr, dpr);

  ctx.clearRect(0, 0, size, size);

  if (activities.length === 0) {
    // Draw empty state
    ctx.beginPath();
    ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
    ctx.fillStyle = "#e5e7eb";
    ctx.fill();
    return;
  }

  let startAngle = -Math.PI / 2; // Start from top

  for (const activity of activities) {
    const sliceAngle = (activity.percentage / 100) * 2 * Math.PI;

    ctx.beginPath();
    ctx.moveTo(centerX, centerY);
    ctx.arc(centerX, centerY, radius, startAngle, startAngle + sliceAngle);
    ctx.closePath();

    ctx.fillStyle = getColor(activity.activity);
    ctx.fill();

    // Add subtle border between slices
    ctx.strokeStyle = "rgba(255,255,255,0.3)";
    ctx.lineWidth = 1;
    ctx.stroke();

    startAngle += sliceAngle;
  }

  // Draw center hole for donut effect
  ctx.beginPath();
  ctx.arc(centerX, centerY, radius * 0.55, 0, 2 * Math.PI);
  ctx.fillStyle = getComputedStyle(document.body).backgroundColor || "#fff";
  ctx.fill();

  // Draw total count in center
  if (currentData) {
    ctx.fillStyle = getComputedStyle(document.body).color || "#000";
    ctx.font = "bold 24px system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(currentData.totalActivities.toString(), centerX, centerY - 8);
    ctx.font = "12px system-ui, sans-serif";
    ctx.fillText("samples", centerX, centerY + 12);
  }
}

function renderLegend(activities: ActivityPercentage[]): void {
  legendEl.innerHTML = activities
    .slice(0, 6)
    .map(
      (a) => `
    <div class="legend-item">
      <span class="legend-color" style="background: ${getColor(a.activity)}"></span>
      <span>${formatActivityName(a.activity)}</span>
    </div>
  `
    )
    .join("");
}

function renderActivityList(activities: ActivityPercentage[]): void {
  activityListEl.innerHTML = activities
    .map(
      (a) => `
    <div class="activity-item">
      <div class="activity-color" style="background: ${getColor(a.activity)}"></div>
      <div class="activity-info">
        <div class="activity-name">${formatActivityName(a.activity)}</div>
        <div class="activity-meta">${a.count} samples - ${a.category}</div>
      </div>
      <div class="activity-bar-container">
        <div class="activity-bar" style="width: ${a.percentage}%; background: ${getColor(a.activity)}"></div>
      </div>
      <div class="activity-pct">${a.percentage.toFixed(1)}%</div>
    </div>
  `
    )
    .join("");
}

function renderData(data: ActivityData): void {
  console.log("[renderData] data:", data);
  console.log("[renderData] totalActivities:", data.totalActivities);
  currentData = data;

  loadingEl.style.display = "none";

  if (data.totalActivities === 0) {
    console.log("[renderData] No activities, showing no-data view");
    noDataEl.style.display = "block";
    contentEl.style.display = "none";
    return;
  }

  noDataEl.style.display = "none";
  contentEl.style.display = "block";

  // Update summary cards
  workPctEl.textContent = `${data.workPercentage.toFixed(0)}%`;
  personalPctEl.textContent = `${data.personalPercentage.toFixed(0)}%`;
  idlePctEl.textContent = `${data.idlePercentage.toFixed(0)}%`;

  // Update date selector
  if (data.availableDates.length > 0) {
    dateSelect.innerHTML = data.availableDates
      .map(
        (d) =>
          `<option value="${d}" ${d === data.date ? "selected" : ""}>${d}</option>`
      )
      .join("");
  }

  // Render visualizations
  drawPieChart(data.activities);
  renderLegend(data.activities);
  renderActivityList(data.activities);
}

function extractData(result: CallToolResult): ActivityData | null {
  console.log("[extractData] result:", result);
  console.log("[extractData] structuredContent:", result.structuredContent);
  const data = result.structuredContent as ActivityData | undefined;
  return data ?? null;
}

function handleHostContextChanged(ctx: McpUiHostContext): void {
  if (ctx.theme) {
    applyDocumentTheme(ctx.theme);
  }
  if (ctx.styles?.variables) {
    applyHostStyleVariables(ctx.styles.variables);
  }
  if (ctx.styles?.css?.fonts) {
    applyHostFonts(ctx.styles.css.fonts);
  }
  if (ctx.safeAreaInsets) {
    mainEl.style.paddingTop = `${ctx.safeAreaInsets.top}px`;
    mainEl.style.paddingRight = `${ctx.safeAreaInsets.right}px`;
    mainEl.style.paddingBottom = `${ctx.safeAreaInsets.bottom}px`;
    mainEl.style.paddingLeft = `${ctx.safeAreaInsets.left}px`;
  }
  // Redraw chart when theme changes
  if (currentData) {
    drawPieChart(currentData.activities);
  }
}

// Create app instance
const app = new App({ name: "Zeit Activity Viz", version: "1.0.0" });

// Register handlers BEFORE connecting
app.onteardown = async () => {
  console.info("App is being torn down");
  return {};
};

app.ontoolinput = (params) => {
  console.info("Received tool call input:", params);
  loadingEl.style.display = "block";
  noDataEl.style.display = "none";
  contentEl.style.display = "none";
};

app.ontoolresult = (result) => {
  console.info("Received tool call result:", result);
  const data = extractData(result);
  if (data) {
    renderData(data);
  } else {
    loadingEl.style.display = "none";
    noDataEl.style.display = "block";
    contentEl.style.display = "none";
  }
};

app.ontoolcancelled = (params) => {
  console.info("Tool call cancelled:", params.reason);
  loadingEl.textContent = "Request cancelled";
};

app.onerror = console.error;

app.onhostcontextchanged = handleHostContextChanged;

// Date selector change handler
dateSelect.addEventListener("change", async () => {
  const selectedDate = dateSelect.value;
  if (selectedDate) {
    loadingEl.style.display = "block";
    loadingEl.textContent = "Loading activity data...";
    noDataEl.style.display = "none";
    contentEl.style.display = "none";

    try {
      const result = await app.callServerTool({
        name: "zeit-activity-viz",
        arguments: { date: selectedDate },
      });
      const data = extractData(result);
      if (data) {
        renderData(data);
      }
    } catch (e) {
      console.error("Error fetching data:", e);
      loadingEl.textContent = "Error loading data";
    }
  }
});

// Connect to host
app.connect().then(() => {
  const ctx = app.getHostContext();
  if (ctx) {
    handleHostContextChanged(ctx);
  }
});
