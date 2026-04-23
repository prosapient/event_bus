# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-23

### Added

- Initial extraction from internal umbrella project.
- `EventBus.publish/1` for dispatching events to registered handlers.
- `EventBus.Handler` behaviour with optional `interested?/1` and `oban_options/0` callbacks.
- `EventBus.Partitioned` protocol for sequential per-key event processing.
- Pluggable backends: `EventBus.Backend.Oban` (default), `EventBus.Backend.Inline`,
  `EventBus.Backend.ProcessMailbox`.
- `EventBus.Testing` helpers: `set_event_bus_mode/1`, `assert_event_published/1`,
  `run_event/2`, `run_event!/2`, `allow_event_bus/1`.

[Unreleased]: https://github.com/prosapient/event_bus/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/prosapient/event_bus/releases/tag/v0.1.0
