using System;
using System.Globalization;
using System.IO;

namespace SimVoiceCopilot.QA.SimConnectOracle.Infrastructure
{
    internal sealed class OracleLogger : IDisposable
    {
        private readonly object sync = new object();
        private readonly StreamWriter writer;

        public OracleLogger(string path)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            writer = new StreamWriter(path, false) { AutoFlush = true };
        }

        public void Info(string message) { Write("INFO", message); }
        public void Warn(string message) { Write("WARN", message); }
        public void Error(string message) { Write("ERROR", message); }

        public void Error(string message, Exception exception)
        {
            Write("ERROR", message + Environment.NewLine + exception);
        }

        private void Write(string level, string message)
        {
            string line = string.Format(
                CultureInfo.InvariantCulture,
                "{0:yyyy-MM-dd HH:mm:ss.fff zzz} [{1}] {2}",
                DateTimeOffset.Now,
                level,
                message ?? string.Empty);

            lock (sync)
            {
                writer.WriteLine(line);
            }

            Console.WriteLine(line);
        }

        public void Dispose()
        {
            writer.Dispose();
        }
    }
}
