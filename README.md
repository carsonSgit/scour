# scour

[![CI](https://github.com/carsonSgit/scour/actions/workflows/ci.yml/badge.svg)](https://github.com/carsonSgit/scour/actions/workflows/ci.yml)

Fast pre-merge checks for repo hygiene, config drift, and PR mistakes.

## Commands

```sh
nimble build
nimble run
nimble test
nim c -r src/scour.nim -- --help
```

## Automation

Pull requests and pushes to `main` run the CI workflow:

```sh
nimble build -y
nimble test -y
nim c -r src/scour.nim -- --help
nim c -r src/scour.nim -- --version
```

Releases are built by `.github/workflows/release.yml`. Pushing a `v*` tag publishes release archives for Linux, macOS, and Windows. The release workflow can also be started manually from GitHub Actions to validate packaging before tagging.
