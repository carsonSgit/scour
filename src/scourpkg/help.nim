const version* = "scour 0.4.5"

const helpText* = """
scour 0.4.5

Usage:
  scour [options] [paths...]
  scour triage [options] [paths...]
  scour [--config <path>] rules
  scour [--config <path>] explain <rule>

Options:
  --help           Show this help text.
  --version        Show version information.
  --score          Output only the numeric score for the scan.
  --staged         Scan staged Git changes.
  --since <ref>    Compare HEAD against <ref> using merge-base semantics
                   (git <ref>...HEAD); an unreachable ref fails the scan.
  --all            Scan all files under the repository root.
                   Default without a mode flag in any folder.
  --config <path>  Use an explicit config file.
  --format <value> Output format: text, json, github, or doctor.
  --fail-on <level> Fail on: error, warning, or info.
  --exit-zero      Return success even when findings meet the threshold.
  --color <value>  Color mode: auto, always, or never.
  --fix            Plan fixes and write scour-fix.patch without changing files.
  --fix-apply      Apply the planned fixes, then rerun the scan.
"""
