# Include the declared MIT license in packages

Issue: [#49](https://github.com/carsonSgit/scour/issues/49).

| Priority | Effort | Change risk | Confidence | Audited commit |
|---|---|---|---|---|
| P1 | S | LOW | HIGH: code or repository evidence | afd5f4d |

## Current gap

scour.nimble declares MIT, but tracked files contain no license text. Release archive steps package only binary and README.

## Work

Add the MIT notice with the maintainer-confirmed copyright holder and include it in every source/binary distribution.

## Acceptance

- [ ] The repository contains the intended LICENSE.
- [ ] All five platform archives and the CI image carry the same notice.
- [ ] Archive validation verifies its presence and content.
- [ ] README links to the license.

## Scope and verification

LICENSE, .github/workflows/release.yml, container packaging, README.md.

Run `nimble test -y` for core changes and `bash tests/test_distribution.sh` for integration changes. Add the named regression cases. Record real pipeline/artifact evidence where required.

Readiness item 019.

## Dependencies

None.
