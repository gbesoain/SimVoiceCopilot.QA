# Stable UI identifiers confirmed in SimVoice Copilot 1.0.16.0

The UI Automation diagnostic exported from the installed MSIX confirmed these identifiers:

| Screen/action | AutomationId | UI Automation ControlType |
|---|---|---|
| Main window | `MainForm` | `Window` |
| Voice Commands | `btnConfigurar` | `Pane` |
| SimVar Call-outs | `btnEditCallouts` | `Pane` |
| Settings | `btnVoiceSettings` | `Pane` |
| Keyboard Settings | `btnKeyboardSettings` | `Pane` |
| Feedback tab | `btnPestanaFeedback` | `Button` |
| Commands tab | `btnPestanaComandos` | `Button` |
| Test Voice Recognition | `btnTestVoiceRecognition` | `Pane` |
| Window close control | `Close` | `Button` |

The configuration uses `AutomationId` as the primary selector and English/Spanish visible text only as a fallback.

Several visual controls are custom WinForms panels and are exposed as `ControlType.Pane`, without `InvokePattern`. The runner therefore uses a real native mouse click at the UI Automation clickable point or bounding rectangle center.

For future controls, keep the WinForms `Name` property stable across versions and languages. The visible caption may be translated, but the `Name`/`AutomationId` should not change.
