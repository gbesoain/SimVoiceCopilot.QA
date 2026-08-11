using System;
using System.IO;
using System.Text;

namespace SimVoiceCopilot.QA.Infrastructure
{
    internal sealed class Logger : IDisposable
    {
        private readonly object sync = new object();
        private readonly StreamWriter writer;

        public Logger(string path)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            writer = new StreamWriter(path, false, new UTF8Encoding(false));
            writer.AutoFlush = true;
        }

        public void Info(string message)
        {
            Write("INFO", message);
        }

        public void Warn(string message)
        {
            Write("WARN", message);
        }

        public void Error(string message)
        {
            Write("ERROR", message);
        }

        public void Error(string message, Exception exception)
        {
            Write("ERROR", message + Environment.NewLine + exception);
        }

        private void Write(string level, string message)
        {
            string line = string.Format(
                "{0:yyyy-MM-dd HH:mm:ss.fff zzz} [{1}] {2}",
                DateTimeOffset.Now,
                level,
                message);

            lock (sync)
            {
                writer.WriteLine(line);
                Console.WriteLine(line);
            }
        }

        public void Dispose()
        {
            writer.Dispose();
        }
    }
}
