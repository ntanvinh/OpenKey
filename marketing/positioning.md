# VOpenKey AI positioning

## Product and audience

**Product:** VOpenKey AI is a Vietnamese input method and writing assistant for macOS and Windows. The repository README gives macOS 13 Ventura or later as the requirement for the Mac app; the Windows app (x86 and x64) is described in `Sources/OpenKey/win32/README.md`. The app configuration lists macOS and Windows as its platforms.

**Who it is for:** People who write Vietnamese on a Mac or a Windows PC and want control over how Vietnamese text is entered, corrected, and reused. It also serves people who want to call an AI writing assistant from their current app, with a hosted service, local model, or supported signed-in command-line agent.

## Promise

**en-US:** For people who write Vietnamese on a Mac or Windows PC, VOpenKey AI is the Vietnamese input method and writing companion that helps them type, recover, and refine text across apps, with configurable input rules and an optional AI assistant.

**vi:** Dành cho người thường viết tiếng Việt trên Mac hoặc máy Windows, VOpenKey AI là bộ gõ kiêm trợ lý viết giúp bạn nhập, khôi phục và chỉnh sửa nội dung xuyên suốt các ứng dụng, với quy tắc gõ tùy chỉnh và trợ lý AI tùy chọn.

## Strongest differentiators and proof

1. **Vietnamese typing with a way back.** The README documents automatic restoration of words detected as non-Vietnamese and a configurable shortcut to restore the current word when detection misses it. It also describes Backspace typing as its approach to the underline issue in macOS’s built-in input method.
2. **An AI writing assistant where you work.** A configurable shortcut opens the assistant from any app; selected text can be brought into the prompt, and generated text can be copied or inserted back. The README documents hosted providers, local models, compatible OpenAI-style servers, and supported signed-in CLI agents. For local models it says the text stays on the Mac; for hosted services the selected destination is shown.
3. **Reusable writing tools in the input workflow.** The app combines searchable snippets (including 21 documented sample AI prompts), text macros, context-aware suggestions, and encoding conversion. The README documents snippet placeholders for clipboard text, date, and time.

## Tone of voice

Clear, capable, and calm. Lead with practical writing outcomes; describe keyboard behavior plainly. In Vietnamese, address the reader as “bạn” and use natural Vietnamese rather than translated English phrasing. Avoid implying that every AI connection is local or private: explain where text goes when describing a provider.

## Competitor and alternative approaches

These are categories of alternatives, not researched competitor evaluations. Product-specific strengths, weaknesses, pricing, and compatibility are **unverified**.

1. **macOS built-in Vietnamese input:** VOpenKey AI offers documented word recovery, configurable typing rules, and a Backspace-based approach to the underline issue; comparative behavior beyond the README is unverified.
2. **Other Vietnamese input methods:** VOpenKey AI combines Vietnamese typing with snippets and an AI writing assistant; what other input methods include is unverified.
3. **Manual keyboard layouts or transliteration:** VOpenKey AI supports Telex, VNI, and Simple Telex plus spelling and grammar controls; comparative setup and workflow claims are unverified.
4. **Separate text-expansion utilities:** VOpenKey AI puts macros and searchable snippets alongside Vietnamese input; other utilities’ capabilities and limits are unverified.
5. **Separate AI writing tools:** VOpenKey AI can open its assistant from a shortcut and insert output into the current work; alternatives’ app integration and provider choices are unverified.

## Claims to keep bounded

- The app configuration lists **macOS** and **Windows**. Windows is released as `VOpenKey-<version>-Windows.zip` (x86 and x64) on the project's GitHub Releases, with a fixed-name copy `VOpenKey-Windows.zip` for the newest version. Describe a Windows behavior as verified only when `docs/windows-port-checklist.md` records it as run on Windows.
- The README identifies the project as a fork of OpenKey by Mai Vũ Tuyên, developed by LSSoft, and licensed under GPL-3.0.
- AI availability, privacy, cost, and speed depend on the selected provider or local model. Do not describe all AI use as offline, free, or private.
- Competitor-specific comparisons and market position are unverified.
