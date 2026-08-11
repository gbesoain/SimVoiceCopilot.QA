using System;
using System.Collections.Generic;

namespace SimVoiceCopilot.QA.Reporting
{
    public sealed class QaReport
    {
        public string RunId { get; set; }
        public DateTimeOffset StartedAtLocal { get; set; }
        public DateTimeOffset FinishedAtLocal { get; set; }
        public string MachineName { get; set; }
        public string UserName { get; set; }
        public string OperatingSystem { get; set; }
        public string FrameworkVersion { get; set; }
        public string ConfigurationPath { get; set; }
        public string OutputDirectory { get; set; }
        public int? ApplicationProcessId { get; set; }
        public string ApplicationVersion { get; set; }
        public bool Success { get; set; }
        public string FatalError { get; set; }
        public List<TestCaseResult> Tests { get; set; }
        public List<ProcessMetricSample> Metrics { get; set; }
        public ResourceDeltaSummary ResourceDelta { get; set; }

        public QaReport()
        {
            Tests = new List<TestCaseResult>();
            Metrics = new List<ProcessMetricSample>();
            ResourceDelta = new ResourceDeltaSummary();
        }
    }

    public sealed class TestCaseResult
    {
        public string Name { get; set; }
        public DateTimeOffset StartedAtLocal { get; set; }
        public DateTimeOffset FinishedAtLocal { get; set; }
        public bool Passed { get; set; }
        public bool Skipped { get; set; }
        public string Message { get; set; }
        public string Error { get; set; }
        public List<TestStepResult> Steps { get; set; }

        public TestCaseResult()
        {
            Steps = new List<TestStepResult>();
        }
    }

    public sealed class TestStepResult
    {
        public int Sequence { get; set; }
        public string Name { get; set; }
        public int? Cycle { get; set; }
        public DateTimeOffset StartedAtLocal { get; set; }
        public DateTimeOffset FinishedAtLocal { get; set; }
        public bool Passed { get; set; }
        public string Message { get; set; }
        public string Error { get; set; }
        public string ScreenshotPath { get; set; }
    }

    public sealed class ProcessMetricSample
    {
        public DateTimeOffset TimestampLocal { get; set; }
        public string Label { get; set; }
        public int ProcessId { get; set; }
        public bool HasExited { get; set; }
        public bool? Responding { get; set; }
        public double WorkingSetMb { get; set; }
        public double PrivateMemoryMb { get; set; }
        public int HandleCount { get; set; }
        public int ThreadCount { get; set; }
        public double? CpuPercent { get; set; }
        public TimeSpan TotalProcessorTime { get; set; }
        public string Error { get; set; }
    }

    public sealed class ResourceDeltaSummary
    {
        public double WorkingSetGrowthMb { get; set; }
        public double PrivateMemoryGrowthMb { get; set; }
        public int HandleGrowth { get; set; }
        public int ThreadGrowth { get; set; }
        public bool WithinConfiguredThresholds { get; set; }
        public string Message { get; set; }
    }
}
