# Issue tracker: GitHub

Issues and specs live in GitHub Issues for `xinlx227-ai/Whatever`. Use `gh` from this repository.

## Operations

- Create: `gh issue create --title "..." --body-file <file>`.
- Read: `gh issue view <number> --comments`.
- List: `gh issue list --state open --json number,title,body,labels,comments`.
- Comment: `gh issue comment <number> --body-file <file>`.
- Label: `gh issue edit <number> --add-label "..."` or `--remove-label "..."`.
- Close: `gh issue close <number> --comment "..."`.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Skill terms

"Publish to the issue tracker" means create a GitHub issue. "Fetch the relevant ticket" means read the issue and its comments.

## Wayfinding

Use one `wayfinder:map` issue with child issues. Link children as GitHub sub-issues; use a task list and `Part of #<map>` when sub-issues are unavailable. Represent blockers with native issue dependencies; fall back to `Blocked by: #<n>`. Claim an unblocked, unassigned child with `gh issue edit <n> --add-assignee @me`. Record the answer, close the child, and add a short decision pointer to the map.
