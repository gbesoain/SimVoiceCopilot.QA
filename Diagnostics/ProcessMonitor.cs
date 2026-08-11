using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using SimVoiceCopilot.QA.Infrastructure;
using SimVoiceCopilot.QA.Reporting;

namespace SimVoiceCopilot.QA.Diagnostics
{
    internal sealed class ProcessMonitor : IDisposable
    {
        private readonly Process process;
        private readonly int intervalMs;
        private readonly Logger logger;
        private readonly List<ProcessMetricSample> samples;
        private readonly object sync;
        private readonly ManualResetEvent stopEvent;
        private Thread worker;

        public ProcessMonitor(Process process, int intervalMs, List<ProcessMetricSample> samples, Logger logger)
        {
            this.process = process;
            this.intervalMs = Math.Max(250, intervalMs);
            this.samples = samples;
            this.logger = logger;
            sync = new object();
            stopEvent = new ManualResetEvent(false);
        }

        public void Start()
        {
            if (worker != null)
            {
                return;
            }

            worker = new Thread(Run)
            {
                IsBackground = true,
                Name = "SimVoiceCopilot.QA.ProcessMonitor"
            };
            worker.Start();
        }

        public void Stop()
        {
            stopEvent.Set();
            if (worker != null && worker.IsAlive)
            {
                worker.Join(3000);
            }
        }

        public ProcessMetricSample TakeSnapshot(string label)
        {
            ProcessMetricSample sample = Capture(label, null, null);
            Add(sample);
            return sample;
        }

        private void Run()
        {
            TimeSpan? previousCpu = null;
            DateTimeOffset? previousTimestamp = null;

            while (!stopEvent.WaitOne(0))
            {
                ProcessMetricSample sample = Capture("periodic", previousCpu, previousTimestamp);
                Add(sample);

                previousCpu = sample.TotalProcessorTime;
                previousTimestamp = sample.TimestampLocal;

                if (stopEvent.WaitOne(intervalMs))
                {
                    break;
                }
            }
        }

        private ProcessMetricSample Capture(
            string label,
            TimeSpan? previousCpu,
            DateTimeOffset? previousTimestamp)
        {
            ProcessMetricSample sample = new ProcessMetricSample
            {
                TimestampLocal = DateTimeOffset.Now,
                Label = label
            };

            try
            {
                process.Refresh();
                sample.ProcessId = process.Id;
                sample.HasExited = process.HasExited;
                if (sample.HasExited)
                {
                    return sample;
                }

                sample.WorkingSetMb = BytesToMb(process.WorkingSet64);
                sample.PrivateMemoryMb = BytesToMb(process.PrivateMemorySize64);
                sample.HandleCount = process.HandleCount;
                sample.ThreadCount = process.Threads.Count;
                sample.TotalProcessorTime = process.TotalProcessorTime;

                try
                {
                    sample.Responding = process.Responding;
                }
                catch
                {
                    sample.Responding = null;
                }

                if (previousCpu.HasValue && previousTimestamp.HasValue)
                {
                    double elapsedMs = (sample.TimestampLocal - previousTimestamp.Value).TotalMilliseconds;
                    double cpuMs = (sample.TotalProcessorTime - previousCpu.Value).TotalMilliseconds;
                    if (elapsedMs > 0)
                    {
                        sample.CpuPercent = Math.Max(
                            0,
                            Math.Min(100, cpuMs / elapsedMs * 100.0 / Environment.ProcessorCount));
                    }
                }
            }
            catch (Exception ex)
            {
                sample.Error = ex.Message;
            }

            return sample;
        }

        private void Add(ProcessMetricSample sample)
        {
            lock (sync)
            {
                samples.Add(sample);
            }
        }

        private static double BytesToMb(long bytes)
        {
            return Math.Round(bytes / 1024.0 / 1024.0, 2);
        }

        public void Dispose()
        {
            Stop();
            stopEvent.Dispose();
        }
    }
}
