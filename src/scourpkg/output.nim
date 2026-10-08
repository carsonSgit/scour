import codequality_output, doctor_output, github_output, issues, json_output,
    sarif_output, scan_plan, text_output

proc renderIssues*(issues: openArray[Issue]; options: CliOptions;
    plan: ScanPlan): string =
  if options.scoreOnly:
    return $scoreIssues(issues).current & "\n"
  case options.outputFormat
  of formatText: text_output.renderIssues(issues, options.colorMode)
  of formatJson: renderJsonIssues(issues, plan)
  of formatGitHub: renderGitHubIssues(issues)
  of formatDoctor: renderDoctorIssues(issues, options.colorMode)
  of formatCodequality: renderCodequalityIssues(issues, plan)
  of formatSarif: renderSarifIssues(issues, plan)
