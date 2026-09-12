import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Notes App',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B7CFA),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: const NotesHomePage(),
    );
  }
}

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  static const String _storageKey = 'notes_app_notes_v1';
  final List<String> _defaultCategories = const [
    'Work',
    'Personal',
    'Ideas',
    'Study',
  ];

  List<Note> _notes = [];
  String _search = '';
  String _selectedFilter = 'All';
  bool _isLoading = true;

  List<String> get _filterOptions {
    final categories = <String>{..._defaultCategories};
    for (final note in _notes) {
      categories.add(note.category);
    }
    return ['All', 'Pinned', 'Favorites', ...categories];
  }

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final rawNotes = prefs.getString(_storageKey);

    if (rawNotes == null || rawNotes.isEmpty) {
      _notes = _buildSampleNotes();
      await _saveNotes();
    } else {
      final decoded = jsonDecode(rawNotes);
      if (decoded is List) {
        _notes = decoded
            .map<Note>((item) => Note.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _notes.map((note) => note.toJson()).toList(),
    );
    await prefs.setString(_storageKey, encoded);
  }

  List<Note> _buildSampleNotes() {
    final now = DateTime.now();
    return [
      Note(
        id: '1',
        title: 'خطة اليوم',
        content:
            'راجع التقارير، أرسل تحديثات العميل، واستعد لاجتماع الساعة 3 مساءً.',
        category: 'Work',
        isPinned: true,
        isFavorite: true,
        createdAt: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        updatedAt: now.subtract(const Duration(hours: 4)).millisecondsSinceEpoch,
      ),
      Note(
        id: '2',
        title: 'أفكار مشروع',
        content:
            'تجربة ميزات جديدة في التطبيق مثل إعدادات شخصية، تنبيهات ذكية، ومشاركة الملاحظات.',
        category: 'Ideas',
        isPinned: false,
        isFavorite: true,
        createdAt: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        updatedAt: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      ),
      Note(
        id: '3',
        title: 'ملاحظات الدراسة',
        content:
            'مراجعة الوحدة الثالثة، حل التدريبات، وتحديد 3 نقاط رئيسية للملخص النهائي.',
        category: 'Study',
        isPinned: false,
        isFavorite: false,
        createdAt: now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
        updatedAt: now.subtract(const Duration(hours: 8)).millisecondsSinceEpoch,
      ),
    ];
  }

  List<Note> get _filteredNotes {
    final query = _search.trim().toLowerCase();

    final filtered = _notes.where((note) {
      final matchesSearch = query.isEmpty ||
          note.title.toLowerCase().contains(query) ||
          note.content.toLowerCase().contains(query);

      final matchesFilter = switch (_selectedFilter) {
        'All' => true,
        'Pinned' => note.isPinned,
        'Favorites' => note.isFavorite,
        _ => note.category == _selectedFilter,
      };

      return matchesSearch && matchesFilter;
    }).toList();

    filtered.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      if (a.isFavorite != b.isFavorite) {
        return a.isFavorite ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return filtered;
  }

  Future<void> _showNoteDialog({Note? note}) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(text: note?.content ?? '');
    String categoryValue = note?.category ?? _defaultCategories.first;

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                note == null ? 'إضافة ملاحظة جديدة' : 'تعديل الملاحظة',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: titleController,
                          textDirection: TextDirection.rtl,
                          decoration: const InputDecoration(
                            labelText: 'العنوان',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'أدخل عنوانًا صحيحًا';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: contentController,
                          textDirection: TextDirection.rtl,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'المحتوى',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'أدخل محتوى الملاحظة';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: categoryValue,
                          decoration: const InputDecoration(
                            labelText: 'الفئة',
                            border: OutlineInputBorder(),
                          ),
                          items: _filterOptions
                              .where((item) => item != 'All' && item != 'Pinned' && item != 'Favorites')
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(category),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                categoryValue = value;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      final updatedNote = note == null
                          ? Note(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              title: titleController.text.trim(),
                              content: contentController.text.trim(),
                              category: categoryValue,
                              isPinned: false,
                              isFavorite: false,
                              createdAt: DateTime.now().millisecondsSinceEpoch,
                              updatedAt: DateTime.now().millisecondsSinceEpoch,
                            )
                          : note.copyWith(
                              title: titleController.text.trim(),
                              content: contentController.text.trim(),
                              category: categoryValue,
                              updatedAt: DateTime.now().millisecondsSinceEpoch,
                            );

                      setState(() {
                        if (note == null) {
                          _notes.insert(0, updatedNote);
                        } else {
                          final index = _notes.indexWhere((item) => item.id == note.id);
                          if (index != -1) {
                            _notes[index] = updatedNote;
                          }
                        }
                      });

                      _saveNotes();
                      Navigator.pop(context);
                    }
                  },
                  child: Text(note == null ? 'إضافة' : 'حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteNote(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الملاحظة؟'),
        content: Text('هل أنت متأكد أنك تريد حذف "${note.title}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _notes.removeWhere((item) => item.id == note.id);
      });
      await _saveNotes();
    }
  }

  void _togglePin(Note note) {
    setState(() {
      final index = _notes.indexWhere((item) => item.id == note.id);
      if (index != -1) {
        _notes[index] = _notes[index].copyWith(
          isPinned: !note.isPinned,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
    });
    _saveNotes();
  }

  void _toggleFavorite(Note note) {
    setState(() {
      final index = _notes.indexWhere((item) => item.id == note.id);
      if (index != -1) {
        _notes[index] = _notes[index].copyWith(
          isFavorite: !note.isFavorite,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
    });
    _saveNotes();
  }

  Color _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'work':
        return const Color(0xFF5B7CFA);
      case 'personal':
        return const Color(0xFF6EC6A4);
      case 'ideas':
        return const Color(0xFFF5B041);
      case 'study':
        return const Color(0xFFB16CE6);
      default:
        return const Color(0xFF8CA1B8);
    }
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final total = _notes.length;
    final pinned = _notes.where((note) => note.isPinned).length;
    final favorites = _notes.where((note) => note.isFavorite).length;

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5B7CFA), Color(0xFF8D6BFF)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5B7CFA).withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'ملاحظاتي',
                                      style: TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'إدارة يومك بشكل أنيق ومرن',
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Colors.white.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(
                                  Icons.sticky_note_2_outlined,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _buildSummaryCard(
                          title: 'الملاحظات',
                          value: total.toString(),
                          icon: Icons.notes_rounded,
                          color: const Color(0xFF5B7CFA),
                        ),
                        const SizedBox(width: 12),
                        _buildSummaryCard(
                          title: 'المفضلة',
                          value: favorites.toString(),
                          icon: Icons.favorite_rounded,
                          color: const Color(0xFFEC5E76),
                        ),
                        const SizedBox(width: 12),
                        _buildSummaryCard(
                          title: 'المثبتة',
                          value: pinned.toString(),
                          icon: Icons.push_pin_rounded,
                          color: const Color(0xFFF5B041),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: TextField(
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          hintText: 'بحث في الملاحظات...',
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _search = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _filterOptions.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final option = _filterOptions[index];
                          final isSelected = _selectedFilter == option;

                          return ChoiceChip(
                            label: Text(option),
                            selected: isSelected,
                            onSelected: (_) {
                              setState(() {
                                _selectedFilter = option;
                              });
                            },
                            selectedColor: const Color(0xFF5B7CFA),
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: _filteredNotes.isEmpty
                          ? const Center(
                              child: Text(
                                'لا توجد ملاحظات مطابقة لبحثك',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.black54,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _filteredNotes.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final note = _filteredNotes[index];
                                final accent = _categoryColor(note.category);

                                return Card(
                                  margin: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  elevation: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.35),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: accent.withValues(alpha: 0.18),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  note.category,
                                                  style: TextStyle(
                                                    color: accent,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const Spacer(),
                                              IconButton(
                                                onPressed: () => _togglePin(note),
                                                tooltip: note.isPinned ? 'إزالة التثبيت' : 'تثبيت',
                                                icon: Icon(
                                                  note.isPinned
                                                      ? Icons.push_pin_rounded
                                                      : Icons.push_pin_outlined,
                                                  color: note.isPinned
                                                      ? const Color(0xFFF5B041)
                                                      : Colors.grey,
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () => _toggleFavorite(note),
                                                tooltip: note.isFavorite ? 'إزالة المفضلة' : 'إضافة للمفضلة',
                                                icon: Icon(
                                                  note.isFavorite
                                                      ? Icons.favorite_rounded
                                                      : Icons.favorite_border_rounded,
                                                  color: note.isFavorite
                                                      ? const Color(0xFFEC5E76)
                                                      : Colors.grey,
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () => _showNoteDialog(note: note),
                                                tooltip: 'تعديل',
                                                icon: const Icon(Icons.edit_outlined),
                                              ),
                                              IconButton(
                                                onPressed: () => _deleteNote(note),
                                                tooltip: 'حذف',
                                                icon: const Icon(Icons.delete_outline_rounded),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            note.title,
                                            textDirection: TextDirection.rtl,
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            note.content,
                                            textDirection: TextDirection.rtl,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              height: 1.65,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.access_time_rounded,
                                                size: 16,
                                                color: Colors.black54,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                _formatDate(note.updatedAt),
                                                style: const TextStyle(
                                                  color: Colors.black54,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNoteDialog(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('ملاحظة جديدة'),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class Note {
  final String id;
  final String title;
  final String content;
  final String category;
  final bool isPinned;
  final bool isFavorite;
  final int createdAt;
  final int updatedAt;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.isPinned,
    required this.isFavorite,
    required this.createdAt,
    required this.updatedAt,
  });

  Note copyWith({
    String? id,
    String? title,
    String? content,
    String? category,
    bool? isPinned,
    bool? isFavorite,
    int? createdAt,
    int? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'category': category,
      'isPinned': isPinned,
      'isFavorite': isFavorite,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      category: json['category'] ?? 'Work',
      isPinned: json['isPinned'] ?? false,
      isFavorite: json['isFavorite'] ?? false,
      createdAt: json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
