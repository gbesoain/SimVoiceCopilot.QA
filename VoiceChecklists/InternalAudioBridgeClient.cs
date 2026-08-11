using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace SimVoiceCopilot.QA.VoiceChecklists
{
    internal sealed class InternalAudioBridgeClient
    {
        private readonly string pipeName;
        private readonly JavaScriptSerializer serializer = new JavaScriptSerializer();

        public InternalAudioBridgeClient(string pipeName)
        {
            this.pipeName = string.IsNullOrWhiteSpace(pipeName)
                ? "SimVoiceCopilot.QA.InternalAudio.v1"
                : pipeName.Trim();
        }

        public BridgeResponse WaitUntilReady(TimeSpan timeout)
        {
            DateTime deadline = DateTime.UtcNow.Add(timeout);
            Exception lastException = null;

            while (DateTime.UtcNow < deadline)
            {
                try
                {
                    BridgeResponse response = Send(new BridgeRequest
                    {
                        Action = "ping",
                        TimeoutMs = 3000
                    });
                    if (response.Success)
                        return response;
                }
                catch (Exception ex)
                {
                    lastException = ex;
                }

                Thread.Sleep(400);
            }

            throw new TimeoutException(
                "Internal Audio QA bridge was not ready within " +
                timeout.TotalSeconds.ToString("0") + " seconds. Last error: " +
                (lastException == null ? "none" : lastException.Message));
        }

        public BridgeResponse GetStatus(int timeoutMs)
        {
            return Send(new BridgeRequest
            {
                Action = "status",
                TimeoutMs = timeoutMs
            });
        }

        public BridgeResponse WaitForSpeechIdle(int timeoutMs)
        {
            return Send(new BridgeRequest
            {
                Action = "wait-speech-idle",
                TimeoutMs = timeoutMs
            });
        }

        public BridgeResponse ResetState(int timeoutMs)
        {
            return Send(new BridgeRequest
            {
                Action = "reset-state",
                TimeoutMs = timeoutMs
            });
        }

        public BridgeResponse Inject(
            string text,
            string language,
            int timeoutMs,
            int postCommandWaitMs,
            int speechRate)
        {
            return Send(new BridgeRequest
            {
                Action = "synthesize-and-inject",
                Text = text,
                Language = language,
                TimeoutMs = timeoutMs,
                PostCommandWaitMs = postCommandWaitMs,
                SpeechRate = speechRate
            });
        }

        private BridgeResponse Send(BridgeRequest request)
        {
            if (request == null)
                throw new ArgumentNullException("request");

            request.ProtocolVersion = 1;
            request.CorrelationId = Guid.NewGuid().ToString("N");
            int timeoutMs = Math.Max(1000, Math.Min(120000, request.TimeoutMs <= 0 ? 30000 : request.TimeoutMs));

            using (var pipe = new NamedPipeClientStream(
                ".",
                pipeName,
                PipeDirection.InOut,
                PipeOptions.Asynchronous))
            {
                pipe.Connect(Math.Min(timeoutMs, 30000));
                var utf8 = new UTF8Encoding(false);
                using (var reader = new StreamReader(pipe, utf8, false, 65536, true))
                using (var writer = new StreamWriter(pipe, utf8, 65536, true) { AutoFlush = true })
                {
                    writer.WriteLine(serializer.Serialize(request));
                    string line = ReadLineWithTimeout(reader, timeoutMs + 10000);
                    if (string.IsNullOrWhiteSpace(line))
                        throw new InvalidDataException("Internal Audio QA bridge returned an empty response.");

                    BridgeResponse response = serializer.Deserialize<BridgeResponse>(line);
                    if (response == null)
                        throw new InvalidDataException("Internal Audio QA bridge returned invalid JSON.");

                    return response;
                }
            }
        }

        private static string ReadLineWithTimeout(StreamReader reader, int timeoutMs)
        {
            Task<string> readTask = reader.ReadLineAsync();
            if (!readTask.Wait(Math.Max(1000, timeoutMs)))
                throw new TimeoutException("Timed out waiting for the Internal Audio QA bridge response.");

            return readTask.Result;
        }
    }

    internal sealed class BridgeRequest
    {
        public int ProtocolVersion { get; set; }
        public string Action { get; set; }
        public string CorrelationId { get; set; }
        public string Text { get; set; }
        public string Language { get; set; }
        public int TimeoutMs { get; set; }
        public int SpeechRate { get; set; }
        public bool WaitForCalloutResponse { get; set; }
        public bool WaitForAiIdle { get; set; }
        public int PostCommandWaitMs { get; set; }
    }

    internal sealed class BridgeResponse
    {
        public int ProtocolVersion { get; set; }
        public bool Success { get; set; }
        public string Action { get; set; }
        public string CorrelationId { get; set; }
        public string Error { get; set; }
        public string AppVersion { get; set; }
        public string VoiceLanguage { get; set; }
        public string RecognizedText { get; set; }
        public string CommandFeedback { get; set; }
        public string CalloutResponse { get; set; }
        public string[] FeedbackMessages { get; set; }
        public string SynthesizerVoice { get; set; }
        public int AudioBytes { get; set; }
        public long ElapsedMs { get; set; }
        public bool AwaitingNumberInput { get; set; }
        public bool AiIdle { get; set; }
        public Dictionary<string, object> Diagnostics { get; set; }

        public ChecklistBridgeSnapshot GetChecklistSnapshot()
        {
            if (Diagnostics == null)
                return null;

            object value;
            if (!Diagnostics.TryGetValue("checklist", out value) || value == null)
                return null;

            var dictionary = value as Dictionary<string, object>;
            if (dictionary == null)
                return null;

            return ChecklistBridgeSnapshot.FromDictionary(dictionary);
        }

        public ChecklistSyncBridgeSnapshot GetChecklistSyncSnapshot()
        {
            if (Diagnostics == null)
                return null;

            object value;
            if (!Diagnostics.TryGetValue("checklistSync", out value) || value == null)
                return null;

            var dictionary = value as Dictionary<string, object>;
            if (dictionary == null)
                return null;

            return ChecklistSyncBridgeSnapshot.FromDictionary(dictionary);
        }
    }

    internal sealed class ChecklistBridgeSnapshot
    {
        public string State { get; private set; }
        public string ChecklistName { get; private set; }
        public string GroupName { get; private set; }
        public string SourceDisplayName { get; private set; }
        public string CurrentLabel { get; private set; }
        public string CurrentAction { get; private set; }
        public int CurrentActionableNumber { get; private set; }
        public int TotalActionableItems { get; private set; }
        public int CompletedItems { get; private set; }
        public int SkippedItems { get; private set; }
        public bool HasCurrentItem { get; private set; }

        public static ChecklistBridgeSnapshot FromDictionary(Dictionary<string, object> values)
        {
            return new ChecklistBridgeSnapshot
            {
                State = GetString(values, "state"),
                ChecklistName = GetString(values, "checklistName"),
                GroupName = GetString(values, "groupName"),
                SourceDisplayName = GetString(values, "sourceDisplayName"),
                CurrentLabel = GetString(values, "currentLabel"),
                CurrentAction = GetString(values, "currentAction"),
                CurrentActionableNumber = GetInt(values, "currentActionableNumber"),
                TotalActionableItems = GetInt(values, "totalActionableItems"),
                CompletedItems = GetInt(values, "completedItems"),
                SkippedItems = GetInt(values, "skippedItems"),
                HasCurrentItem = GetBool(values, "hasCurrentItem")
            };
        }

        public override string ToString()
        {
            return string.Format(
                "State={0}; List={1}; Current={2}/{3}; Completed={4}; Skipped={5}; Label={6}; Action={7}",
                State,
                ChecklistName,
                CurrentActionableNumber,
                TotalActionableItems,
                CompletedItems,
                SkippedItems,
                CurrentLabel,
                CurrentAction);
        }

        internal static string GetString(Dictionary<string, object> values, string key)
        {
            object value;
            return values != null && values.TryGetValue(key, out value) && value != null
                ? Convert.ToString(value)
                : string.Empty;
        }

        internal static int GetInt(Dictionary<string, object> values, string key)
        {
            object value;
            if (values == null || !values.TryGetValue(key, out value) || value == null)
                return 0;

            int result;
            return int.TryParse(Convert.ToString(value), out result) ? result : 0;
        }

        internal static bool GetBool(Dictionary<string, object> values, string key)
        {
            object value;
            if (values == null || !values.TryGetValue(key, out value) || value == null)
                return false;

            bool result;
            return bool.TryParse(Convert.ToString(value), out result) && result;
        }
    }

    internal sealed class ChecklistSyncBridgeSnapshot
    {
        public string State { get; private set; }
        public string StatusText { get; private set; }
        public string AircraftTitle { get; private set; }
        public string AdapterName { get; private set; }
        public bool IsReady { get; private set; }

        public static ChecklistSyncBridgeSnapshot FromDictionary(Dictionary<string, object> values)
        {
            return new ChecklistSyncBridgeSnapshot
            {
                State = ChecklistBridgeSnapshot.GetString(values, "state"),
                StatusText = ChecklistBridgeSnapshot.GetString(values, "statusText"),
                AircraftTitle = ChecklistBridgeSnapshot.GetString(values, "aircraftTitle"),
                AdapterName = ChecklistBridgeSnapshot.GetString(values, "adapterName"),
                IsReady = ChecklistBridgeSnapshot.GetBool(values, "isReady")
            };
        }

        public override string ToString()
        {
            return string.Format(
                "State={0}; Ready={1}; Aircraft={2}; Adapter={3}; Status={4}",
                State,
                IsReady,
                AircraftTitle,
                AdapterName,
                StatusText);
        }
    }
}
