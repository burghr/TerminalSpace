---
description: Open a new Claude session in TerminalSpace with Remote Control on, so that you can use it from the phone now and from the Mac later.
argument-hint: <session name>
allowed-tools: Bash(open 'terminalspace://remote-session?name=*')
---

Open a new TerminalSpace session with the name "$ARGUMENTS".

1. If the name is empty, ask for a name and stop.
2. Make sure that the name has 1 to 40 characters. Only letters, digits, spaces, dots, dashes, and underscores are allowed. If the name has other characters, tell the user and stop.
3. Encode each space in the name as `%20`.
4. Run exactly one command, with the encoded name in single quotes:
   `open 'terminalspace://remote-session?name=<encoded name>'`
5. Reply with only this message, with the name in place of <name>:

   > Do not use this chat for the work. A new session with the name "<name>" opened in TerminalSpace. Open "<name>" from the session list in the Claude app. The session can take a few seconds to show.

Do not do other work in this session for this request.
