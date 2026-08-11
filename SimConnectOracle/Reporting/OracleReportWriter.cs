using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Web.Script.Serialization;
using SimVoiceCopilot.QA.SimConnectOracle.Oracle;

namespace SimVoiceCopilot.QA.SimConnectOracle.Reporting
{
    internal static class OracleReportWriter
    {
        public static void WriteAll(OracleReport report, string outputDirectory)
        {
            Directory.CreateDirectory(outputDirectory);
            WriteJson(report, Path.Combine(outputDirectory, "oracle-report.json"));
            WriteCsv(report, Path.Combine(outputDirectory, "oracle-snapshots.csv"));
            WriteHtml(report, Path.Combine(outputDirectory, "oracle-report.html"));
        }

        private static void WriteJson(OracleReport report, string path)
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
            File.WriteAllText(path, serializer.Serialize(report), new UTF8Encoding(false));
        }

        private static void WriteCsv(OracleReport report, string path)
        {
            StringBuilder text = new StringBuilder();
            text.AppendLine("TimestampLocal,FlightActive,DialogMode,AircraftTitle,AtcModel,OnGround,PlaneAltitudeFeet,IndicatedAltitudeFeet,PlaneHeadingDegrees,HeadingBugDegrees,SelectedAltitudeFeet,SelectedVerticalSpeedFpm,TransponderCode,AutopilotAvailable,AutopilotMaster,HeadingHold,AltitudeHold,VerticalSpeedHold,ParkingBrake,GearHandlePosition,FlapsHandleIndex,FuelGallons,WindDirectionDegrees,WindSpeedKnots,GroundSpeedKnots,SimulationRate");

            foreach (OracleSnapshot item in report.Snapshots)
            {
                text.Append(Csv(item.TimestampLocal.ToString("O", CultureInfo.InvariantCulture))).Append(',')
                    .Append(Bool(item.FlightActive)).Append(',')
                    .Append(item.DialogMode.ToString(CultureInfo.InvariantCulture)).Append(',')
                    .Append(Csv(item.AircraftTitle)).Append(',')
                    .Append(Csv(item.AtcModel)).Append(',')
                    .Append(Bool(item.OnGround)).Append(',')
                    .Append(Number(item.PlaneAltitudeFeet)).Append(',')
                    .Append(Number(item.IndicatedAltitudeFeet)).Append(',')
                    .Append(Number(item.PlaneHeadingMagneticDegrees)).Append(',')
                    .Append(Number(item.HeadingBugDegrees)).Append(',')
                    .Append(Number(item.SelectedAltitudeFeet)).Append(',')
                    .Append(Number(item.SelectedVerticalSpeedFpm)).Append(',')
                    .Append(item.TransponderCode.ToString("0000", CultureInfo.InvariantCulture)).Append(',')
                    .Append(Bool(item.AutopilotAvailable)).Append(',')
                    .Append(Bool(item.AutopilotMaster)).Append(',')
                    .Append(Bool(item.HeadingHold)).Append(',')
                    .Append(Bool(item.AltitudeHold)).Append(',')
                    .Append(Bool(item.VerticalSpeedHold)).Append(',')
                    .Append(Bool(item.ParkingBrake)).Append(',')
                    .Append(Number(item.GearHandlePosition)).Append(',')
                    .Append(Number(item.FlapsHandleIndex)).Append(',')
                    .Append(Number(item.FuelTotalQuantityGallons)).Append(',')
                    .Append(Number(item.WindDirectionDegrees)).Append(',')
                    .Append(Number(item.WindSpeedKnots)).Append(',')
                    .Append(Number(item.GroundSpeedKnots)).Append(',')
                    .Append(Number(item.SimulationRate))
                    .AppendLine();
            }

            File.WriteAllText(path, text.ToString(), new UTF8Encoding(false));
        }

        private static void WriteHtml(OracleReport report, string path)
        {
            OracleSnapshot latest = report.Snapshots.LastOrDefault();
            StringBuilder html = new StringBuilder();
            html.Append("<!doctype html><html><head><meta charset='utf-8'><title>SimConnect Oracle</title>")
                .Append("<style>body{font-family:Segoe UI,Arial;margin:28px;color:#222}h1{margin-bottom:4px}.pass{color:#187a2f}.fail{color:#b42318}table{border-collapse:collapse;margin-top:18px}th,td{border:1px solid #ccc;padding:7px 10px;text-align:left}th{background:#f2f2f2}code{background:#f4f4f4;padding:2px 4px}</style></head><body>")
                .Append("<h1>SimVoice Copilot QA — SimConnect Oracle</h1>")
                .Append("<p class='").Append(report.Success ? "pass" : "fail").Append("'><strong>")
                .Append(report.Success ? "PASS" : "FAIL").Append("</strong> — ")
                .Append(WebUtility.HtmlEncode(report.Message ?? string.Empty)).Append("</p>")
                .Append("<p>Mode: <code>").Append(WebUtility.HtmlEncode(report.Mode)).Append("</code><br>")
                .Append("Run: <code>").Append(WebUtility.HtmlEncode(report.RunId)).Append("</code><br>")
                .Append("Snapshots: ").Append(report.Snapshots.Count.ToString(CultureInfo.InvariantCulture)).Append("</p>");

            if (report.Assertion != null)
            {
                html.Append("<h2>Assertion</h2><table><tr><th>Variable</th><th>Expected</th><th>Observed</th><th>Tolerance</th><th>Difference</th><th>Result</th></tr><tr><td>")
                    .Append(WebUtility.HtmlEncode(report.Assertion.Variable)).Append("</td><td>")
                    .Append(WebUtility.HtmlEncode(report.Assertion.Expected)).Append("</td><td>")
                    .Append(WebUtility.HtmlEncode(report.Assertion.Observed)).Append("</td><td>")
                    .Append(Number(report.Assertion.Tolerance)).Append("</td><td>")
                    .Append(Number(report.Assertion.Difference)).Append("</td><td>")
                    .Append(report.Assertion.Passed ? "PASS" : "FAIL").Append("</td></tr></table>");
            }

            if (latest != null)
            {
                html.Append("<h2>Latest snapshot</h2><table>");
                foreach (var pair in latest.ToVariableDictionary())
                {
                    html.Append("<tr><th>").Append(WebUtility.HtmlEncode(pair.Key)).Append("</th><td>")
                        .Append(WebUtility.HtmlEncode(Convert.ToString(pair.Value, CultureInfo.InvariantCulture))).Append("</td></tr>");
                }
                html.Append("</table>");
            }

            if (!string.IsNullOrWhiteSpace(report.Error))
            {
                html.Append("<h2>Error</h2><pre>").Append(WebUtility.HtmlEncode(report.Error)).Append("</pre>");
            }

            html.Append("</body></html>");
            File.WriteAllText(path, html.ToString(), new UTF8Encoding(false));
        }

        private static string Bool(bool value) { return value ? "1" : "0"; }
        private static string Number(double value) { return value.ToString("0.########", CultureInfo.InvariantCulture); }

        private static string Csv(string value)
        {
            string text = value ?? string.Empty;
            return "\"" + text.Replace("\"", "\"\"") + "\"";
        }
    }
}
