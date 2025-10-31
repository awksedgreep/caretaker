# Release Checklist

Use this checklist to prepare a release (v0.1.0 target).

1) Verify code quality
- mix format
- mix test (no limiting flags)
- Ensure no Logger warnings you care about at default level

2) Docs
- mix docs (ensure docs build)
- Review README and guides (docs/phase-5-cpe-client.md, docs/telemetry.md)

3) Version & metadata
- Update version in mix.exs if needed
- Verify package metadata (licenses, links, description)

4) Changelog
- Create/Update CHANGELOG.md with highlights since last release

5) Tag & publish
- git add -A && git commit -m "v0.1.0"
- git tag v0.1.0
- mix hex.publish (review prompts)

Note: Follow AGENTS.md rules — stage all changes before committing; avoid adding deps without approval; no IO.puts/IO.inspect.
