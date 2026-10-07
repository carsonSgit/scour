# Scope drift checks to workspaces and parse CI command context

Issue: [#37](https://github.com/carsonSgit/scour/issues/37).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P1 | L | MED | HIGH: code or repository evidence | afd5f4d |

## Current gap

src/scourpkg/rules/cross_reference.nim:288 merges scripts from every package into one inventory. CI checks at line 419 recognize only GitHub workflows. workflowRunCommands ignores working-directory semantics.

## Work

Resolve commands against their package/task root and effective working directory. Scope env examples to the owning workspace with a documented shared-root option. Parse supported GitHub and GitLab YAML structures rather than matching unrelated indented text. Keep provider-specific action pinning separate.

## Acceptance

- [ ] Two packages with different scripts cannot validate each other's missing commands.
- [ ] GitHub working-directory, multiline run blocks, GitLab script/before_script, and YAML quoting have fixtures.
- [ ] Unknown dynamic commands are reported as unsupported context rather than confidently broken.
- [ ] Workspace env contracts remain isolated.
- [ ] No repository command is executed during scanning.

## Scope and verification

src/scourpkg/rules/cross_reference.nim, src/scourpkg/config.nim, tests/test_cli_setup.nim.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 007.

## Dependencies

[#31](https://github.com/carsonSgit/scour/issues/31), [#34](https://github.com/carsonSgit/scour/issues/34).
