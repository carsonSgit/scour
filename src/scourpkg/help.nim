const version* = "scour 0.3.1"

const helpText* = """
scour 0.3.1

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
  --since <ref>    Scan changes since a Git ref.
  --all            Scan all files under the repository root.
  --config <path>  Use an explicit config file.
  --format <value> Output format: text, json, github, or doctor.
  --fail-on <level> Fail on: error, warning, or info.
  --exit-zero      Return success even when findings meet the threshold.
  --color <value>  Color mode: auto, always, or never.
"""
