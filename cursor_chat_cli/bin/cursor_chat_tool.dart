#!/usr/bin/env dart
// Request ID is the folder names in the workspaceStorage directory
// This is important to understand for correct display of chat data

import 'dart:io';
import 'package:args/args.dart';
import '../lib/chat_browser.dart';
import '../lib/chat_extractor.dart';
import '../lib/config.dart';
import '../lib/chat_model.dart';
import 'package:path/path.dart' as path;

/// Main function
void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help')
    ..addFlag('list',
        abbr: 'l', negatable: false, help: 'List all chat histories')
    ..addFlag('tui', abbr: 't', negatable: false, help: 'Open TUI browser')
    ..addFlag('show-empty',
        negatable: false, help: 'Include empty chats in listings')
    ..addFlag('verbose',
        abbr: 'v', negatable: false, help: 'Show verbose output for debugging')
    ..addOption('extract',
        abbr: 'e', help: 'Extract a specific chat (id or all)')
    ..addOption('format',
        abbr: 'f',
        defaultsTo: 'text',
        help: 'Output format (text, markdown, html, json)')
    ..addOption('output',
        abbr: 'o', defaultsTo: '~/repo/cursor_chats', help: 'Output directory')
    ..addOption('config',
        abbr: 'c',
        defaultsTo: '~/.cursor_chat_tool.conf',
        help: 'Path to configuration file')
    ..addOption('request-id',
        abbr: 'r',
        help:
            'Extract chat with specific request ID and save JSON to current directory')
    ..addOption('output-dir',
        abbr: 'd', help: 'Specific output directory for request-id command')
    ..addOption('output-path',
        abbr: 'p',
        help: 'Full output path including filename (without extension)');

  try {
    ArgResults results;

    try {
      results = parser.parse(arguments);
    } catch (e) {
      // If parsing fails, check if the first argument could be a request ID
      if (arguments.isNotEmpty && !arguments[0].startsWith('-')) {
        final requestId = arguments[0];

        // Load config and initialize the extractor
        final config = Config.load('~/.cursor_chat_tool.conf');
        final extractor = ChatExtractor(config);

        // Extract chat with request ID
        await extractor.extractWithRequestId(requestId, Directory.current.path);
        return;
      } else {
        // If not a request ID, rethrow the error
        rethrow;
      }
    }

    // Load config
    final configPath = results['config'] as String;
    final config = Config.load(configPath);

    // Verbose mode
    final bool verbose = results['verbose'] as bool;

    // Initialize chat browser and extractor
    final browser = ChatBrowser(config, verbose: verbose);
    final extractor = ChatExtractor(config, verbose: verbose);

    if (results['help'] as bool) {
      _printUsage(parser);
      return;
    }

    if (results['list'] as bool) {
      final allChats = await browser.loadAllChats();

      if (allChats.isEmpty) {
        print('No chat history found');
        return;
      }

      print('=== Cursor Chat History Browser ===');
      print('');
      print('ID | Title | Request ID | Count');
      print('----------------------------------------');

      for (var i = 0; i < allChats.length; i++) {
        final chat = allChats[i];
        final displayTitle =
            chat.title.isEmpty || chat.title == 'Chat ${chat.id}'
                ? chat.id
                : chat.title;

        // Use chat.id as fallback for requestId
        final requestIdDisplay = chat.requestId.isNotEmpty
            ? chat.requestId
            : chat.id.split('_').first;

        print(
            '${i + 1} | ${displayTitle} | $requestIdDisplay | ${chat.messages.length}');
      }

      print('');
      print('Found ${allChats.length} chat histories');
      return;
    }

    if (results['tui'] as bool) {
      await browser.showTUI();
      return;
    }

    // Handle request-id parameter
    if (results.wasParsed('request-id')) {
      final requestId = results['request-id'] as String;

      // Determine output directory (current directory or user-specified)
      final outputDir = results.wasParsed('output-dir')
          ? results['output-dir'] as String
          : Directory.current.path;

      // Extract chat with requestId
      final customFilename = results.wasParsed('output-path')
          ? results['output-path'] as String
          : null;

      await extractor.extractWithRequestId(requestId, outputDir,
          customFilename: customFilename);
      return;
    }

    if (results.wasParsed('extract')) {
      final chatId = results['extract'] as String;
      final format = results['format'] as String;
      final outputDir = results['output'] as String;
      final customPath = results.wasParsed('output-path')
          ? results['output-path'] as String
          : null;

      // Extract chat(s)
      await extractor.extract(chatId, outputDir, format,
          customPath: customPath);
      return;
    }

    // If no options specified but there's a positional argument, assume it's a request ID
    if (results.rest.isNotEmpty) {
      final requestId = results.rest[0];

      // Determine output directory
      String outputDir = Directory.current.path;
      if (results.wasParsed('output-dir')) {
        outputDir = results['output-dir'] as String;
      }

      final customFilename = results.wasParsed('output-path')
          ? results['output-path'] as String
          : null;

      await extractor.extractWithRequestId(requestId, outputDir,
          customFilename: customFilename);
      return;
    }

    if (arguments.isEmpty) {
      _printUsage(parser);
    }
  } catch (e) {
    print('Error parsing arguments: $e');
    print('Use --help to see available commands');
    exit(1);
  }
}

/// Print usage
void _printUsage(ArgParser parser) {
  print('''
Cursor Chat Tool - Værktøj til at håndtere chats fra Cursor

BRUG:
  cursor_chat_tool [options]

OPTIONER:
${parser.usage}

EKSEMPLER:
  cursor_chat_tool --list               # List alle chats
  cursor_chat_tool -l                   # Samme som ovenfor, brug kort form
  cursor_chat_tool --tui                # Åben text UI browser til at se chats
  cursor_chat_tool -t                   # Samme som ovenfor, kort form
  cursor_chat_tool --extract=1          # Udtræk chat med ID 1 (nummer fra liste)
  cursor_chat_tool --extract=all        # Udtræk alle chats
  cursor_chat_tool -e=all               # Samme som ovenfor, kort form
  cursor_chat_tool -e=all -f markdown   # Udtræk alle chats som markdown filer
  cursor_chat_tool -e=all -f json -o ./exports  # Udtræk alle chats som JSON til ./exports mappe
  cursor_chat_tool -r UUID              # Udtræk chat med specifik UUID (understøtter både korte og lange UUID'er)
  cursor_chat_tool -r 7bbe23e9-240b-4b76-b3e4-b84430f0daea  # Eksempel på UUID søgning
  cursor_chat_tool -v                   # Vis detaljeret output (verbose mode) for debugging
  cursor_chat_tool -r UUID -v           # Kombinér kommandoer, her UUID søgning med verbose output
  
TIP:
  UUID format er typisk et format som: 7bbe23e9-240b-4b76-b3e4-b84430f0daea
  Cursor Chat Tool kan nu finde chats baseret på disse UUID'er.
''');
}
