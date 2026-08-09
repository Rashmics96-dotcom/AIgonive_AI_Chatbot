import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../services/gemini_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() =>
      _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ============================================================
  // CONTROLLERS
  // ============================================================

  final TextEditingController controller =
  TextEditingController();

  final ImagePicker picker =
  ImagePicker();

  // ============================================================
  // ACTIVE ATTACHMENTS
  // ============================================================

  Uint8List? selectedImage;

  PlatformFile? selectedPdf;

  String? activePdfText;
  String? activePdfName;

  String? activeImageName;
  String activeImageMimeType =
      "image/jpeg";

  String? activeAttachmentId;

  // ============================================================
  // SETTINGS
  // ============================================================

  bool isDarkMode = false;

  bool autoSaveHistory = true;

  bool keepAttachments = true;

  bool isThinking = false;

  // ============================================================
  // CHAT
  // ============================================================

  String currentChatId = "";

  String currentChatTitle = "New Chat";

  List<Map<String, dynamic>> messages =
  [];

  List<Map<String, dynamic>> conversations =
  [];

  List<String> pinnedChatIds = [];

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    initializeChat();
  }

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initializeChat() async {
    final prefs =
    await SharedPreferences.getInstance();

    final savedConversations =
    prefs.getStringList(
      "conversations",
    );

    final savedPinned =
    prefs.getStringList(
      "pinned_chat_ids",
    );

    isDarkMode =
        prefs.getBool("dark_mode") ?? false;

    autoSaveHistory =
        prefs.getBool("auto_save_history") ??
            true;

    keepAttachments =
        prefs.getBool("keep_attachments") ??
            true;

    if (savedConversations != null &&
        savedConversations.isNotEmpty) {
      try {
        conversations =
            savedConversations
                .map(
                  (item) =>
              Map<String, dynamic>.from(
                jsonDecode(item),
              ),
            )
                .toList();
      } catch (e) {
        debugPrint(
          "Conversation loading error: $e",
        );

        conversations = [];
      }
    }

    if (savedPinned != null) {
      pinnedChatIds = savedPinned;
    }

    if (conversations.isNotEmpty) {
      final firstChat =
          conversations.first;

      currentChatId =
          firstChat["id"].toString();

      currentChatTitle =
          firstChat["title"]?.toString() ??
              "New Chat";

      messages =
      List<Map<String, dynamic>>.from(
        (firstChat["messages"] as List)
            .map(
              (message) =>
          Map<String, dynamic>.from(
            message,
          ),
        ),
      );

      restoreAttachmentFromMessages();
    } else {
      createNewChatInternal();
    }

    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // NEW CHAT INTERNAL
  // ============================================================

  void createNewChatInternal() {
    currentChatId =
        DateTime.now()
            .millisecondsSinceEpoch
            .toString();

    currentChatTitle = "New Chat";

    messages = [
      {
        "text":
        "👋 Hello! I'm your AI Study Assistant.\n\nAsk me anything!",
        "isUser": false,
      }
    ];

    clearActiveAttachment();
  }

  // ============================================================
  // NEW CHAT
  // ============================================================

  Future<void> newChat() async {
    await updateCurrentChat();

    if (!mounted) return;

    setState(() {
      createNewChatInternal();

      controller.clear();
    });
  }

  // ============================================================
  // SAVE CONVERSATIONS
  // ============================================================

  Future<void> saveConversations() async {
    final prefs =
    await SharedPreferences.getInstance();

    final data = conversations
        .map(
          (chat) => jsonEncode(chat),
    )
        .toList();

    await prefs.setStringList(
      "conversations",
      data,
    );

    await prefs.setStringList(
      "pinned_chat_ids",
      pinnedChatIds,
    );
  }

  // ============================================================
  // UPDATE CURRENT CHAT
  // ============================================================

  Future<void> updateCurrentChat() async {
    if (!autoSaveHistory) {
      return;
    }

    if (currentChatId.isEmpty) {
      return;
    }

    final index =
    conversations.indexWhere(
          (chat) =>
      chat["id"] == currentChatId,
    );

    final chatData = {
      "id": currentChatId,
      "title": currentChatTitle,
      "messages": messages,
    };

    if (index == -1) {
      conversations.insert(
        0,
        chatData,
      );
    } else {
      conversations[index] =
          chatData;
    }

    await saveConversations();
  }

  // ============================================================
  // IMAGE PICKER
  // ============================================================

  Future<void> pickImage() async {
    final XFile? image =
    await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1400,
      maxHeight: 1400,
      imageQuality: 75,
    );

    if (image == null) {
      return;
    }

    final bytes =
    await image.readAsBytes();

    final lowerName =
    image.name.toLowerCase();

    String mimeType =
        "image/jpeg";

    if (lowerName.endsWith(".png")) {
      mimeType = "image/png";
    } else if (lowerName.endsWith(".webp")) {
      mimeType = "image/webp";
    } else if (lowerName.endsWith(".gif")) {
      mimeType = "image/gif";
    }

    if (!mounted) return;

    setState(() {
      selectedImage = bytes;

      selectedPdf = null;

      activePdfText = null;
      activePdfName = null;

      activeImageName =
          image.name;

      activeImageMimeType =
          mimeType;

      activeAttachmentId =
          DateTime.now()
              .millisecondsSinceEpoch
              .toString();
    });
  }

  // ============================================================
  // PDF PICKER
  // ============================================================

  Future<void> pickPdf() async {
    final FilePickerResult? result =
    await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        "pdf",
      ],
      withData: true,
    );

    if (result == null ||
        result.files.isEmpty) {
      return;
    }

    final file =
        result.files.first;

    if (file.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              "Could not read this PDF file.",
            ),
          ),
        );
      }

      return;
    }

    if (!mounted) return;

    setState(() {
      selectedPdf = file;

      selectedImage = null;

      activeImageName = null;

      activePdfText = null;

      activePdfName = file.name;

      activeAttachmentId =
          DateTime.now()
              .millisecondsSinceEpoch
              .toString();
    });
  }

  // ============================================================
  // PDF TEXT EXTRACTION
  // ============================================================

  Future<String> extractPdfText() async {
    if (selectedPdf == null ||
        selectedPdf!.bytes == null) {
      return "";
    }

    try {
      final document =
      PdfDocument(
        inputBytes:
        selectedPdf!.bytes!,
      );

      final extractor =
      PdfTextExtractor(
        document,
      );

      String text =
      extractor.extractText();

      document.dispose();

      // Prevent extremely large PDF text
      // from consuming the local storage
      // and Gemini request unnecessarily.
      const maxCharacters = 60000;

      if (text.length > maxCharacters) {
        text = text.substring(
          0,
          maxCharacters,
        );

        text +=
        "\n\n[PDF text truncated for performance.]";
      }

      return text;
    } catch (e) {
      debugPrint(
        "PDF extraction error: $e",
      );

      return "";
    }
  }

  // ============================================================
  // RESTORE ATTACHMENT FROM CHAT
  // ============================================================

  void restoreAttachmentFromMessages() {
    clearActiveAttachment();

    for (final message
    in messages.reversed) {
      final type =
      message["attachmentType"];

      if (type == "image") {
        final data =
        message["attachmentData"];

        if (data is String &&
            data.isNotEmpty) {
          try {
            selectedImage =
                base64Decode(data);

            activeImageName =
            message[
            "attachmentName"];

            activeImageMimeType =
                message[
                "attachmentMimeType"] ??
                    "image/jpeg";

            activeAttachmentId =
            message[
            "attachmentId"];

            return;
          } catch (e) {
            debugPrint(
              "Image restore error: $e",
            );
          }
        }
      }

      if (type == "pdf") {
        final pdfText =
        message["pdfText"];

        if (pdfText is String &&
            pdfText.isNotEmpty) {
          activePdfText =
              pdfText;

          activePdfName =
          message[
          "attachmentName"];

          activeAttachmentId =
          message[
          "attachmentId"];

          return;
        }
      }
    }
  }

  // ============================================================
  // CLEAR ACTIVE ATTACHMENT
  // ============================================================

  void clearActiveAttachment() {
    selectedImage = null;

    selectedPdf = null;

    activePdfText = null;

    activePdfName = null;

    activeImageName = null;

    activeImageMimeType =
    "image/jpeg";

    activeAttachmentId = null;
  }

  // ============================================================
  // CHECK IF ATTACHMENT ALREADY SAVED
  // ============================================================

  bool attachmentAlreadySaved() {
    if (activeAttachmentId == null) {
      return false;
    }

    return messages.any(
          (message) =>
      message["attachmentId"] ==
          activeAttachmentId,
    );
  }

  // ============================================================
  // SEND MESSAGE
  // ============================================================

  Future<void> sendMessage() async {
    final userText =
    controller.text.trim();

    if (userText.isEmpty ||
        isThinking) {
      return;
    }

    controller.clear();

    final previousHistory =
    List<Map<String, dynamic>>.from(
      messages,
    );

    // ----------------------------------------------------------
    // Prepare attachment information
    // ----------------------------------------------------------

    String? attachmentType;

    String? attachmentData;

    String? attachmentName;

    String? attachmentMimeType;

    String? pdfTextForRequest;

    // IMAGE
    if (selectedImage != null) {
      attachmentType = "image";

      attachmentName =
          activeImageName ??
              "Image";

      attachmentMimeType =
          activeImageMimeType;

      if (!attachmentAlreadySaved() &&
          keepAttachments) {
        attachmentData =
            base64Encode(
              selectedImage!,
            );
      }
    }

    // PDF
    else if (activePdfText != null ||
        selectedPdf != null) {
      attachmentType = "pdf";

      attachmentName =
          activePdfName ??
              selectedPdf?.name ??
              "PDF";

      if (activePdfText == null &&
          selectedPdf != null) {
        if (mounted) {
          setState(() {
            isThinking = true;
          });
        }

        activePdfText =
        await extractPdfText();
      }

      pdfTextForRequest =
          activePdfText;

      if (pdfTextForRequest ==
          null ||
          pdfTextForRequest!
              .trim()
              .isEmpty) {
        if (mounted) {
          setState(() {
            isThinking = false;
          });

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            const SnackBar(
              content: Text(
                "I couldn't read text from this PDF.",
              ),
            ),
          );
        }

        return;
      }
    }

    if (mounted) {
      setState(() {
        isThinking = true;
      });
    }

    // ----------------------------------------------------------
    // User message
    // ----------------------------------------------------------

    final Map<String, dynamic>
    userMessage = {
      "text": userText,
      "isUser": true,
    };

    // Save attachment only once in
    // the conversation to avoid
    // duplicating huge image/PDF data.
    if (keepAttachments &&
        !attachmentAlreadySaved() &&
        activeAttachmentId != null) {
      userMessage[
      "attachmentId"] =
          activeAttachmentId;

      userMessage[
      "attachmentType"] =
          attachmentType;

      userMessage[
      "attachmentName"] =
          attachmentName;

      if (attachmentType ==
          "image") {
        userMessage[
        "attachmentData"] =
            attachmentData;

        userMessage[
        "attachmentMimeType"] =
            attachmentMimeType;
      }

      if (attachmentType ==
          "pdf") {
        userMessage[
        "pdfText"] =
            pdfTextForRequest;
      }
    }

    if (!mounted) return;

    setState(() {
      messages.add(
        userMessage,
      );
    });

    // ----------------------------------------------------------
    // Chat title
    // ----------------------------------------------------------

    if (currentChatTitle ==
        "New Chat") {
      currentChatTitle =
      userText.length > 35
          ? "${userText.substring(0, 35)}..."
          : userText;
    }

    await updateCurrentChat();

    // ----------------------------------------------------------
    // AI RESPONSE
    // ----------------------------------------------------------

    String reply;

    try {
      // ========================================================
      // IMAGE QUESTION
      // ========================================================

      if (selectedImage != null) {
        reply =
        await GeminiService.askImage(
          selectedImage!,
          userText,
          mimeType:
          activeImageMimeType,
          history:
          previousHistory,
        );
      }

      // ========================================================
      // PDF QUESTION
      // ========================================================

      else if (pdfTextForRequest != null &&
          pdfTextForRequest!
              .trim()
              .isNotEmpty) {
        final prompt = """
You are an AI Study Assistant.

The user has uploaded a PDF.

Use ONLY the PDF content below to answer the user's question.

PDF FILE:
${attachmentName ?? "PDF"}

PDF CONTENT:
$pdfTextForRequest

USER QUESTION:
$userText

Instructions:
- Answer clearly and accurately.
- Use information from the PDF.
- Do not invent information.
- If the answer is not available in the PDF, say that clearly.
- Keep the answer useful for a student.
""";

        reply =
        await GeminiService.askAI(
          prompt,
          history:
          previousHistory,
        );
      }

      // ========================================================
      // NORMAL CHAT
      // ========================================================

      else {
        reply =
        await GeminiService.askAI(
          userText,
          history:
          previousHistory,
        );
      }
    } catch (e) {
      reply =
      "Sorry, something went wrong.\n\n$e";
    }

    if (!mounted) return;

    setState(() {
      isThinking = false;

      messages.add({
        "text": reply,
        "isUser": false,
      });
    });

    // IMPORTANT:
    // Attachment is intentionally NOT cleared.
    // This lets the user ask another question
    // about the same image/PDF.
    await updateCurrentChat();
  }

  // ============================================================
  // OPEN CHAT
  // ============================================================

  Future<void> openChat(
      Map<String, dynamic> chat,
      ) async {
    Navigator.pop(context);

    setState(() {
      currentChatId =
          chat["id"].toString();

      currentChatTitle =
          chat["title"]?.toString() ??
              "Chat";

      messages =
      List<Map<String, dynamic>>.from(
        (chat["messages"] as List)
            .map(
              (message) =>
          Map<String, dynamic>.from(
            message,
          ),
        ),
      );

      controller.clear();

      restoreAttachmentFromMessages();
    });
  }

  // ============================================================
  // PIN CHAT
  // ============================================================

  Future<void> togglePinChat(
      Map<String, dynamic> chat,
      ) async {
    final id =
    chat["id"].toString();

    setState(() {
      if (pinnedChatIds
          .contains(id)) {
        pinnedChatIds.remove(id);
      } else {
        pinnedChatIds.add(id);
      }
    });

    await saveConversations();
  }

  // ============================================================
  // RENAME CHAT
  // ============================================================

  Future<void> renameChat(
      Map<String, dynamic> chat,
      ) async {
    final renameController =
    TextEditingController(
      text:
      chat["title"]?.toString() ??
          "Chat",
    );

    final newName =
    await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
          const Text("Rename chat"),
          content: TextField(
            controller:
            renameController,
            autofocus: true,
            decoration:
            const InputDecoration(
              hintText:
              "Chat name",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                    context,
                  ),
              child:
              const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  renameController
                      .text
                      .trim(),
                );
              },
              child:
              const Text("Save"),
            ),
          ],
        );
      },
    );

    renameController.dispose();

    if (newName == null ||
        newName.isEmpty) {
      return;
    }

    final index =
    conversations.indexWhere(
          (item) =>
      item["id"] ==
          chat["id"],
    );

    if (index != -1) {
      conversations[index]
      ["title"] = newName;
    }

    if (chat["id"] ==
        currentChatId) {
      setState(() {
        currentChatTitle =
            newName;
      });
    }

    await saveConversations();
  }

  // ============================================================
  // DELETE CHAT
  // ============================================================

  Future<void> deleteChat(
      Map<String, dynamic> chat,
      ) async {
    final confirm =
    await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
          const Text("Delete chat?"),
          content: Text(
            "Delete \"${chat["title"]}\"?",
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                    context,
                    false,
                  ),
              child:
              const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(
                    context,
                    true,
                  ),
              child:
              const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() {
      conversations.removeWhere(
            (item) =>
        item["id"] ==
            chat["id"],
      );

      pinnedChatIds.remove(
        chat["id"],
      );

      if (chat["id"] ==
          currentChatId) {
        createNewChatInternal();
      }
    });

    await saveConversations();
  }

  // ============================================================
  // CHAT LIST
  // ============================================================

  Widget buildChatList({
    required List<Map<String, dynamic>>
    chats,
  }) {
    if (chats.isEmpty) {
      return Center(
        child: Text(
          "No chats yet.",
          style: TextStyle(
            color: isDarkMode
                ? Colors.white60
                : Colors.grey,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: chats.length,
      itemBuilder:
          (context, index) {
        final chat =
        chats[index];

        final isPinned =
        pinnedChatIds.contains(
          chat["id"],
        );

        return ListTile(
          leading:
          CircleAvatar(
            backgroundColor:
            isPinned
                ? Colors.deepPurple
                .shade100
                : Colors.indigo
                .shade50,
            child: Icon(
              isPinned
                  ? Icons.push_pin
                  : Icons
                  .chat_bubble_outline,
              color: isPinned
                  ? Colors.deepPurple
                  : Colors.indigo,
            ),
          ),
          title: Text(
            chat["title"] ??
                "Chat",
            maxLines: 1,
            overflow:
            TextOverflow.ellipsis,
          ),
          subtitle: Text(
            "${(chat["messages"] as List).length} messages",
          ),
          onTap: () =>
              openChat(chat),
          trailing:
          PopupMenuButton<
              String>(
            onSelected:
                (value) async {
              if (value ==
                  "pin") {
                await togglePinChat(
                  chat,
                );
              }

              if (value ==
                  "rename") {
                await renameChat(
                  chat,
                );
              }

              if (value ==
                  "delete") {
                await deleteChat(
                  chat,
                );
              }
            },
            itemBuilder:
                (context) =>
            [
              PopupMenuItem(
                value: "pin",
                child: Text(
                  isPinned
                      ? "Unpin chat"
                      : "Pin chat",
                ),
              ),
              const PopupMenuItem(
                value: "rename",
                child:
                Text("Rename"),
              ),
              const PopupMenuItem(
                value: "delete",
                child:
                Text("Delete"),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // HISTORY
  // ============================================================

  void showHistory() {
    Navigator.pop(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
      isDarkMode
          ? const Color(
        0xFF111827,
      )
          : Colors.white,
      builder: (context) {
        return SizedBox(
          height:
          MediaQuery.of(context)
              .size
              .height *
              0.80,
          child: Column(
            children: [
              Padding(
                padding:
                const EdgeInsets
                    .all(18),
                child: Row(
                  children: [
                    const Icon(
                      Icons.history,
                      color:
                      Colors.indigo,
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Text(
                      "Chat History",
                      style:
                      TextStyle(
                        fontSize: 20,
                        fontWeight:
                        FontWeight.bold,
                        color: isDarkMode
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                height: 1,
              ),
              Expanded(
                child:
                buildChatList(
                  chats:
                  conversations,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // PINNED
  // ============================================================

  void showPinned() {
    Navigator.pop(context);

    final pinnedChats =
    conversations
        .where(
          (chat) =>
          pinnedChatIds
              .contains(
            chat["id"],
          ),
    )
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
      isDarkMode
          ? const Color(
        0xFF111827,
      )
          : Colors.white,
      builder: (context) {
        return SizedBox(
          height:
          MediaQuery.of(context)
              .size
              .height *
              0.80,
          child: Column(
            children: [
              Padding(
                padding:
                const EdgeInsets
                    .all(18),
                child: Row(
                  children: [
                    const Icon(
                      Icons.push_pin,
                      color:
                      Colors.deepPurple,
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Text(
                      "Pinned Chats",
                      style:
                      TextStyle(
                        fontSize: 20,
                        fontWeight:
                        FontWeight.bold,
                        color: isDarkMode
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                height: 1,
              ),
              Expanded(
                child:
                buildChatList(
                  chats:
                  pinnedChats,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // CLEAR ALL HISTORY
  // ============================================================

  Future<void> clearAllHistory() async {
    final confirm =
    await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            "Clear all chat history?",
          ),
          content: const Text(
            "This will permanently remove saved chats and pinned chats.",
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                    context,
                    false,
                  ),
              child:
              const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(
                    context,
                    true,
                  ),
              child: const Text(
                "Clear",
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() {
      conversations.clear();

      pinnedChatIds.clear();

      createNewChatInternal();

      controller.clear();
    });

    await saveConversations();
  }

  // ============================================================
  // SETTINGS
  // ============================================================

  Future<void> showSettings() async {
    Navigator.pop(context);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder:
              (
              context,
              setDialogState,
              ) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(
                    Icons.settings,
                    color:
                    Colors.deepPurple,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  const Text(
                    "Settings",
                  ),
                ],
              ),
              content:
              SingleChildScrollView(
                child: Column(
                  mainAxisSize:
                  MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text(
                        "Dark mode",
                      ),
                      subtitle:
                      const Text(
                        "Change the chatbot appearance",
                      ),
                      value:
                      isDarkMode,
                      onChanged:
                          (value) async {
                        setDialogState(
                              () {
                            isDarkMode =
                                value;
                          },
                        );

                        setState(() {});

                        final prefs =
                        await SharedPreferences
                            .getInstance();

                        await prefs
                            .setBool(
                          "dark_mode",
                          value,
                        );
                      },
                    ),
                    SwitchListTile(
                      title: const Text(
                        "Auto-save chats",
                      ),
                      subtitle:
                      const Text(
                        "Save conversations to chat history",
                      ),
                      value:
                      autoSaveHistory,
                      onChanged:
                          (value) async {
                        setDialogState(
                              () {
                            autoSaveHistory =
                                value;
                          },
                        );

                        final prefs =
                        await SharedPreferences
                            .getInstance();

                        await prefs
                            .setBool(
                          "auto_save_history",
                          value,
                        );

                        if (value) {
                          await updateCurrentChat();
                        }
                      },
                    ),
                    SwitchListTile(
                      title: const Text(
                        "Keep attachments",
                      ),
                      subtitle:
                      const Text(
                        "Keep images and PDFs inside saved chats",
                      ),
                      value:
                      keepAttachments,
                      onChanged:
                          (value) async {
                        setDialogState(
                              () {
                            keepAttachments =
                                value;
                          },
                        );

                        final prefs =
                        await SharedPreferences
                            .getInstance();

                        await prefs
                            .setBool(
                          "keep_attachments",
                          value,
                        );
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading:
                      const Icon(
                        Icons.delete_sweep,
                        color: Colors.red,
                      ),
                      title: const Text(
                        "Clear all history",
                      ),
                      subtitle:
                      const Text(
                        "Delete all saved conversations",
                      ),
                      onTap: () async {
                        Navigator.pop(
                          dialogContext,
                        );

                        await clearAllHistory();
                      },
                    ),
                    ListTile(
                      leading:
                      const Icon(
                        Icons.info_outline,
                        color:
                        Colors.indigo,
                      ),
                      title: const Text(
                        "About",
                      ),
                      subtitle:
                      const Text(
                        "AI Study Assistant",
                      ),
                      onTap: () {
                        showDialog(
                          context:
                          context,
                          builder:
                              (context) {
                            return AlertDialog(
                              title:
                              const Text(
                                "AI Study Assistant",
                              ),
                              content:
                              const Text(
                                "A Flutter AI chatbot for studying, normal conversations, image questions, PDF questions, chat history and pinned conversations.",
                              ),
                              actions: [
                                TextButton(
                                  onPressed:
                                      () {
                                    Navigator.pop(
                                      context,
                                    );
                                  },
                                  child:
                                  const Text(
                                    "OK",
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading:
                      Icon(
                        GeminiService
                            .hasApiKey
                            ? Icons
                            .check_circle
                            : Icons
                            .error,
                        color:
                        GeminiService
                            .hasApiKey
                            ? Colors
                            .green
                            : Colors
                            .red,
                      ),
                      title: const Text(
                        "Gemini AI",
                      ),
                      subtitle:
                      Text(
                        GeminiService
                            .hasApiKey
                            ? "API configured • ${GeminiService.modelName}"
                            : "API key not configured",
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(
                        dialogContext,
                      ),
                  child:
                  const Text("Close"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // MESSAGE ATTACHMENT
  // ============================================================

  Widget buildMessageAttachment(
      Map<String, dynamic> message,
      ) {
    final type =
    message["attachmentType"];

    if (type == "image") {
      final data =
      message["attachmentData"];

      if (data is! String ||
          data.isEmpty) {
        return const SizedBox();
      }

      try {
        final bytes =
        base64Decode(data);

        return Padding(
          padding:
          const EdgeInsets.only(
            top: 12,
          ),
          child: ClipRRect(
            borderRadius:
            BorderRadius.circular(
              14,
            ),
            child: Image.memory(
              bytes,
              height: 180,
              width:
              double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (e) {
        return const SizedBox();
      }
    }

    if (type == "pdf") {
      return Padding(
        padding:
        const EdgeInsets.only(
          top: 12,
        ),
        child: Container(
          padding:
          const EdgeInsets.all(
            12,
          ),
          decoration:
          BoxDecoration(
            color:
            Colors.red.shade50,
            borderRadius:
            BorderRadius.circular(
              14,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.picture_as_pdf,
                color: Colors.red,
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: Text(
                  message[
                  "attachmentName"] ??
                      "PDF",
                  maxLines: 2,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  const TextStyle(
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox();
  }

  // ============================================================
  // CURRENT ATTACHMENT PREVIEW
  // ============================================================

  Widget buildActiveAttachmentPreview() {
    // IMAGE
    if (selectedImage != null) {
      return Padding(
        padding:
        const EdgeInsets.fromLTRB(
          12,
          12,
          12,
          4,
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius:
              BorderRadius.circular(
                18,
              ),
              child: Image.memory(
                selectedImage!,
                height: 170,
                width:
                double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: CircleAvatar(
                backgroundColor:
                Colors.black54,
                child: IconButton(
                  icon: const Icon(
                    Icons.close,
                    color:
                    Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      clearActiveAttachment();
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    // PDF
    if (activePdfName != null) {
      return Padding(
        padding:
        const EdgeInsets.fromLTRB(
          12,
          12,
          12,
          4,
        ),
        child: Card(
          elevation: 2,
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(
              18,
            ),
          ),
          child: ListTile(
            leading:
            const CircleAvatar(
              backgroundColor:
              Color(0xFFFFE4E6),
              child: Icon(
                Icons.picture_as_pdf,
                color: Colors.red,
              ),
            ),
            title: Text(
              activePdfName!,
              maxLines: 1,
              overflow:
              TextOverflow.ellipsis,
              style:
              const TextStyle(
                fontWeight:
                FontWeight.bold,
              ),
            ),
            subtitle:
            const Text(
              "PDF ready • Ask a question",
            ),
            trailing:
            IconButton(
              icon: const Icon(
                Icons.close,
              ),
              onPressed: () {
                setState(() {
                  clearActiveAttachment();
                });
              },
            ),
          ),
        ),
      );
    }

    return const SizedBox();
  }

  // ============================================================
  // DRAWER ITEM
  // ============================================================

  Widget drawerItem(
      IconData icon,
      String title,
      Color color,
      VoidCallback onTap,
      ) {
    return ListTile(
      contentPadding:
      const EdgeInsets.symmetric(
        horizontal: 22,
        vertical: 3,
      ),
      leading:
      CircleAvatar(
        backgroundColor:
        color.withValues(
          alpha: 0.12,
        ),
        child: Icon(
          icon,
          color: color,
        ),
      ),
      title: Text(
        title,
        style:
        const TextStyle(
          fontWeight:
          FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    final backgroundColor =
    isDarkMode
        ? const Color(
      0xFF0F172A,
    )
        : const Color(
      0xFFF5F3FF,
    );

    final inputColor =
    isDarkMode
        ? const Color(
      0xFF1E293B,
    )
        : Colors.white;

    final messageColor =
    isDarkMode
        ? const Color(
      0xFF1E293B,
    )
        : Colors.white;

    final textColor =
    isDarkMode
        ? Colors.white
        : const Color(
      0xFF242038,
    );

    return Scaffold(
      backgroundColor:
      backgroundColor,

      // ========================================================
      // DRAWER
      // ========================================================

      drawer: Drawer(
        child: Container(
          decoration:
          const BoxDecoration(
            gradient:
            LinearGradient(
              begin:
              Alignment.topCenter,
              end:
              Alignment.bottomCenter,
              colors: [
                Color(
                  0xFF4F46E5,
                ),
                Color(
                  0xFF7C3AED,
                ),
                Color(
                  0xFFF5F3FF,
                ),
              ],
              stops: [
                0.0,
                0.38,
                0.75,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(
                  height: 20,
                ),
                const CircleAvatar(
                  radius: 38,
                  backgroundColor:
                  Colors.white,
                  child: Icon(
                    Icons.auto_awesome,
                    size: 42,
                    color:
                    Colors.deepPurple,
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                const Text(
                  "AI Study Assistant",
                  style:
                  TextStyle(
                    color:
                    Colors.white,
                    fontSize: 23,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 5,
                ),
                const Text(
                  "Learn • Ask • Explore",
                  style:
                  TextStyle(
                    color:
                    Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(
                  height: 25,
                ),
                Expanded(
                  child:
                  Container(
                    decoration:
                    BoxDecoration(
                      color: isDarkMode
                          ? const Color(
                        0xFF111827,
                      )
                          : const Color(
                        0xFFF8F7FF,
                      ),
                      borderRadius:
                      const BorderRadius
                          .vertical(
                        top: Radius
                            .circular(
                          28,
                        ),
                      ),
                    ),
                    child:
                    ListView(
                      padding:
                      const EdgeInsets
                          .only(
                        top: 18,
                      ),
                      children: [
                        drawerItem(
                          Icons.add_comment,
                          "New Chat",
                          Colors.indigo,
                              () async {
                            Navigator.pop(
                              context,
                            );
                            await newChat();
                          },
                        ),
                        drawerItem(
                          Icons.history,
                          "History",
                          Colors.blue,
                          showHistory,
                        ),
                        drawerItem(
                          Icons.push_pin,
                          "Pinned Chats",
                          Colors.deepPurple,
                          showPinned,
                        ),
                        drawerItem(
                          Icons.settings,
                          "Settings",
                          Colors.teal,
                          showSettings,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        elevation: 0,
        backgroundColor:
        Colors.indigo,
        foregroundColor:
        Colors.white,
        centerTitle: true,
        title: Row(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome,
              size: 21,
            ),
            const SizedBox(
              width: 8,
            ),
            Flexible(
              child: Text(
                currentChatTitle,
                maxLines: 1,
                overflow:
                TextOverflow
                    .ellipsis,
                style:
                const TextStyle(
                  fontWeight:
                  FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),

      // ========================================================
      // BODY
      // ========================================================

      body: Column(
        children: [
          // ACTIVE ATTACHMENT
          buildActiveAttachmentPreview(),

          // WELCOME CARD
          if (messages.length ==
              1 &&
              !isThinking)
            Padding(
              padding:
              const EdgeInsets
                  .fromLTRB(
                20,
                18,
                20,
                8,
              ),
              child: Container(
                width:
                double.infinity,
                padding:
                const EdgeInsets
                    .all(
                  20,
                ),
                decoration:
                BoxDecoration(
                  gradient:
                  const LinearGradient(
                    colors: [
                      Color(
                        0xFF6366F1,
                      ),
                      Color(
                        0xFF8B5CF6,
                      ),
                    ],
                  ),
                  borderRadius:
                  BorderRadius
                      .circular(
                    24,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors
                          .deepPurple
                          .withValues(
                        alpha: 0.20,
                      ),
                      blurRadius: 15,
                      offset:
                      const Offset(
                        0,
                        6,
                      ),
                    ),
                  ],
                ),
                child:
                const Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color:
                      Colors.white,
                      size: 30,
                    ),
                    SizedBox(
                      height: 10,
                    ),
                    Text(
                      "What can I help you learn?",
                      style:
                      TextStyle(
                        color:
                        Colors.white,
                        fontSize: 21,
                        fontWeight:
                        FontWeight
                            .bold,
                      ),
                    ),
                    SizedBox(
                      height: 6,
                    ),
                    Text(
                      "Ask a question, upload an image, or attach a PDF.",
                      style:
                      TextStyle(
                        color:
                        Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ======================================================
          // MESSAGES
          // ======================================================

          Expanded(
            child:
            ListView.builder(
              padding:
              const EdgeInsets
                  .fromLTRB(
                12,
                8,
                12,
                12,
              ),
              itemCount:
              messages.length,
              itemBuilder:
                  (
                  context,
                  index,
                  ) {
                final msg =
                messages[index];

                final bool isUser =
                    msg["isUser"] ==
                        true;

                return Align(
                  alignment:
                  isUser
                      ? Alignment
                      .centerRight
                      : Alignment
                      .centerLeft,
                  child:
                  Container(
                    margin:
                    const EdgeInsets
                        .symmetric(
                      vertical: 6,
                    ),
                    padding:
                    const EdgeInsets
                        .symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    constraints:
                    const BoxConstraints(
                      maxWidth: 370,
                    ),
                    decoration:
                    BoxDecoration(
                      gradient:
                      isUser
                          ? const LinearGradient(
                        colors: [
                          Color(
                            0xFF4F46E5,
                          ),
                          Color(
                            0xFF7C3AED,
                          ),
                        ],
                      )
                          : null,
                      color:
                      isUser
                          ? null
                          : messageColor,
                      borderRadius:
                      BorderRadius
                          .only(
                        topLeft:
                        const Radius
                            .circular(
                          20,
                        ),
                        topRight:
                        const Radius
                            .circular(
                          20,
                        ),
                        bottomLeft:
                        Radius
                            .circular(
                          isUser
                              ? 20
                              : 5,
                        ),
                        bottomRight:
                        Radius
                            .circular(
                          isUser
                              ? 5
                              : 20,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors
                              .black
                              .withValues(
                            alpha:
                            0.06,
                          ),
                          blurRadius:
                          8,
                          offset:
                          const Offset(
                            0,
                            3,
                          ),
                        ),
                      ],
                    ),
                    child:
                    Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                      children: [
                        MarkdownBody(
                          data:
                          msg["text"] ??
                              "",
                          styleSheet:
                          MarkdownStyleSheet(
                            p:
                            TextStyle(
                              fontSize:
                              15.5,
                              height:
                              1.45,
                              color: isUser
                                  ? Colors
                                  .white
                                  : textColor,
                            ),
                            strong:
                            TextStyle(
                              fontWeight:
                              FontWeight
                                  .bold,
                              color: isUser
                                  ? Colors
                                  .white
                                  : Colors
                                  .indigo,
                            ),
                            code:
                            TextStyle(
                              fontFamily:
                              "monospace",
                              fontSize:
                              14,
                              color:
                              textColor,
                            ),
                          ),
                        ),

                        // IMAGE/PDF SAVED
                        // INSIDE THE CHAT
                        buildMessageAttachment(
                          msg,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // ======================================================
          // THINKING
          // ======================================================

          if (isThinking)
            const Padding(
              padding:
              EdgeInsets.only(
                left: 22,
                bottom: 8,
              ),
              child: Align(
                alignment:
                Alignment
                    .centerLeft,
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child:
                      CircularProgressIndicator(
                        strokeWidth:
                        2,
                        color:
                        Colors.deepPurple,
                      ),
                    ),
                    SizedBox(
                      width: 10,
                    ),
                    Text(
                      "AI is thinking...",
                      style:
                      TextStyle(
                        color:
                        Colors.deepPurple,
                        fontStyle:
                        FontStyle
                            .italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ======================================================
          // INPUT
          // ======================================================

          Container(
            padding:
            const EdgeInsets
                .fromLTRB(
              10,
              8,
              10,
              12,
            ),
            decoration:
            BoxDecoration(
              color: inputColor,
              boxShadow: [
                BoxShadow(
                  color: Colors
                      .black
                      .withValues(
                    alpha: 0.08,
                  ),
                  blurRadius: 12,
                  offset:
                  const Offset(
                    0,
                    -3,
                  ),
                ),
              ],
            ),
            child:
            Row(
              crossAxisAlignment:
              CrossAxisAlignment
                  .end,
              children: [
                IconButton(
                  tooltip:
                  "Image",
                  icon:
                  const Icon(
                    Icons
                        .image_outlined,
                    color: Colors
                        .deepPurple,
                  ),
                  onPressed:
                  isThinking
                      ? null
                      : pickImage,
                ),

                IconButton(
                  tooltip:
                  "PDF",
                  icon:
                  const Icon(
                    Icons
                        .picture_as_pdf_outlined,
                    color: Colors
                        .redAccent,
                  ),
                  onPressed:
                  isThinking
                      ? null
                      : pickPdf,
                ),

                Expanded(
                  child:
                  TextField(
                    controller:
                    controller,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction:
                    TextInputAction
                        .send,
                    style:
                    TextStyle(
                      color:
                      isDarkMode
                          ? Colors
                          .white
                          : Colors
                          .black,
                    ),
                    decoration:
                    InputDecoration(
                      hintText:
                      selectedImage !=
                          null
                          ? "Ask about this image..."
                          : activePdfName !=
                          null
                          ? "Ask about this PDF..."
                          : "Ask anything...",
                      hintStyle:
                      TextStyle(
                        color:
                        isDarkMode
                            ? Colors
                            .white60
                            : Colors
                            .grey,
                      ),
                      filled: true,
                      fillColor:
                      isDarkMode
                          ? const Color(
                        0xFF1E293B,
                      )
                          : const Color(
                        0xFFF3F1FF,
                      ),
                      border:
                      OutlineInputBorder(
                        borderRadius:
                        BorderRadius
                            .circular(
                          25,
                        ),
                        borderSide:
                        BorderSide
                            .none,
                      ),
                      contentPadding:
                      const EdgeInsets
                          .symmetric(
                        horizontal:
                        18,
                        vertical:
                        12,
                      ),
                    ),
                    onSubmitted:
                        (_) =>
                        sendMessage(),
                  ),
                ),

                const SizedBox(
                  width: 8,
                ),

                Container(
                  decoration:
                  const BoxDecoration(
                    shape:
                    BoxShape
                        .circle,
                    gradient:
                    LinearGradient(
                      colors: [
                        Color(
                          0xFF4F46E5,
                        ),
                        Color(
                          0xFF7C3AED,
                        ),
                      ],
                    ),
                  ),
                  child:
                  IconButton(
                    tooltip:
                    "Send",
                    onPressed:
                    isThinking
                        ? null
                        : sendMessage,
                    icon:
                    const Icon(
                      Icons
                          .send_rounded,
                      color:
                      Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}