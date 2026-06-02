import doctor_output, github_output, issues, json_output, scan_plan, text_output

proc renderIssues*(issues: openArray[Issue]; options: CliOptions): string =
  if options.scoreOnly:
    return $scoreIssues(issues).current & "\n"
  case options.outputFormat
  of formatText: text_output.renderIssues(issues, options.colorMode)
  of formatJson: renderJsonIssues(issues)
  of formatGitHub: renderGitHubIssues(issues)
  of formatDoctor: renderDoctorIssues(issues, options.colorMode)
