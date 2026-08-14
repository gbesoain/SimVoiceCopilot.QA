# Guided Voice Checklist Focus - 1.0.19.0 A1

This guided QA validates the first implementation of native MSFS 2024 cockpit visual helpers in SimVoice Copilot.

Run:

```powershell
.\Scripts\Run-QA-Guided-Checklist-Focus.ps1
```

Expected diagnostic markers in a support package:

- `GUIDED_CHECKLIST_FOCUS_CAPABILITY`
- `EFB_NATIVE_VISUAL_HELPER_EXTRACTED`
- `EFB_NATIVE_VISUAL_HELPER_SHAPE`
- `GUIDED_CHECKLIST_AUTO_FOCUS`
- `GUIDED_CHECKLIST_MANUAL_FOCUS`
- `GUIDED_CHECKLIST_FOCUS_APPLIED`
- `GUIDED_CHECKLIST_FOCUS_CLEARED`

The first aircraft should be one whose native MSFS 2024 checklist already provides a working eye/visual-helper function. If the native eye works but SVC does not, the support package is authoritative for the next iteration.
