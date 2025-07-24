import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../widgets/message_bubble.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../services/translation_service.dart';
import 'package:provider/provider.dart';
import '../locale_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/animated_card.dart';
import '../widgets/animated_button.dart';
import '../widgets/typing_text_animation.dart';
import 'package:medical/theme/theme.dart';
import 'package:medical/screens/voice_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;  
  late AnimationController _typingAnimationController;
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _selectedType = ''; // Store selected medical type
  final List<String> _medicalTypes = ['Select Type', 'Ayurvedic', 'Allopathic'];
  bool _waitingForTypeSelection = false; // Track if we're waiting for type selection

  
Color neonGreen = Color(0xFF39FF14); // example
 Color backgroundMid = Colors.grey[200]!;
 Color subtitleGray = Colors.grey;
 Color backgroundDark = Colors.black87;
 Color _textColor = Colors.black; // or appropriate color
 Color _primaryColor = Colors.blue; // or your theme color
 Color _cardColor = Colors.white; // or your card background
  // Language mapping from locale codes to language names
  final Map<String, String> _localeToLanguage = {
    'en': 'English',
    'hi': 'Hindi',
    'gu': 'Gujarati',
    'mr': 'Marathi',
    'ta': 'Tamil',
    'te': 'Telugu',
    'ml': 'Malayalam',
    'bn': 'Bengali',
    'kn': 'Kannada',
    'pa': 'Punjabi',
    'or': 'Odia',
    'as': 'Assamese',
  };

  // Get current language based on locale
  String _getCurrentLanguage() {
    final currentLocale = Provider.of<LocaleProvider>(context, listen: false).locale;
    return _localeToLanguage[currentLocale.languageCode] ?? 'English';
  }

  void _listen() async {
    var status = await Permission.microphone.status;

    if (!status.isGranted) {
      status = await Permission.microphone.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('Microphone permission is required.', style: TextStyle(color: _textColor))
));
        return;
      }
    }

    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (val) {
          setState(() => _isListening = false);
        },
      );

      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _textController.text = val.recognizedWords;
            });

            if (val.hasConfidenceRating && val.confidence > 0.5 && val.finalResult) {
              _sendMessage(val.recognizedWords);
              _speech.stop();
            }
          },
        );
      }
    } else {
      _speech.stop();
      setState(() => _isListening = false);
    }
  }

  // Quick action buttons - updated to use current locale
  List<Map<String, dynamic>> _getQuickActions() {
    final currentLocale = Provider.of<LocaleProvider>(context, listen: false).locale;
    
    switch (currentLocale.languageCode) {
      case 'hi':
        return [
          {'text': 'सिरदर्द का इलाज', 'icon': Icons.psychology, 'query': 'मुझे सिरदर्द है'},
          {'text': 'जलने का इलाज', 'icon': Icons.local_fire_department, 'query': 'जलने पर क्या करें?'},
          {'text': 'अपच की मदत', 'icon': Icons.dining, 'query': 'अपच की समस्या है'},
          {'text': 'कीड़े का काटना', 'icon': Icons.pest_control, 'query': 'कीड़े काटने का इलाज'},
        ];
      case 'mr':
        return [
          {'text': 'डोकेदुखीचा उपाय', 'icon': Icons.psychology, 'query': 'मला डोकेदुखी आहे'},
          {'text': 'जळण्याचा उपचार', 'icon': Icons.local_fire_department, 'query': 'जळण्यासाठी काय करावे?'},
          {'text': 'अपचनाची मदत', 'icon': Icons.dining, 'query': 'अपचनाची समस्या आहे'},
          {'text': 'कीड चावणे', 'icon': Icons.pest_control, 'query': 'कीड चावण्याचा उपाय'},
        ];
      default:
        return [
          {'text': 'Headache remedy', 'icon': Icons.psychology, 'query': 'I have a headache'},
          {'text': 'Burn treatment', 'icon': Icons.local_fire_department, 'query': 'What to do for a burn?'},
          {'text': 'Indigestion help', 'icon': Icons.dining, 'query': 'Help with indigestion'},
          {'text': 'Insect bite', 'icon': Icons.pest_control, 'query': 'Remedy for insect bite'},
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    _typingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    _speech = stt.SpeechToText();
    _selectedType = _medicalTypes[0]; // Default to 'Select Type'
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _typingAnimationController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    final trimmedText = text.trim();
    
    // Check if user is responding to type selection request
    if (_waitingForTypeSelection) {
      final lowerText = trimmedText.toLowerCase();
      if (lowerText.contains('ayurvedic') || lowerText.contains('allopathic')) {
        // User specified type in their message, let it go through normally
        setState(() {
          _waitingForTypeSelection = false;
        });
      } else {
        // Show quick selection buttons if they didn't specify type clearly
        _showTypeSelectionDialog();
        return;
      }
    }

    final userMessage = ChatMessage.user(trimmedText);
    
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
      _textController.clear();
    });

    _scrollToBottom();

    try {
      // Get current language from LocaleProvider
      final currentLanguage = _getCurrentLanguage();
      
      // Send message with selected type
      final effectiveType = (_selectedType == 'Select Type') ? '' : _selectedType;
      final botResponse = await ChatService.sendMessage(trimmedText, currentLanguage, effectiveType);
      
      setState(() {
        _messages.add(botResponse);
        // Check if bot is asking for type selection
        if (botResponse.requiresTypeSelection) {
          _waitingForTypeSelection = true;
        }
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage.bot(
          '⚠️ Error: ${e.toString().replaceFirst('Exception: ', '')}',
          isEmergency: true,
        ));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _showTypeSelectionDialog() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.medical_services, color: themeProvider.primaryColor),
            const SizedBox(width: 8),
            Text(
              'Choose Treatment Type', 
              style: TextStyle(color: themeProvider.primaryColor),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Please select your preferred treatment type:',
              style: TextStyle(color: themeProvider.textColor),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _waitingForTypeSelection = false;
                        _selectedType = 'Ayurvedic';
                      });
                      _sendMessage('ayurvedic: ${_textController.text.isEmpty ? "Please help me" : _textController.text}');
                    },
                    icon: const Icon(Icons.eco),
                    label: const Text('Ayurvedic'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeProvider.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _waitingForTypeSelection = false;
                        _selectedType = 'Allopathic';
                      });
                      _sendMessage('allopathic: ${_textController.text.isEmpty ? "Please help me" : _textController.text}');
                    },
                    icon: const Icon(Icons.medical_information),
                    label: const Text('Allopathic'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeProvider.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Keep this version of _scrollToBottom
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Use this version of _showInfoDialog that uses ThemeProvider
  void _showInfoDialog() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.info, color: themeProvider.primaryColor),
            const SizedBox(width: 8),
            Text(
              'About Medical First Aid', 
              style: TextStyle(color: themeProvider.primaryColor),
            ),
          ],
        ),
        content: Text(
          'This app provides both traditional Ayurvedic remedies and modern Allopathic treatments for common health issues. '
          'Always consult a qualified healthcare professional for serious conditions.\n\n'
          '⚠️ This is not a substitute for professional medical advice.',
          style: TextStyle(color: themeProvider.textColor, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Got it', 
              style: TextStyle(color: themeProvider.primaryColor),
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, child) {
        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return Scaffold(
              backgroundColor: Colors.transparent,
              body: Column(
                children: [
                  _buildAppBar(themeProvider),
                  Expanded(
                    child: _messages.isEmpty 
                        ? _buildEmptyState(themeProvider)
                        : _buildMessagesList(themeProvider),
                  ),
                  if (_isLoading) _buildTypingIndicator(themeProvider),
                  _buildInputArea(themeProvider),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAppBar(ThemeProvider themeProvider) {
    final currentLanguage = _getCurrentLanguage();
    
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        color: themeProvider.surfaceColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: themeProvider.primaryColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: themeProvider.primaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.local_hospital,
                  color: themeProvider.primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🏥 Medical First Aid',
                      style: TextStyle(
                        color: themeProvider.primaryColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Ayurvedic & Allopathic remedies',
                      style: TextStyle(
                        color: themeProvider.secondaryTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _showInfoDialog,
                icon: Icon(Icons.info_outline, color: themeProvider.primaryColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Language display (read-only, shows current selection from menu)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: themeProvider.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: themeProvider.primaryColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.language, color: themeProvider.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Language: ',
                  style: TextStyle(color: themeProvider.primaryColor, fontSize: 14),
                ),
                Expanded(
                  child: Text(
                    currentLanguage,
                    style: TextStyle(color: themeProvider.primaryColor, fontSize: 14),
                  ),
                ),
                Text(
                  '(Change from menu)',
                  style: TextStyle(
                    color: themeProvider.secondaryTextColor, 
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Medical type selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: themeProvider.primaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: themeProvider.primaryColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.medical_services, color: themeProvider.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Preference: ',
                  style: TextStyle(color: themeProvider.primaryColor, fontSize: 14),
                ),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedType,
                    dropdownColor: themeProvider.cardColor,
                    icon: Icon(Icons.arrow_drop_down, color: themeProvider.primaryColor),
                    underline: SizedBox(),
                    isExpanded: true,
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedType = newValue;
                          _waitingForTypeSelection = false; // Reset waiting state
                        });
                      }
                    },
                    items: _medicalTypes.map((type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Text(
                          type,
                          style: TextStyle(
                            color: themeProvider.textColor,
                            fontSize: 14,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          if (_selectedType == 'Select Type')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '💡 Tip: Select a type above or I\'ll ask you to choose',
                style: TextStyle(
                  color: themeProvider.secondaryTextColor,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

Widget _buildEmptyState(ThemeProvider themeProvider) {
  return Expanded(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40), // Add spacing from top
          AnimatedCard(
            padding: const EdgeInsets.all(24),
            borderRadius: BorderRadius.circular(100),
            child: ClipOval(
              child: Image.asset(
                'assets/Luna.png',
                height: 64,
                width: 64,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 24),
          TypingTextAnimation(
            text: 'Welcome to Medical First Aid',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: themeProvider.primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Get both traditional and modern remedies',
            style: TextStyle(
              fontSize: 16,
              color: themeProvider.secondaryTextColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildQuickActions(themeProvider),
        ],
      ),
    ),
  );
}

  Widget _buildQuickActions(ThemeProvider themeProvider) {
    final quickActions = _getQuickActions();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: quickActions.map((action) => 
        AnimatedCard(
          onTap: () => _sendMessage(action['query']),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          borderRadius: BorderRadius.circular(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action['icon'], 
                   color: themeProvider.primaryColor, 
                   size: 20),
              const SizedBox(width: 8),
              Text(
                action['text'],
                style: TextStyle(
                  color: themeProvider.primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ).toList(),
    );
  }

  Widget _buildMessagesList(ThemeProvider themeProvider) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        
        // Show type selection buttons for askType messages
        if (message.requiresTypeSelection) {
          return Column(
            children: [
              MessageBubble(
                message: message,
                isUserMessage: false,
                userColor: themeProvider.primaryColor,
                botColor: themeProvider.cardColor,
                textColor: themeProvider.textColor,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedCard(
                        onTap: () {
                          setState(() {
                            _waitingForTypeSelection = false;
                            _selectedType = 'Ayurvedic';
                          });
                          _sendMessage('ayurvedic: Please help me');
                        },
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        borderRadius: BorderRadius.circular(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.eco, color: themeProvider.primaryColor, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Ayurvedic',
                              style: TextStyle(
                                color: themeProvider.primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedCard(
                        onTap: () {
                          setState(() {
                            _waitingForTypeSelection = false;
                            _selectedType = 'Allopathic';
                          });
                          _sendMessage('allopathic: Please help me');
                        },
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        borderRadius: BorderRadius.circular(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.medical_information, color: themeProvider.primaryColor, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Allopathic',
                              style: TextStyle(
                                color: themeProvider.primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        
        return MessageBubble(
          message: message,
          isUserMessage: message.type == MessageType.user,
          userColor: themeProvider.primaryColor,
          botColor: themeProvider.cardColor,
          textColor: themeProvider.textColor,
        );
      },
    );
  }

  Widget _buildTypingIndicator(ThemeProvider themeProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: themeProvider.primaryColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.local_hospital,
              color: themeProvider.backgroundColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          AnimatedBuilder(
            animation: _typingAnimationController,
            builder: (context, child) {
              return Row(
                children: List.generate(3, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: themeProvider.primaryColor.withOpacity(
                        0.3 + 0.7 * 
                        ((_typingAnimationController.value + index * 0.3) % 1),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(width: 8),
          Text(
            'Analyzing your query...',
            style: TextStyle(
              color: themeProvider.secondaryTextColor,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ThemeProvider themeProvider) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: themeProvider.surfaceColor,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        topRight: Radius.circular(24),
      ),
      boxShadow: [
        BoxShadow(
          color: themeProvider.primaryColor.withOpacity(0.1),
          blurRadius: 10,
          offset: const Offset(0, -2),
        ),
      ],
    ),
    child: SafeArea(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              style: TextStyle(color: themeProvider.textColor),
              decoration: InputDecoration(
                hintText: _waitingForTypeSelection 
                    ? 'Choose Ayurvedic or Allopathic above...'
                    : 'Describe your health concern...',
                hintStyle: TextStyle(color: themeProvider.secondaryTextColor),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (text) => _sendMessage(text),
              enabled: !_waitingForTypeSelection, // Disable when waiting for type selection
            ),
          ),
          const SizedBox(width: 8),
          // Updated Microphone Button - Navigate to Voice Screen
          AnimatedCard(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(20),
            child: IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const VoiceScreen(),
                  ),
                );
              },
              icon: Icon(
                Icons.mic,
                color: themeProvider.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedButton(
            text: '',
            width: 48,
            height: 48,
            icon: _isLoading ? Icons.hourglass_empty : Icons.send,
            onPressed: (_isLoading || _waitingForTypeSelection) ? () {} : () => _sendMessage(_textController.text),
          ),
        ],
      ),
    ),
  );
  }
}