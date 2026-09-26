# M3 native tool control

Hermes reference HEAD `959c7649fd806c3996cdd845ee4bd4e0eb1a0276`: desktop tool schemas are filtered by toolset and `check_fn` (`model_tools.py:505–515`; `tools/registry.py:843–871`), but ordinary dispatch invokes a registered handler by name without rechecking the advertised set (`tools/registry.py:893–910`; `model_tools.py:834–845,940–956`).

Yanuseu does not ship desktop tools. Its typed `ToolCapability` registry currently exposes only local arithmetic. The selected profile’s saved permission is snapshotted into a foreground turn; the same policy filters provider schemas, gates the runtime before any injected tool executes, and gates the native executor again. Unknown or disabled calls produce a paired denial result, not an action. `/tools` opens a native profile-scoped control screen. No shell, arbitrary filesystem, subprocess, plugin execution, stdio MCP, or background work is implied.
