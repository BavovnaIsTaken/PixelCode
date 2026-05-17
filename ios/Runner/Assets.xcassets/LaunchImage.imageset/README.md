# Launch Screen Assets

You can customize the launch screen with your own desired assets by replacing the image files in this directory.

You can also do it by opening your Flutter project's Xcode project with `open ios/Runner.xcworkspace`, selecting `Runner/Assets.xcassets` in the Project Navigator and dropping in the desired images.

## LeanKG Setup

LeanKG is a local-first knowledge graph for AI-assisted development. It indexes the codebase and exposes an MCP server that Claude Code queries for context.

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/FreePeak/LeanKG/main/scripts/install.sh | bash -s -- claude
```

### Initialize & index the project

```bash
leankg init
leankg index
```

### Start MCP server (port 3000)

```bash
leankg serve
```

### Configuration

Project-level config lives in [leankg.yaml](../../../../leankg.yaml) at the repo root. Key settings:

- `indexer.include` — file globs to index (`.ts`, `.js`, `.kt`, `.dart`)
- `indexer.exclude` — paths to skip (`node_modules`, `build`, `.dart_tool`, etc.)
- `mcp.port` — MCP server port (default: 3000)
- `mcp.auto_index_on_start` — re-index automatically on server start

### Update

```bash
curl -fsSL https://raw.githubusercontent.com/FreePeak/LeanKG/main/scripts/install.sh | bash -s -- update
```