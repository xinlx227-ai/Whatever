# Domain docs

Read the root `GLOSSARY.md` before work involving domain terms, and read relevant ADRs under `docs/adr/`. Create the glossary only when the first term is resolved; create ADRs when decisions are made.

## Path compatibility

- Follow explicit paths in `AGENTS.md` and this file, then any `GLOSSARY-MAP.md` or `CONTEXT-MAP.md`.
- Preserve an existing `GLOSSARY.md` or legacy glossary `CONTEXT.md`; treat a generic `CONTEXT.md` as a glossary only when guidance or content establishes that role.
- If both naming schemes cover the same context without a canonical source, ask which is authoritative before changing domain documents.
- Use `GLOSSARY.md` for a new single-context glossary. Use `GLOSSARY-MAP.md` only when multiple bounded contexts warrant it.
- Read and write the same resolved files; preserve existing names, links, and unrelated sections.

Use glossary terms in issues, code, tests, and proposals. Surface conflicts with existing ADRs.
