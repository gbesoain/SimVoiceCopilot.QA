using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Web.Script.Serialization;

namespace SimVoiceCopilot.QA.Reporting
{
    internal static class ReportWriter
    {
        public static void WriteAll(QaReport report, string outputRoot)
        {
            Directory.CreateDirectory(outputRoot);
            WriteJson(report, Path.Combine(outputRoot, "results.json"));
            WriteMetricsCsv(report, Path.Combine(outputRoot, "metrics.csv"));
            WriteHtml(report, Path.Combine(outputRoot, "report.html"));
        }

        private static void WriteJson(QaReport report, string path)
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer
            {
                MaxJsonLength = int.MaxValue,
                RecursionLimit = 100
            };

            File.WriteAllText(path, serializer.Serialize(report), new UTF8Encoding(false));
        }

        private static void WriteMetricsCsv(QaReport report, string path)
        {
            StringBuilder builder = new StringBuilder();
            builder.AppendLine("TimestampLocal,Label,ProcessId,HasExited,Responding,CpuPercent,WorkingSetMb,PrivateMemoryMb,HandleCount,ThreadCount,Error");
            foreach (ProcessMetricSample sample in report.Metrics.OrderBy(m => m.TimestampLocal))
            {
                builder.Append(Csv(sample.TimestampLocal.ToString("O"))).Append(',');
                builder.Append(Csv(sample.Label)).Append(',');
                builder.Append(sample.ProcessId.ToString(CultureInfo.InvariantCulture)).Append(',');
                builder.Append(sample.HasExited ? "true" : "false").Append(',');
                builder.Append(sample.Responding.HasValue ? (sample.Responding.Value ? "true" : "false") : string.Empty).Append(',');
                builder.Append(sample.CpuPercent.HasValue ? sample.CpuPercent.Value.ToString("0.00", CultureInfo.InvariantCulture) : string.Empty).Append(',');
                builder.Append(sample.WorkingSetMb.ToString("0.00", CultureInfo.InvariantCulture)).Append(',');
                builder.Append(sample.PrivateMemoryMb.ToString("0.00", CultureInfo.InvariantCulture)).Append(',');
                builder.Append(sample.HandleCount.ToString(CultureInfo.InvariantCulture)).Append(',');
                builder.Append(sample.ThreadCount.ToString(CultureInfo.InvariantCulture)).Append(',');
                builder.Append(Csv(sample.Error)).AppendLine();
            }

            File.WriteAllText(path, builder.ToString(), new UTF8Encoding(false));
        }

        private static void WriteHtml(QaReport report, string path)
        {
            int passed = report.Tests.Count(t => t.Passed);
            int failed = report.Tests.Count(t => !t.Passed && !t.Skipped);
            int skipped = report.Tests.Count(t => t.Skipped);

            StringBuilder html = new StringBuilder();
            html.AppendLine("<!doctype html>");
            html.AppendLine("<html lang=\"en\"><head><meta charset=\"utf-8\">");
            html.AppendLine("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">");
            html.AppendLine("<title>SimVoice Copilot QA Report</title>");
            html.AppendLine("<style>");
            html.AppendLine("body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#202124;background:#f6f8fa}");
            html.AppendLine(".card{background:#fff;border:1px solid #d0d7de;border-radius:8px;padding:18px;margin:14px 0}");
            html.AppendLine(".pass{color:#137333}.fail{color:#b3261e}.skip{color:#8250df}");
            html.AppendLine("table{width:100%;border-collapse:collapse}th,td{border-bottom:1px solid #d8dee4;padding:8px;text-align:left;vertical-align:top}");
            html.AppendLine("code,pre{font-family:Consolas,monospace;white-space:pre-wrap;overflow-wrap:anywhere}");
            html.AppendLine(".muted{color:#57606a}.metric{display:inline-block;margin-right:24px}");
            html.AppendLine("</style></head><body>");

            html.AppendLine("<h1>SimVoice Copilot QA Report</h1>");
            html.Append("<div class=\"card\"><h2 class=\"")
                .Append(report.Success ? "pass" : "fail")
                .Append("\">")
                .Append(report.Success ? "PASS" : "FAIL")
                .AppendLine("</h2>");
            html.Append("<div class=\"metric\"><strong>Passed:</strong> ").Append(passed).AppendLine("</div>");
            html.Append("<div class=\"metric\"><strong>Failed:</strong> ").Append(failed).AppendLine("</div>");
            html.Append("<div class=\"metric\"><strong>Skipped:</strong> ").Append(skipped).AppendLine("</div>");
            html.Append("<p class=\"muted\">Run ").Append(E(report.RunId))
                .Append(" · ").Append(E(report.StartedAtLocal.ToString("G")))
                .Append(" · ").Append(E(report.MachineName)).AppendLine("</p></div>");

            html.AppendLine("<div class=\"card\"><h2>Application and environment</h2><table>");
            Row(html, "Process ID", report.ApplicationProcessId.HasValue ? report.ApplicationProcessId.Value.ToString() : string.Empty);
            Row(html, "Application version", report.ApplicationVersion);
            Row(html, "Operating system", report.OperatingSystem);
            Row(html, ".NET runtime", report.FrameworkVersion);
            Row(html, "Configuration", report.ConfigurationPath);
            Row(html, "Output", report.OutputDirectory);
            html.AppendLine("</table></div>");

            html.AppendLine("<div class=\"card\"><h2>Tests</h2>");
            foreach (TestCaseResult test in report.Tests)
            {
                string css = test.Skipped ? "skip" : (test.Passed ? "pass" : "fail");
                string status = test.Skipped ? "SKIPPED" : (test.Passed ? "PASS" : "FAIL");
                html.Append("<h3 class=\"").Append(css).Append("\">")
                    .Append(E(status)).Append(" — ").Append(E(test.Name)).AppendLine("</h3>");
                if (!string.IsNullOrWhiteSpace(test.Message))
                {
                    html.Append("<p>").Append(E(test.Message)).AppendLine("</p>");
                }
                if (!string.IsNullOrWhiteSpace(test.Error))
                {
                    html.Append("<pre class=\"fail\">").Append(E(test.Error)).AppendLine("</pre>");
                }

                if (test.Steps.Count > 0)
                {
                    html.AppendLine("<table><thead><tr><th>#</th><th>Cycle</th><th>Step</th><th>Status</th><th>Details</th><th>Evidence</th></tr></thead><tbody>");
                    foreach (TestStepResult step in test.Steps)
                    {
                        html.Append("<tr><td>").Append(step.Sequence).Append("</td><td>")
                            .Append(step.Cycle.HasValue ? step.Cycle.Value.ToString() : string.Empty)
                            .Append("</td><td>").Append(E(step.Name)).Append("</td><td class=\"")
                            .Append(step.Passed ? "pass" : "fail").Append("\">")
                            .Append(step.Passed ? "PASS" : "FAIL").Append("</td><td>")
                            .Append(E(string.IsNullOrWhiteSpace(step.Error) ? step.Message : step.Error))
                            .Append("</td><td>");
                        if (!string.IsNullOrWhiteSpace(step.ScreenshotPath))
                        {
                            string relative = MakeRelativePath(Path.GetDirectoryName(path), step.ScreenshotPath);
                            html.Append("<a href=\"").Append(E(relative.Replace('\\', '/'))).Append("\">screenshot</a>");
                        }
                        html.AppendLine("</td></tr>");
                    }
                    html.AppendLine("</tbody></table>");
                }
            }
            html.AppendLine("</div>");

            ResourceDeltaSummary delta = report.ResourceDelta ?? new ResourceDeltaSummary();
            html.AppendLine("<div class=\"card\"><h2>Resource delta</h2><table>");
            Row(html, "Working set growth", delta.WorkingSetGrowthMb.ToString("0.00", CultureInfo.InvariantCulture) + " MB");
            Row(html, "Private memory growth", delta.PrivateMemoryGrowthMb.ToString("0.00", CultureInfo.InvariantCulture) + " MB");
            Row(html, "Handle growth", delta.HandleGrowth.ToString(CultureInfo.InvariantCulture));
            Row(html, "Thread growth", delta.ThreadGrowth.ToString(CultureInfo.InvariantCulture));
            Row(html, "Threshold evaluation", delta.Message);
            html.AppendLine("</table></div>");

            if (!string.IsNullOrWhiteSpace(report.FatalError))
            {
                html.Append("<div class=\"card\"><h2 class=\"fail\">Fatal error</h2><pre>")
                    .Append(E(report.FatalError)).AppendLine("</pre></div>");
            }

            html.AppendLine("</body></html>");
            File.WriteAllText(path, html.ToString(), new UTF8Encoding(false));
        }

        private static void Row(StringBuilder html, string name, string value)
        {
            html.Append("<tr><th>").Append(E(name)).Append("</th><td>")
                .Append(E(value ?? string.Empty)).AppendLine("</td></tr>");
        }

        private static string E(string value)
        {
            return WebUtility.HtmlEncode(value ?? string.Empty);
        }

        private static string Csv(string value)
        {
            value = value ?? string.Empty;
            return "\"" + value.Replace("\"", "\"\"") + "\"";
        }

        private static string MakeRelativePath(string baseDirectory, string fullPath)
        {
            Uri baseUri = new Uri(AppendDirectorySeparatorChar(Path.GetFullPath(baseDirectory)));
            Uri fileUri = new Uri(Path.GetFullPath(fullPath));
            return Uri.UnescapeDataString(baseUri.MakeRelativeUri(fileUri).ToString());
        }

        private static string AppendDirectorySeparatorChar(string path)
        {
            if (!path.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal))
            {
                return path + Path.DirectorySeparatorChar;
            }

            return path;
        }
    }
}
