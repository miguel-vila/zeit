# Zeit Activity Viz MCP App

Visualizes activity percentages from Zeit tracker data.

## Build

```bash
npm install
npm run build
```

## Run

```bash
ZEIT_CLI="uv run zeit" npm run serve
# Server at http://127.0.0.1:3001/mcp
```

For stdio transport: `ZEIT_CLI="uv run zeit" tsx main.ts --stdio`
