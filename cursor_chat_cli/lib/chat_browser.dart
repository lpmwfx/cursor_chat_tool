import 'dart:io';
import 'package:dart_console/dart_console.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:collection/collection.dart';
import 'package:sqlite3/sqlite3.dart';
import 'dart:convert';
import 'config.dart';
import 'chat_model.dart';

/// Class for browsing and displaying chat histories
class ChatBrowser {
  final Config config;
  final console = Console();
  List<Chat> _chats = [];
  bool _verbose = false;

  ChatBrowser(this.config, {bool verbose = false}) {
    _verbose = verbose;
  }

  void _debug(String message) {
    if (_verbose) {
      print("Debug: $message");
    }
  }

  /// Loads all chats from workspace storage folders
  Future<List<Chat>> _loadChats({bool includeEmpty = false}) async {
    _debug("Søger efter chats i: ${config.workspaceStoragePath}");
    _debug("includeEmpty er: $includeEmpty");
    final storageDir = Directory(config.workspaceStoragePath);

    if (!storageDir.existsSync()) {
      print(
          'Warning: Workspace storage folder not found: ${config.workspaceStoragePath}');
      return [];
    }

    final chats = <Chat>[];
    final skippedChats = <String>[];
    int fileScanCount = 0;
    int validFileCount = 0;
    int parseErrorCount = 0;

    try {
      // Go through all md5 hash folders (workspace storage)
      await for (final entity in storageDir.list()) {
        if (entity is Directory) {
          final dbFile = File(path.join(entity.path, 'state.vscdb'));
          fileScanCount++;

          // Check if there's a state.vscdb file in the folder
          if (dbFile.existsSync()) {
            validFileCount++;
            try {
              // Open SQLite database
              final db = sqlite3.open(dbFile.path);

              // Get all data from database for deeper search
              final allResult =
                  db.select("SELECT rowid, [key], value FROM ItemTable");

              // Process each row
              for (final row in allResult) {
                final rowId = row['rowid'] as int;
                final key = row['key'] as String;
                final value = row['value'] as String;

                // Generate chat ID
                final chatId =
                    '${entity.path.split(Platform.pathSeparator).last}_$rowId';

                try {
                  // Try to create a Chat from the value
                  final chat = Chat.fromSqliteValue(chatId, value);

                  // Validate chat and only add valid ones
                  if (chat != null) {
                    if (chat.messages.isNotEmpty || includeEmpty) {
                      chats.add(chat);
                    } else {
                      // Add to skipped chats list but don't print individual messages
                      skippedChats.add(chatId);
                    }
                  }
                } catch (e) {
                  // Tæl fejl, men vis kun beskeden i verbose mode
                  parseErrorCount++;
                  if (_verbose) {
                    print("Fejl ved parsing af chat data: $e");
                  }
                }
              }

              // Close the database
              db.dispose();
            } catch (e) {
              print('Could not read database ${dbFile.path}: $e');
            }
          }
        }
      }

      // Show info about number of skipped chats (only if there are any)
      if (skippedChats.isNotEmpty) {
        _debug('Skipped ${skippedChats.length} empty chats (no messages)');
      }

      if (parseErrorCount > 0) {
        _debug("Ignorerede $parseErrorCount fejl ved parsing af chat-data");
      }

      _debug(
          "Scannede $fileScanCount filer, fandt $validFileCount gyldige chat-filer");

      // Sort by date, newest first
      chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      _debug("Returnerer ${chats.length} chats");
      return chats;
    } catch (e) {
      print('Error loading chats: $e');
      return [];
    }
  }

  /// Public method to load all chats
  Future<List<Chat>> loadAllChats({bool includeEmpty = false}) async {
    return await _loadChats(includeEmpty: includeEmpty);
  }

  /// Søger efter en chat med et specifikt UUID direkte i databasen
  Future<Chat?> searchRawDatabaseForUuid(String uuid) async {
    _debug("Søger direkte i databasen efter UUID: $uuid");
    final storageDir = Directory(config.workspaceStoragePath);

    if (!storageDir.existsSync()) {
      print(
          'Warning: Workspace storage folder not found: ${config.workspaceStoragePath}');
      return null;
    }

    try {
      // Gennemgå alle mapper i workspace storage
      await for (final entity in storageDir.list()) {
        if (entity is Directory) {
          final dbFile = File(path.join(entity.path, 'state.vscdb'));

          // Kontroller om der er en state.vscdb fil i mappen
          if (dbFile.existsSync()) {
            try {
              // Åben SQLite database
              final db = sqlite3.open(dbFile.path);

              // Søg direkte efter UUID i værdier
              final result = db.select(
                  "SELECT rowid, [key], value FROM ItemTable WHERE value LIKE '%$uuid%'");

              // Behandl resultater
              for (final row in result) {
                final rowId = row['rowid'] as int;
                final key = row['key'] as String;
                final value = row['value'] as String;

                // Generer chat ID
                final chatId =
                    '${entity.path.split(Platform.pathSeparator).last}_$rowId';

                _debug(
                    "Fandt UUID $uuid i database ${dbFile.path}, rowid: $rowId, key: $key");

                // Prøv at oprette en Chat fra værdien
                try {
                  final chat = Chat.fromSqliteValue(chatId, value);
                  if (chat != null) {
                    // Sæt UUID som requestId hvis det ikke allerede er sat
                    if (chat.requestId.isEmpty) {
                      final updatedChat = Chat(
                        id: chat.id,
                        title: chat.title,
                        messages: chat.messages,
                        requestId: uuid,
                      );

                      db.dispose();
                      return updatedChat;
                    }

                    db.dispose();
                    return chat;
                  }
                } catch (e) {
                  _debug("Kunne ikke parse chat fra værdi: $e");
                }
              }

              // Luk databasen
              db.dispose();
            } catch (e) {
              print('Could not read database ${dbFile.path}: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error scanning databases: $e');
    }

    return null;
  }

  /// Finder en chat ud fra dens request ID
  Future<Chat?> findChatByRequestId(String requestId) async {
    final allChats = await loadAllChats(includeEmpty: true);

    _debug("Søger efter request ID: $requestId");
    _debug("Søger i ${allChats.length} chats");

    // Først: Print alle tilgængelige requestIds for debug
    if (_verbose) {
      _debug("Tilgængelige request IDs:");
      for (final chat in allChats) {
        _debug("  - Chat ID: ${chat.id}");
        _debug("    Request ID: ${chat.requestId}");
      }
    }

    // Find chat with matching requestId - exact match first
    for (final chat in allChats) {
      // Exact match first
      if (chat.id == requestId || chat.requestId == requestId) {
        _debug("Fandt nøjagtig match på request ID: $requestId");
        return chat;
      }
    }

    // Case insensitive match
    for (final chat in allChats) {
      if (chat.id.toLowerCase() == requestId.toLowerCase() ||
          chat.requestId.toLowerCase() == requestId.toLowerCase()) {
        _debug("Fandt case-insensitive match på request ID: $requestId");
        return chat;
      }
    }

    // Contains match
    for (final chat in allChats) {
      if (chat.id.toLowerCase().contains(requestId.toLowerCase()) ||
          chat.requestId.toLowerCase().contains(requestId.toLowerCase())) {
        _debug(
            "Fandt delvis match på request ID: $requestId i ${chat.id} eller ${chat.requestId}");
        return chat;
      }
    }

    // Prøv direkte databasesøgning som sidste udvej
    _debug(
        "Ingen match fundet i indlæste chats, prøver direkte databasesøgning");
    final directDbMatch = await searchRawDatabaseForUuid(requestId);
    if (directDbMatch != null) {
      _debug("Fandt match via direkte databasesøgning: ${directDbMatch.id}");
      return directDbMatch;
    }

    _debug("Ingen match fundet for request ID: $requestId");
    return null;
  }

  /// Henter en chat ved ID eller index
  Future<Chat?> getChat(String chatId) async {
    final allChats = await loadAllChats();

    // Parse chatId as integer index
    int? index = int.tryParse(chatId);
    if (index != null) {
      if (index < 1 || index > allChats.length) {
        print(
            'Invalid chat index: $index (should be between 1 and ${allChats.length})');
        return null;
      }

      return allChats[index - 1];
    }

    // Try to match by chat id
    final chat = allChats
        .firstWhereOrNull((c) => c.id == chatId || c.id.contains(chatId));
    if (chat != null) {
      return chat;
    }

    // Try to match by request id
    return await findChatByRequestId(chatId);
  }

  /// Shows a list of all chats in the console
  Future<void> listChats() async {
    _chats = await _loadChats();

    if (_chats.isEmpty) {
      print('No chat histories found in ${config.workspaceStoragePath}');
      return;
    }

    print('=== Cursor Chat History Browser ===');
    print('');
    print('ID | Title | Request ID | Count');
    print('----------------------------------------');

    for (var i = 0; i < _chats.length; i++) {
      final chat = _chats[i];

      // Show either title or ID based on format
      final displayTitle = chat.title.isEmpty || chat.title == 'Chat ${chat.id}'
          ? chat.id
          : chat.title;

      final requestIdDisplay =
          chat.requestId.isNotEmpty ? chat.requestId : chat.id.split('_').first;

      print(
          '${i + 1} | ${displayTitle} | $requestIdDisplay | ${chat.messages.length}');
    }

    print('');
    print('Found ${_chats.length} chat histories');
  }

  /// Shows Text User Interface (TUI) to browse and view chats
  Future<void> showTUI() async {
    _chats = await _loadChats();

    if (_chats.isEmpty) {
      print('No chat histories found in ${config.workspaceStoragePath}');
      return;
    }

    console.clearScreen();
    var selectedIndex = 0;
    var viewingChat = false;
    var scrollOffset = 0;
    var statusMessage = '';

    while (true) {
      console.clearScreen();
      console.resetCursorPosition();

      if (!viewingChat) {
        _drawChatList(selectedIndex);
      } else {
        _drawChatView(_chats[selectedIndex], scrollOffset, statusMessage);
        statusMessage = ''; // Reset status message after displaying
      }

      final key = console.readKey();

      if (key.controlChar == ControlCharacter.ctrlC) {
        console.clearScreen();
        console.resetCursorPosition();
        return;
      }

      if (!viewingChat) {
        // Navigation in chat list
        if (key.controlChar == ControlCharacter.arrowDown) {
          selectedIndex = (selectedIndex + 1) % _chats.length;
        } else if (key.controlChar == ControlCharacter.arrowUp) {
          selectedIndex = (selectedIndex - 1 + _chats.length) % _chats.length;
        } else if (key.controlChar == ControlCharacter.enter) {
          viewingChat = true;
          scrollOffset = 0;
        } else if (key.char == 'q' ||
            key.controlChar == ControlCharacter.ctrlQ) {
          console.clearScreen();
          console.resetCursorPosition();
          return;
        }
      } else {
        // Navigation in chat view
        if (key.controlChar == ControlCharacter.arrowDown) {
          scrollOffset += 1;
        } else if (key.controlChar == ControlCharacter.arrowUp) {
          scrollOffset = (scrollOffset - 1).clamp(0, double.infinity).toInt();
        } else if (key.char == 'q' ||
            key.controlChar == ControlCharacter.escape) {
          viewingChat = false;
        } else if (key.char == 's') {
          // Save chat as JSON
          statusMessage = _saveCurrentChatAsJson(_chats[selectedIndex]);
        }
      }
    }
  }

  /// Save current chat as JSON in the current directory
  String _saveCurrentChatAsJson(Chat chat) {
    try {
      final title = _sanitizeFilename(chat.title);
      final reqId =
          chat.requestId.isNotEmpty ? chat.requestId : chat.id.split('_').first;
      final filename = '$title-$reqId.json';

      // Convert chat to JSON
      final jsonData = {
        'id': chat.id,
        'title': chat.title,
        'requestId': reqId,
        'messages': chat.messages
            .map((msg) => {
                  'role': msg.role,
                  'content': msg.content,
                  'timestamp': msg.timestamp.millisecondsSinceEpoch
                })
            .toList()
      };

      final jsonString = JsonEncoder.withIndent('  ').convert(jsonData);

      // Write to current directory
      final file = File(path.join(Directory.current.path, filename));
      file.writeAsStringSync(jsonString);

      return 'Chat saved to ${file.path}';
    } catch (e) {
      return 'Error saving chat: $e';
    }
  }

  /// Sanitize filename for safe file operations
  String _sanitizeFilename(String input) {
    if (input.isEmpty) return 'chat';

    // Limit length
    var sanitized = input.length > 30 ? input.substring(0, 30) : input;

    // Replace invalid filename characters
    sanitized = sanitized.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), '_');

    return sanitized;
  }

  /// Draws the chat list
  void _drawChatList(int selectedIndex) {
    final width = console.windowWidth;

    console.writeLine(
      '=== Cursor Chat History Browser ==='.padRight(width),
      TextAlignment.center,
    );
    console.writeLine('');
    console.writeLine(
      'Press ↑/↓ to navigate, Enter to view chat, q or Ctrl+Q to exit',
    );
    console.writeLine('');

    final titleWidth = 40;
    final requestIdWidth = 40;

    console.writeLine(
      'ID | ${_padTruncate('Title', titleWidth)} | ${_padTruncate('Request ID', requestIdWidth)} | Count',
    );
    console.writeLine(''.padRight(width, '-'));

    for (var i = 0; i < _chats.length; i++) {
      final chat = _chats[i];

      // Show either title or ID based on format
      final displayTitle = chat.title.isEmpty || chat.title == 'Chat ${chat.id}'
          ? chat.id
          : chat.title;

      // Use chat.id as fallback for requestId
      final requestIdDisplay =
          chat.requestId.isNotEmpty ? chat.requestId : chat.id.split('_').first;

      final line = '${_padTruncate((i + 1).toString(), 3)} | '
          '${_padTruncate(displayTitle, titleWidth)} | '
          '${_padTruncate(requestIdDisplay, requestIdWidth)} | '
          '${chat.messages.length}';

      if (i == selectedIndex) {
        console.setForegroundColor(ConsoleColor.white);
        console.setBackgroundColor(ConsoleColor.blue);
        console.writeLine(line.padRight(width));
        console.resetColorAttributes();
      } else {
        console.writeLine(line);
      }
    }

    console.writeLine('');
    console.writeLine('Found ${_chats.length} chat histories');
  }

  /// Draws the chat view
  void _drawChatView(Chat chat, int scrollOffset, [String statusMessage = '']) {
    final width = console.windowWidth;
    final height = console.windowHeight -
        7; // Reduced height to accommodate status and help lines

    console.writeLine(
      '=== ${chat.title} ==='.padRight(width),
      TextAlignment.center,
    );
    console.writeLine('');
    console.writeLine(
        'Press ↑/↓ to scroll, q or ESC to go back, s to save as JSON');
    console.writeLine(''.padRight(width, '-'));

    final visibleMessages = chat.messages.skip(scrollOffset).take(height);

    for (final message in visibleMessages) {
      final sender = message.isUser ? 'User' : 'AI';
      console.writeLine(
        '[$sender - ${DateFormat('HH:mm:ss').format(message.timestamp)}]',
      );

      // Split content into lines that fit the screen width
      final contentLines = _wrapText(message.content, width);
      for (final line in contentLines) {
        console.writeLine(line);
      }

      console.writeLine('');
    }

    console.writeLine(''.padRight(width, '-'));

    // Show message position
    console.writeLine(
      'Message ${scrollOffset + 1}-${(scrollOffset + visibleMessages.length).clamp(1, chat.messages.length)} of ${chat.messages.length}',
    );

    // Show help text
    console.writeLine('[q] Back  [ESC] Back  [s] Save JSON  [Ctrl+Q] Exit',
        TextAlignment.center);

    // Show status message if present
    if (statusMessage.isNotEmpty) {
      console.setForegroundColor(ConsoleColor.green);
      console.writeLine(statusMessage, TextAlignment.center);
      console.resetColorAttributes();
    }
  }

  /// Helper function to format text
  String _padTruncate(String text, int width) {
    if (text.length > width) {
      return text.substring(0, width - 3) + '...';
    }
    return text.padRight(width);
  }

  /// Helper function to wrap text to a specific width
  List<String> _wrapText(String text, int width) {
    final result = <String>[];
    final words = text.split(' ');

    String currentLine = '';
    for (final word in words) {
      if (currentLine.isEmpty) {
        currentLine = word;
      } else if (currentLine.length + word.length + 1 <= width) {
        currentLine += ' $word';
      } else {
        result.add(currentLine);
        currentLine = word;
      }
    }

    if (currentLine.isNotEmpty) {
      result.add(currentLine);
    }

    return result;
  }
}
