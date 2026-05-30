import github_output, issues, json_output, scan_plan, text_output

proc renderIssues*(issues: openArray[Issue]; options: CliOptions): string =
  case options.outputFormat
  of formatText: text_output.renderIssues(issues, options.colorMode)
  of formatJson: renderJsonIssues(issues)
  of formatGitHub: renderGitHubIssues(issues)
