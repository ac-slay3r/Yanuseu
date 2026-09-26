# M3 local skill evidence and boundaries

Hermes reference checkout at `959c7649fd806c3996cdd845ee4bd4e0eb1a0276`:

- `agent/skill_utils.py:103–123,141–148,199–216` parses frontmatter, checks platforms and load requirements. Yanuseu reads a **small supported subset** (`name`, `description`, optional `platforms` including `ios`) from a user-selected UTF-8 SKILL.md; unsupported declarations fail closed. This is not a full Hermes YAML/skill-package loader.
- `agent/skill_utils.py:533–583` and `tools/skills_tool.py:539–548` quarantine certain trusted project skills. Yanuseu instead requires explicit in-app text inspection and per-profile enablement for every import/replacement; this is user review, **not an automated safety audit**.
- `agent/skill_preprocessing.py:46–69,98–112` can expand shell-bearing skill text and `tools/skills_tool.py:634–659` can install dependencies in the desktop runtime. Yanuseu does neither. It stores text under iOS file protection, never opens referenced paths, and never runs scripts or installs packages.
- Desktop tool schemas can be filtered at offer-time (`model_tools.py:505–515`), but ordinary dispatch by registered name is not itself a per-session authorization check (`tools/registry.py:893–910`). A skill is only provider-sent guidance; the opt-in calculator gate remains enforced separately at execution. No skill can enable a tool.
