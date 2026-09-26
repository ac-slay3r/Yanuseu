# M3 command discovery: Hermes behavior and iOS boundary

Hermes keeps slash commands in `hermes_cli/commands.py` (`COMMAND_REGISTRY`); autocomplete and `/help` derive from that registry. The iOS app has its own small `AppCommand.registry` for **implemented native commands only**, shared by slash parsing, live suggestions, `/help`, and the command palette. It does not claim parity with desktop-only commands such as shell, editor, gateway, cron, or process control.

Commands are handled on-device and are not sent as prompts to a provider. `/tools` reports the actual local calculator permission; unknown commands remain local. The only model-callable tool remains the opt-in, bounded calculator. This slice does not yet add installable skills or new tool capabilities.
