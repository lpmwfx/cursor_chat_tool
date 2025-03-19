import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'config.dart';
import 'chat_model.dart';
import 'chat_browser.dart';

/// Formaterer tidsstempel til læsbart dansk-venligt format
String formatTimestamp(int millisecondsSinceEpoch) {
  // Konverter millisekunder til DateTime
  final dateTime = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
  
  // Formatter til læsbart dansk-venligt format
  final year = dateTime.year;
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');
  
  return '$day-$month-$year $hour:$minute:$second';
}

/// Sikrer at en mappe eksisterer, opretter den rekursivt hvis nødvendigt
void ensureDirectoryExists(String dirPath) {
  final directory = Directory(dirPath);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
    print('Oprettede mappe: $dirPath');
  }
}

/// Hjælpefunktion til at escape HTML tegn
String escapeHtml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#039;');
}

/// Hjælpefunktion til at sanitize filnavne
String sanitizeFilename(String input) {
  if (input.isEmpty) return 'untitled';
  
  // Limit length
  var sanitized = input.length > 50 ? input.substring(0, 50) : input;
  
  // Replace invalid filename characters
  sanitized = sanitized.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  sanitized = sanitized.replaceAll(RegExp(r'\s+'), '_');
  
  return sanitized;
}

/// Klasse til at udtrække chats fra historik
class ChatExtractor {
  final Config config;
  final ChatBrowser browser;

  ChatExtractor(this.config) : browser = ChatBrowser(config);

  /// Udtræk en specifik chat eller alle chats
  Future<void> extract(String chatId, String outputPath, String format, {String? customPath}) async {
    List<Chat> chats = [];

    if (chatId.toLowerCase() == 'alle' || chatId.toLowerCase() == 'all') {
      // Hent alle chats ved at kalde den offentlige metode
      chats = await browser.loadAllChats();
    } else {
      // Hent specifik chat med den offentlige metode
      final chat = await browser.getChat(chatId);
      if (chat != null) {
        chats = [chat];
      }
    }

    if (chats.isEmpty) {
      print('Ingen chats fundet til udtrækning.');
      return;
    }

    // Sikr at output-mappen eksisterer
    ensureDirectoryExists(outputPath);

    int skippedCount = 0;
    int successCount = 0;

    for (final chat in chats) {
      // Skip chats without messages
      if (chat.messages.isEmpty) {
        skippedCount++;
        continue;
      }

      String outputFilePath;
      if (customPath != null) {
        // Hvis der er angivet en specifik sti, brug den
        final dirName = path.dirname(customPath);
        ensureDirectoryExists(dirName);
        
        final extension = getExtensionForFormat(format);
        outputFilePath = '$customPath$extension';
      } else {
        // Ellers brug standard sti-generering
        final filename = '${sanitizeFilename(chat.title)}_${chat.id}';
        final extension = getExtensionForFormat(format);
        outputFilePath = path.join(outputPath, '$filename$extension');
      }

      final content = formatChat(chat, format);
      File(outputFilePath).writeAsStringSync(content);
      
      print('Chat udtrukket til: ${path.basename(outputFilePath)}');
      successCount++;
    }

    print('Udtrækning fuldført! $successCount chat(s) udtrukket til $outputPath');
    if (skippedCount > 0) {
      print('Sprang $skippedCount tomme chats over (ingen beskeder)');
    }
  }

  /// Udtræk chat med specifik request ID og gem som JSON
  Future<void> extractWithRequestId(String requestId, String outputDir, {String? customFilename}) async {
    final chat = await browser.findChatByRequestId(requestId);
    
    if (chat == null) {
      print('Ingen chat fundet med request ID: $requestId');
      return;
    }
    
    String outputFile;
    if (customFilename != null) {
      // Hvis der er angivet et specifikt filnavn, brug det
      final dirName = path.dirname(customFilename);
      ensureDirectoryExists(dirName);
      outputFile = '$customFilename.json';
    } else {
      // Ellers brug standard filnavn
      final sanitizedTitle = sanitizeFilename(chat.title);
      outputFile = path.join(outputDir, '$sanitizedTitle-${chat.id}.json');
    }
    
    // Sikr at output-mappen eksisterer
    ensureDirectoryExists(path.dirname(outputFile));
    
    // Eksporter chat som JSON
    final jsonContent = JsonEncoder.withIndent('  ').convert({
      'id': chat.id,
      'title': chat.title,
      'requestId': chat.requestId,
      'messages': chat.messages.map((msg) => {
        'role': msg.role,
        'content': msg.content,
        'timestamp': msg.timestamp.millisecondsSinceEpoch
      }).toList()
    });
    
    File(outputFile).writeAsStringSync(jsonContent);
    print('Chat med request ID "${chat.id}" gemt som ${path.basename(outputFile)}');
  }

  /// Formatterer chat til det ønskede output format
  String formatChat(Chat chat, String format) {
    switch (format.toLowerCase()) {
      case 'json':
        return formatChatAsJson(chat);
      case 'markdown':
      case 'md':
        return formatChatAsMarkdown(chat);
      case 'html':
        return formatChatAsHtml(chat);
      case 'text':
      default:
        return formatChatAsText(chat);
    }
  }

  /// Formatterer chat som JSON
  String formatChatAsJson(Chat chat) {
    final jsonMap = {
      'id': chat.id,
      'title': chat.title,
      'requestId': chat.requestId,
      'messages': chat.messages.map((msg) => {
        'role': msg.role,
        'content': msg.content,
        'timestamp': msg.timestamp.millisecondsSinceEpoch
      }).toList()
    };
    return JsonEncoder.withIndent('  ').convert(jsonMap);
  }

  /// Formatterer chat som simpel tekst
  String formatChatAsText(Chat chat) {
    final buffer = StringBuffer();

    buffer.writeln('=== ${chat.title} ===');
    buffer.writeln('Chat ID: ${chat.id}');
    buffer.writeln('Request ID: ${chat.requestId}');
    buffer.writeln('Antal beskeder: ${chat.messages.length}');
    buffer.writeln('');

    for (final message in chat.messages) {
      // Brug formatTimestamp funktionen til korrekt datovisning
      final formattedTime = formatTimestamp(message.timestamp.millisecondsSinceEpoch);
      buffer.writeln('[${message.role} - $formattedTime]');
      buffer.writeln(message.content);
      buffer.writeln('');
    }

    return buffer.toString();
  }

  /// Formatterer chat som Markdown
  String formatChatAsMarkdown(Chat chat) {
    final buffer = StringBuffer();

    buffer.writeln('# ${chat.title}');
    buffer.writeln('');
    buffer.writeln('**Chat ID:** ${chat.id}');
    buffer.writeln('**Request ID:** ${chat.requestId}');
    buffer.writeln('**Antal beskeder:** ${chat.messages.length}');
    buffer.writeln('');

    for (final message in chat.messages) {
      // Brug formatTimestamp funktionen til korrekt datovisning
      final formattedTime = formatTimestamp(message.timestamp.millisecondsSinceEpoch);
      buffer.writeln('## ${message.role} ($formattedTime)');
      buffer.writeln('');
      buffer.writeln(message.content);
      buffer.writeln('');
    }

    return buffer.toString();
  }

  /// Formatterer chat som HTML
  String formatChatAsHtml(Chat chat) {
    final buffer = StringBuffer();

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html>');
    buffer.writeln('<head>');
    buffer.writeln('  <meta charset="UTF-8">');
    buffer.writeln('  <title>${escapeHtml(chat.title)}</title>');
    buffer.writeln('  <style>');
    buffer.writeln(
        '    body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }');
    buffer.writeln(
        '    .header { border-bottom: 1px solid #ddd; padding-bottom: 10px; margin-bottom: 20px; }');
    buffer.writeln(
        '    .message { margin-bottom: 20px; padding: 10px; border-radius: 5px; }');
    buffer.writeln('    .user { background-color: #f0f0f0; }');
    buffer.writeln('    .assistant { background-color: #e6f7ff; }');
    buffer.writeln(
        '    .timestamp { color: #666; font-size: 0.8em; margin-bottom: 5px; }');
    buffer.writeln('    .content { white-space: pre-wrap; }');
    buffer.writeln('  </style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');

    buffer.writeln('  <div class="header">');
    buffer.writeln('    <h1>${escapeHtml(chat.title)}</h1>');
    buffer.writeln('    <p>Chat ID: ${chat.id}</p>');
    buffer.writeln('    <p>Request ID: ${chat.requestId}</p>');
    buffer.writeln('    <p>Antal beskeder: ${chat.messages.length}</p>');
    buffer.writeln('  </div>');

    for (final message in chat.messages) {
      // Brug formatTimestamp funktionen til korrekt datovisning
      final formattedTime = formatTimestamp(message.timestamp.millisecondsSinceEpoch);
      final cssClass = message.role == 'user' ? 'user' : 'assistant';

      buffer.writeln('  <div class="message $cssClass">');
      buffer.writeln('    <div class="timestamp">Tidspunkt: $formattedTime</div>');
      buffer.writeln('    <div class="role">${escapeHtml(message.role)}</div>');
      buffer.writeln('    <div class="content">${escapeHtml(message.content)}</div>');
      buffer.writeln('  </div>');
    }

    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  /// Hjælpefunktion til at få filendelse baseret på format
  String getExtensionForFormat(String format) {
    switch (format.toLowerCase()) {
      case 'json':
        return '.json';
      case 'markdown':
      case 'md':
        return '.md';
      case 'html':
        return '.html';
      case 'text':
      default:
        return '.txt';
    }
  }
}
