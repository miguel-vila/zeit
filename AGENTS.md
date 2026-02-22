# CLAUDE.md

**Updated:** 2026-02-21 | **Branch:** main

## Overview

macOS activity tracker: periodic screenshots → LLM vision model → activity classification → SQLite storage. Single Swift executable runs as both menubar app (GUI) and CLI. Scheduled via launchd.

For detailed documentation see:

- [Architecture](ARCHITECTURE.md) - Component design, patterns, and how they connect
- [Build & Installation](docs/BUILD.md) - Development and distribution builds
- [Product Specs](docs/product-specs/index.md) - Feature descriptions and behavior
  - [Onboarding](docs/product-specs/onboarding.md)
  - [Menubar](docs/product-specs/menubar.md)
  - [Recurring Tracking](docs/product-specs/recurring-tracking.md)
  - [CLI](docs/product-specs/cli.md)

## Where to Look

| Task | Location |
|------|----------|
| Add CLI command | `Sources/ZeitApp/CLI/` (ZeitCLI.swift routes to subcommands) |
| Modify LLM prompts | `Sources/ZeitApp/LLM/Prompts.swift` |
| Change screenshot behavior | `Sources/ZeitApp/Core/ScreenCapture.swift` |
| Modify idle detection | `Sources/ZeitApp/Core/IdleDetection.swift` |
| Add menubar features | `Sources/ZeitApp/Features/Menubar/` (MenubarFeature + MenubarView) |
| Add new UI feature | `Sources/ZeitApp/Features/` (TCA reducer + SwiftUI view) |
| Add dependency client | `Sources/ZeitApp/Clients/` (use @DependencyClient) |
| Change database schema | `Sources/ZeitApp/Clients/DatabaseClient.swift` |
| Change data paths | `Sources/ZeitApp/Core/ZeitConfig.swift` |
| Add LLM provider | `Sources/ZeitApp/LLM/` (conform to LLMProvider/VisionLLMProvider) |
| Modify build process | `build.sh` |

## Code Conventions

- Swift concurrency: async/await throughout, Sendable types
- TCA (Composable Architecture) for all UI features (reducer + view pairs)
- @DependencyClient for testable service interfaces
- Actor-based database access (thread-safe GRDB)
- Protocol-based LLM providers (LLMProvider, VisionLLMProvider)
- Modern SwiftUI patterns (@State, @Binding, ViewStore)
