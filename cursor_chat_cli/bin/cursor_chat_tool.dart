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
    ..addFlag('list', abbr: 'l', negatable: false, help: 'List all chat histories')
    ..addFlag('tui', abbr: 't', negatable: false, help: 'Open TUI browser')
    ..addFlag('show-empty', negatable: false, help: 'Include empty chats in listings')
    ..addOption('extract', abbr: 'e', help: 'Extract a specific chat (id or all)')
    ..addOption('format', abbr: 'f', defaultsTo: 'text', help: 'Output format (text, markdown, html, json)')
    ..addOption('output', abbr: 'o', defaultsTo: './output', help: 'Output directory')
    ..addOption('config', abbr: 'c', defaultsTo: '~/.cursor_chat_tool.conf', help: 'Path to configuration file')
    ..addOption('request-id', abbr: 'r', help: 'Extract chat with specific request ID and save JSON to current directory')
    ..addOption('output-dir', abbr: 'd', help: 'Specific output directory for request-id command')
    ..addOption('output-path', abbr: 'p', help: 'Full output path including filename (without extension)');

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
    
    // Initialize chat browser and extractor
    final browser = ChatBrowser(config);
    final extractor = ChatExtractor(config);
    
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
        final displayTitle = chat.title.isEmpty || chat.title == 'Chat ${chat.id}'
            ? chat.id
            : chat.title;
        
        // Use chat.id as fallback for requestId
        final requestIdDisplay = chat.requestId.isNotEmpty ? chat.requestId : chat.id.split('_').first;
        
        print('${i + 1} | ${displayTitle} | $requestIdDisplay | ${chat.messages.length}');
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
      
      await extractor.extractWithRequestId(requestId, outputDir, customFilename: customFilename);
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
      await extractor.extract(chatId, outputDir, format, customPath: customPath);
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
      
      await extractor.extractWithRequestId(requestId, outputDir, customFilename: customFilename);
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

// Help function
void _printUsage(ArgParser parser) {
  print('Cursor Chat Browser & Extractor\n');
  print('Usage: cursor_chat_tool [options] [request_id]\n');
  print('If a request_id is provided as a direct argument, the tool will save that chat as JSON in the current directory.\n');
  print(parser.usage);
  print('\nExamples:');
  print('  cursor_chat_tool --list             # List all chats');
  print('  cursor_chat_tool --tui              # Open TUI browser');
  print('  cursor_chat_tool 1234abcd           # Extract chat with ID 1234abcd to current directory');
  print('  cursor_chat_tool --extract=all      # Extract all chats to ./output folder');
  print('  cursor_chat_tool -e=all             # Same as above, using shorthand notation');
  print('  cursor_chat_tool -e=all -f markdown # Extract all chats as markdown files');
  print('  cursor_chat_tool -e=all -f json -o ./exports  # Extract all chats as JSON to ./exports folder');
  print('  cursor_chat_tool -e=all -o ./chats/cursor/exports  # Extract to nested directory structure (created automatically)');
  print('  cursor_chat_tool -r 1234abcd -p ./specific/path/mychat  # Extract to specific path and filename');
}
