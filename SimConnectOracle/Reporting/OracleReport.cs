using System;
using System.Collections.Generic;
using SimVoiceCopilot.QA.SimConnectOracle.Oracle;

namespace SimVoiceCopilot.QA.SimConnectOracle.Reporting
{
    public sealed class OracleReport
    {
        public string RunId { get; set; }
        public string Mode { get; set; }
        public DateTimeOffset StartedAtLocal { get; set; }
        public DateTimeOffset FinishedAtLocal { get; set; }
        public string MachineName { get; set; }
        public string UserName { get; set; }
        public string OperatingSystem { get; set; }
        public string FrameworkVersion { get; set; }
        public string OutputDirectory { get; set; }
        public bool Success { get; set; }
        public string Message { get; set; }
        public string Error { get; set; }
        public string Variable { get; set; }
        public string Expected { get; set; }
        public double Tolerance { get; set; }
        public OracleAssertionResult Assertion { get; set; }
        public List<OracleSnapshot> Snapshots { get; set; }

        public OracleReport()
        {
            Snapshots = new List<OracleSnapshot>();
        }
    }
}
