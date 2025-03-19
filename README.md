# Cursor Chat Tools


This repository contains a collection of tools for working with the Cursor AI IDE, including command-line utilities and a text-based user interface for browsing and extracting chat histories.

## Overview

Cursor Chat Tools provide a simple way to access, browse, and export your Cursor AI conversation history. The tools parse Cursor's SQLite databases and workspace storage to retrieve chat data, which can then be viewed in a text interface or exported in various formats.

## Features

- **List all chat histories** with titles, request IDs and message counts
- **Browse chats** through an interactive text user interface
- **Search and view** specific chats by ID
- **Export chats** in multiple formats (JSON, Markdown, HTML, text)
- **Direct JSON export** using request ID as a command-line parameter
- **Filter out empty chats** automatically to keep listings clean

## Installation

### Prerequisites

- Dart SDK (version 2.12 or higher)
- Cursor AI IDE installed (the tool reads from its data directory)

### Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/lpmwfx/cursorchattool.git
   cd cursorchattool/cursor_chat_cli
   ```

2. Compile the executable:
   ```bash
   dart compile exe bin/cursor_chat_tool.dart -o cursor_chat_tool
   ```

3. Install to ~/.cursor directory (to make it available in your path):
   ```bash
   cp cursor_chat_tool ~/.cursor/
   chmod +x ~/.cursor/cursor_chat_tool
   ```

## Usage

### List All Chats

View a list of all available chat histories:
```bash
cursor_chat_tool --list
```

### Interactive TUI Browser

Open the Text User Interface to browse and interact with chats:
```bash
cursor_chat_tool --tui
```

In the TUI:
- Use ↑/↓ arrows to navigate the list
- Press Enter to view a selected chat
- Press q or ESC to go back from chat view
- Press s in chat view to save as JSON
- Press Ctrl+Q to exit

### Extract a Chat by ID

Extract a specific chat directly using its request ID:
```bash
cursor_chat_tool 1e4ddc91eebcec20571cd738f31756a9
```
This will save the chat as a JSON file in the current directory.

### Extract Multiple Chats

Extract all chats to a specific directory:
```bash
cursor_chat_tool --extract=all --format=json --output=./exports
```

Du kan også bruge kortere flag-syntaks:
```bash
cursor_chat_tool -e=all -f json -o ./exports
```

## Command-line Parameters

```
Cursor Chat Browser & Extractor

Usage: cursor_chat_tool [options] [request_id]

If a request_id is provided as a direct argument, the tool will save that chat as JSON in the current directory.

-h, --help          Show help
-l, --list          List all chat histories
-t, --tui           Open TUI browser
-e, --extract       Extract a specific chat (id or all)
-f, --format        Output format (text, markdown, html, json)
                    (defaults to "text")
-o, --output        Output directory
                    (defaults to "./output")
-c, --config        Path to configuration file
                    (defaults to "~/.cursor_chat_tool.conf")
-r, --request-id    Extract chat with specific request ID and save JSON to current directory
-d, --output-dir    Specific output directory for request-id command

Examples:
  cursor_chat_tool --list             # List all chats
  cursor_chat_tool --tui              # Open the TUI browser
  cursor_chat_tool 1234abcd           # Extract chat with ID 1234abcd to current directory
  cursor_chat_tool --extract=all      # Extract all chats to ./output folder
  cursor_chat_tool -e=all             # Same as above, using shorthand notation
  cursor_chat_tool -e=all -f markdown # Extract all chats as markdown files
  cursor_chat_tool -e=all -f json -o ./exports  # Extract all chats as JSON to ./exports folder
```

## VSCode Integration

You can use this tool directly from VSCode as a task. A task configuration example is included.

To use this tool as a task in VSCode:

1. Copy the contents of `vscode_task_example.json` to `.vscode/tasks.json` in your project
2. Run the task via Command Palette (Ctrl+Shift+P) > "Tasks: Run Task" > "Extract Cursor Chat with Request ID"
3. Enter the request ID
4. The tool will generate a JSON file in your project's root directory

Example task configuration:
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Extract Cursor Chat with Request ID",
      "type": "shell",
      "command": "cursor_chat_tool ${input:requestId}",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "new"
      }
    }
  ],
  "inputs": [
    {
      "id": "requestId",
      "description": "Enter the request ID for the chat you want to extract:",
      "default": "",
      "type": "promptString"
    }
  ]
}
```

## Project Structure

- `bin/cursor_chat_tool.dart`: Main entry point and command-line interface
- `lib/chat_browser.dart`: TUI implementation and chat browser functionality
- `lib/chat_model.dart`: Data models for working with chat data
- `lib/chat_extractor.dart`: Code for extracting chats to different formats
- `lib/config.dart`: Configuration handling

## Technical Details

The tool works by:
1. Locating Cursor's workspace storage directory based on your OS
2. Reading SQLite databases in these directories to extract chat data
3. Parsing various JSON formats that Cursor uses to store conversations
4. Filtering out empty chats (those without any messages)

## Development

To contribute to the project:

1. Fork the repository
2. Make your changes
3. Run tests with: `dart test`
4. Create a pull request

## Credits

This project was developed by Lars with assistance from Claude 3.7 AI.

## License

MIT License - see LICENSE file for details.
