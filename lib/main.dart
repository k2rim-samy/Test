import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('UTC'));

  await NotificationService.instance.init();
  runApp(const NotesApp());
}

class NotesApp extends StatefulWidget {
  const NotesApp({super.key});

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  AppSettings _settings = const AppSettings();
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _settings = AppSettings.fromPreferences(prefs);
      _isLoaded = true;
    });
  }

  Future<void> _applySettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notes_app_settings', jsonEncode(settings.toJson()));

    if (!mounted) return;
    setState(() {
      _settings = settings;
    });
  }

  ThemeData _buildTheme(Brightness brightness, Color accent) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          brightness == Brightness.dark ? const Color(0xFF0F172A) : const Color(0xFFF5F7FF),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: brightness == Brightness.dark ? Colors.white : Colors.black,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final locale = Locale(_settings.languageCode);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Notes App',
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: _settings.themeMode,
      theme: _buildTheme(Brightness.light, _settings.accentColor),
      darkTheme: _buildTheme(Brightness.dark, _settings.accentColor),
      home: NotesHomePage(
        settings: _settings,
        onSettingsChanged: _applySettings,
      ),
    );
  }
}

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  final AppSettings settings;
  final Future<void> Function(AppSettings settings) onSettingsChanged;

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  static const String _storageKey = 'notes_app_notes_v1';

  final List<String> _defaultCategories = const ['Work', 'Personal', 'Ideas', 'Study'];

  List<Note> _notes = [];
  String _search = '';
  String _selectedFilter = 'All';
  bool _isLoading = true;

  AppStrings get _strings => AppStrings.forLanguage(widget.settings.languageCode);

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

    _notes = [];

    if (rawNotes != null && rawNotes.isNotEmpty) {
      final decoded = jsonDecode(rawNotes);
      if (decoded is List) {
        _notes = decoded
            .map<Note>((item) => Note.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    }

    if (_notes.isNotEmpty) {
      for (final note in _notes) {
        await NotificationService.instance.scheduleReminder(note);
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
    final encoded = jsonEncode(_notes.map((note) => note.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  List<Note> get _filteredNotes {
    final query = _search.trim().toLowerCase();

    final filtered = _notes.where((note) {
      final matchesText = query.isEmpty ||
          note.title.toLowerCase().contains(query) ||
          note.content.toLowerCase().contains(query);

      final matchesFavorites = !widget.settings.showFavoritesOnly || note.isFavorite;
      final matchesPinned = !widget.settings.showPinnedOnly || note.isPinned;

      final matchesFilter = switch (_selectedFilter) {
        'All' => true,
        'Pinned' => note.isPinned,
        'Favorites' => note.isFavorite,
        _ => note.category == _selectedFilter,
      };

      return matchesText && matchesFavorites && matchesPinned && matchesFilter;
    }).toList();

    filtered.sort((a, b) {
      switch (widget.settings.sortMode) {
        case NoteSort.newest:
          return b.updatedAt.compareTo(a.updatedAt);
        case NoteSort.oldest:
          return a.updatedAt.compareTo(b.updatedAt);
        case NoteSort.pinnedFirst:
          if (a.isPinned != b.isPinned) {
            return a.isPinned ? -1 : 1;
          }
          return b.updatedAt.compareTo(a.updatedAt);
      }
    });

    return filtered;
  }

  Future<void> _showNoteDialog({Note? note}) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(text: note?.content ?? '');
    String categoryValue = note?.category ?? _defaultCategories.first;
    DateTime? reminderDateTime = note?.reminderAt != null
        ? DateTime.fromMillisecondsSinceEpoch(note!.reminderAt!)
        : null;

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final categoryItems = _filterOptions
                .where((item) => item != 'All' && item != 'Pinned' && item != 'Favorites')
                .toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                note == null ? _strings.addNoteTitle : _strings.editNoteTitle,
                style: const TextStyle(fontWeight: FontWeight.w700),
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
                          textDirection: widget.settings.languageCode == 'ar'
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: _strings.titleLabel,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return _strings.titleRequired;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: contentController,
                          textDirection: widget.settings.languageCode == 'ar'
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText: _strings.contentLabel,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return _strings.contentRequired;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: categoryValue,
                          decoration: InputDecoration(
                            labelText: _strings.categoryLabel,
                          ),
                          items: categoryItems
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
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () async {
                            if (!mounted) return;

                            final dialogContext = context;
                            final pickedDate = await showDatePicker(
                              context: dialogContext,
                              initialDate: reminderDateTime ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(const Duration(days: 1)),
                              lastDate: DateTime.now().add(const Duration(days: 3650)),
                            );

                            if (pickedDate == null) return;

                            if (!context.mounted) return;

                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(
                                reminderDateTime ?? DateTime.now(),
                              ),
                            );

                            if (pickedTime == null) return;

                            final combined = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              pickedTime.hour,
                              pickedTime.minute,
                            );

                            setDialogState(() {
                              reminderDateTime = combined;
                            });
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.alarm_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    reminderDateTime == null
                                        ? _strings.reminderLabel
                                        : '${_strings.reminderSet} ${_formatDateTime(reminderDateTime!.millisecondsSinceEpoch)}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(_strings.cancelText),
                ),
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) {
                      return;
                    }

                    final now = DateTime.now().millisecondsSinceEpoch;
                    final updatedNote = note == null
                        ? Note(
                            id: now.toString(),
                            title: titleController.text.trim(),
                            content: contentController.text.trim(),
                            category: categoryValue,
                            isPinned: false,
                            isFavorite: false,
                            createdAt: now,
                            updatedAt: now,
                            reminderAt: reminderDateTime?.millisecondsSinceEpoch,
                          )
                        : note.copyWith(
                            title: titleController.text.trim(),
                            content: contentController.text.trim(),
                            category: categoryValue,
                            updatedAt: now,
                            reminderAt: reminderDateTime?.millisecondsSinceEpoch,
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
                    if (updatedNote.reminderAt != null) {
                      NotificationService.instance.scheduleReminder(updatedNote);
                    } else if (note != null) {
                      NotificationService.instance.cancelReminder(note.id);
                    }
                    Navigator.pop(context);
                  },
                  child: Text(note == null ? _strings.addText : _strings.saveText),
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
        title: Text(_strings.deleteDialogTitle),
        content: Text('${_strings.deleteDialogContent} "${note.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_strings.cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_strings.deleteText),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _notes.removeWhere((item) => item.id == note.id);
      });
      await _saveNotes();
      await NotificationService.instance.cancelReminder(note.id);
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

  String _formatDateTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
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
          color: Theme.of(context).cardColor,
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
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final total = _notes.length;
    final pinned = _notes.where((note) => note.isPinned).length;
    final favorites = _notes.where((note) => note.isFavorite).length;
    final accent = widget.settings.accentColor;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent,
                      accent.withValues(alpha: 0.78),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _strings.appTitle,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _strings.subtitle,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () async {
                            final result = await Navigator.of(context).push<AppSettings>(
                              MaterialPageRoute(
                                builder: (context) => SettingsPage(
                                  settings: widget.settings,
                                  strings: _strings,
                                ),
                              ),
                            );

                            if (result != null) {
                              await widget.onSettingsChanged(result);
                              if (mounted) {
                                setState(() {});
                              }
                            }
                          },
                          icon: const Icon(Icons.tune_rounded, color: Colors.white),
                          tooltip: _strings.settingsTitle,
                        ),
                        const SizedBox(width: 8),
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
              if (widget.settings.showStats)
                Row(
                  children: [
                    _buildSummaryCard(
                      title: _strings.totalNotes,
                      value: total.toString(),
                      icon: Icons.notes_rounded,
                      color: const Color(0xFF5B7CFA),
                    ),
                    const SizedBox(width: 12),
                    _buildSummaryCard(
                      title: _strings.favoriteCount,
                      value: favorites.toString(),
                      icon: Icons.favorite_rounded,
                      color: const Color(0xFFEC5E76),
                    ),
                    const SizedBox(width: 12),
                    _buildSummaryCard(
                      title: _strings.pinnedCount,
                      value: pinned.toString(),
                      icon: Icons.push_pin_rounded,
                      color: const Color(0xFFF5B041),
                    ),
                  ],
                ),
              if (widget.settings.showStats) const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
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
                  textDirection: widget.settings.languageCode == 'ar'
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: _strings.searchHint,
                    border: InputBorder.none,
                    prefixIcon: const Icon(Icons.search_rounded),
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
                    final chipLabel = switch (option) {
                      'All' => _strings.filterAll,
                      'Pinned' => _strings.filterPinned,
                      'Favorites' => _strings.filterFavorites,
                      _ => option,
                    };

                    return ChoiceChip(
                      label: Text(chipLabel),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _selectedFilter = option;
                        });
                      },
                      selectedColor: accent,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: _filteredNotes.isEmpty
                    ? Center(
                        child: Text(
                          _strings.noResults,
                          style: const TextStyle(
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
                          final accentColor = _categoryColor(note.category);

                          return Card(
                            margin: EdgeInsets.zero,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: accentColor.withValues(alpha: 0.35),
                                  width: 1.2,
                                ),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(widget.settings.compactMode ? 12 : 18),
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
                                            color: accentColor.withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            note.category,
                                            style: TextStyle(
                                              color: accentColor,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        if (note.reminderAt != null)
                                          Container(
                                            margin: const EdgeInsets.only(right: 8),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF5B7CFA).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(9),
                                            ),
                                            child: Text(
                                              '${_strings.reminderLabel}: ${_formatDateTime(note.reminderAt!)}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        IconButton(
                                          onPressed: () => _togglePin(note),
                                          tooltip: note.isPinned ? _strings.unpin : _strings.pin,
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
                                          tooltip: note.isFavorite ? _strings.removeFavorite : _strings.addFavorite,
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
                                          tooltip: _strings.editText,
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                        IconButton(
                                          onPressed: () => _deleteNote(note),
                                          tooltip: _strings.deleteText,
                                          icon: const Icon(Icons.delete_outline_rounded),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      note.title,
                                      textDirection: widget.settings.languageCode == 'ar'
                                          ? TextDirection.rtl
                                          : TextDirection.ltr,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      note.content,
                                      textDirection: widget.settings.languageCode == 'ar'
                                          ? TextDirection.rtl
                                          : TextDirection.ltr,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        height: 1.65,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.access_time_rounded,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _formatDate(note.updatedAt),
                                          style: const TextStyle(
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
        label: Text(_strings.addNewNote),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.strings,
  });

  final AppSettings settings;
  final AppStrings strings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.strings.settingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.strings.appearanceTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _settings.themeModeName,
                    decoration: InputDecoration(
                      labelText: widget.strings.themeLabel,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'light', child: Text('Light')),
                      DropdownMenuItem(value: 'dark', child: Text('Dark')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _settings = _settings.copyWith(themeModeName: value);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _settings.languageCode,
                    decoration: InputDecoration(
                      labelText: widget.strings.languageLabel,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ar', child: Text('العربية')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _settings = _settings.copyWith(languageCode: value);
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.strings.accentColorTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: List.generate(AppSettings.accentColors.length, (index) {
                      final color = AppSettings.accentColors[index];
                      final selected = _settings.accentIndex == index;
                      return ChoiceChip(
                        label: const SizedBox(width: 16, height: 16),
                        selected: selected,
                        onSelected: (_) {
                          setState(() {
                            _settings = _settings.copyWith(accentIndex: index);
                          });
                        },
                        avatar: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        showCheckmark: false,
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.strings.behaviorTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _settings.sortModeName,
                    decoration: InputDecoration(
                      labelText: widget.strings.sortLabel,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('Newest first')),
                      DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
                      DropdownMenuItem(value: 'pinnedFirst', child: Text('Pinned first')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _settings = _settings.copyWith(sortModeName: value);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.strings.compactModeLabel),
                    value: _settings.compactMode,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(compactMode: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.strings.showStatsLabel),
                    value: _settings.showStats,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(showStats: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.strings.favoriteOnlyLabel),
                    value: _settings.showFavoritesOnly,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(showFavoritesOnly: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.strings.pinnedOnlyLabel),
                    value: _settings.showPinnedOnly,
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(showPinnedOnly: value);
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).pop(_settings);
        },
        icon: const Icon(Icons.save_rounded),
        label: Text(widget.strings.saveSettings),
      ),
    );
  }
}

class AppSettings {
  const AppSettings({
    this.themeModeName = 'light',
    this.languageCode = 'ar',
    this.accentIndex = 0,
    this.sortModeName = 'newest',
    this.compactMode = false,
    this.showStats = true,
    this.showFavoritesOnly = false,
    this.showPinnedOnly = false,
  });

  final String themeModeName;
  final String languageCode;
  final int accentIndex;
  final String sortModeName;
  final bool compactMode;
  final bool showStats;
  final bool showFavoritesOnly;
  final bool showPinnedOnly;

  static const List<Color> accentColors = [
    Color(0xFF5B7CFA),
    Color(0xFF6EC6A4),
    Color(0xFFF5B041),
    Color(0xFFEC5E76),
    Color(0xFF8D6BFF),
  ];

  Color get accentColor => accentColors[accentIndex.clamp(0, accentColors.length - 1)];

  ThemeMode get themeMode {
    switch (themeModeName) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  NoteSort get sortMode {
    switch (sortModeName) {
      case 'oldest':
        return NoteSort.oldest;
      case 'pinnedFirst':
        return NoteSort.pinnedFirst;
      case 'newest':
      default:
        return NoteSort.newest;
    }
  }

  AppSettings copyWith({
    String? themeModeName,
    String? languageCode,
    int? accentIndex,
    String? sortModeName,
    bool? compactMode,
    bool? showStats,
    bool? showFavoritesOnly,
    bool? showPinnedOnly,
  }) {
    return AppSettings(
      themeModeName: themeModeName ?? this.themeModeName,
      languageCode: languageCode ?? this.languageCode,
      accentIndex: accentIndex ?? this.accentIndex,
      sortModeName: sortModeName ?? this.sortModeName,
      compactMode: compactMode ?? this.compactMode,
      showStats: showStats ?? this.showStats,
      showFavoritesOnly: showFavoritesOnly ?? this.showFavoritesOnly,
      showPinnedOnly: showPinnedOnly ?? this.showPinnedOnly,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeModeName': themeModeName,
      'languageCode': languageCode,
      'accentIndex': accentIndex,
      'sortModeName': sortModeName,
      'compactMode': compactMode,
      'showStats': showStats,
      'showFavoritesOnly': showFavoritesOnly,
      'showPinnedOnly': showPinnedOnly,
    };
  }

  factory AppSettings.fromPreferences(SharedPreferences prefs) {
    final raw = prefs.getString('notes_app_settings');

    if (raw == null || raw.isEmpty) {
      return const AppSettings();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const AppSettings();
      }

      return AppSettings(
        themeModeName: decoded['themeModeName'] as String? ?? 'light',
        languageCode: decoded['languageCode'] as String? ?? 'ar',
        accentIndex: decoded['accentIndex'] as int? ?? 0,
        sortModeName: decoded['sortModeName'] as String? ?? 'newest',
        compactMode: decoded['compactMode'] as bool? ?? false,
        showStats: decoded['showStats'] as bool? ?? true,
        showFavoritesOnly: decoded['showFavoritesOnly'] as bool? ?? false,
        showPinnedOnly: decoded['showPinnedOnly'] as bool? ?? false,
      );
    } catch (_) {
      return const AppSettings();
    }
  }
}

class AppStrings {
  const AppStrings({
    required this.appTitle,
    required this.subtitle,
    required this.settingsTitle,
    required this.searchHint,
    required this.addNewNote,
    required this.totalNotes,
    required this.favoriteCount,
    required this.pinnedCount,
    required this.noResults,
    required this.filterAll,
    required this.filterPinned,
    required this.filterFavorites,
    required this.addNoteTitle,
    required this.editNoteTitle,
    required this.titleLabel,
    required this.contentLabel,
    required this.categoryLabel,
    required this.reminderLabel,
    required this.reminderSet,
    required this.addText,
    required this.saveText,
    required this.cancelText,
    required this.deleteText,
    required this.titleRequired,
    required this.contentRequired,
    required this.deleteDialogTitle,
    required this.deleteDialogContent,
    required this.pin,
    required this.unpin,
    required this.addFavorite,
    required this.removeFavorite,
    required this.editText,
    required this.appearanceTitle,
    required this.themeLabel,
    required this.languageLabel,
    required this.accentColorTitle,
    required this.behaviorTitle,
    required this.sortLabel,
    required this.compactModeLabel,
    required this.showStatsLabel,
    required this.favoriteOnlyLabel,
    required this.pinnedOnlyLabel,
    required this.saveSettings,
  });

  final String appTitle;
  final String subtitle;
  final String settingsTitle;
  final String searchHint;
  final String addNewNote;
  final String totalNotes;
  final String favoriteCount;
  final String pinnedCount;
  final String noResults;
  final String filterAll;
  final String filterPinned;
  final String filterFavorites;
  final String addNoteTitle;
  final String editNoteTitle;
  final String titleLabel;
  final String contentLabel;
  final String categoryLabel;
  final String reminderLabel;
  final String reminderSet;
  final String addText;
  final String saveText;
  final String cancelText;
  final String deleteText;
  final String titleRequired;
  final String contentRequired;
  final String deleteDialogTitle;
  final String deleteDialogContent;
  final String pin;
  final String unpin;
  final String addFavorite;
  final String removeFavorite;
  final String editText;
  final String appearanceTitle;
  final String themeLabel;
  final String languageLabel;
  final String accentColorTitle;
  final String behaviorTitle;
  final String sortLabel;
  final String compactModeLabel;
  final String showStatsLabel;
  final String favoriteOnlyLabel;
  final String pinnedOnlyLabel;
  final String saveSettings;

  static AppStrings forLanguage(String languageCode) {
    if (languageCode == 'en') {
      return const AppStrings(
        appTitle: 'My Notes',
        subtitle: 'Manage your day in a stylish and flexible way',
        settingsTitle: 'Settings',
        searchHint: 'Search notes...',
        addNewNote: 'New note',
        totalNotes: 'Notes',
        favoriteCount: 'Favorites',
        pinnedCount: 'Pinned',
        noResults: 'No notes match your search',
        filterAll: 'All',
        filterPinned: 'Pinned',
        filterFavorites: 'Favorites',
        addNoteTitle: 'Add new note',
        editNoteTitle: 'Edit note',
        titleLabel: 'Title',
        contentLabel: 'Content',
        categoryLabel: 'Category',
        reminderLabel: 'Reminder',
        reminderSet: 'Reminder set to',
        addText: 'Add',
        saveText: 'Save',
        cancelText: 'Cancel',
        deleteText: 'Delete',
        titleRequired: 'Please enter a title',
        contentRequired: 'Please enter note content',
        deleteDialogTitle: 'Delete note?',
        deleteDialogContent: 'Are you sure you want to delete',
        pin: 'Pin',
        unpin: 'Unpin',
        addFavorite: 'Add to favorites',
        removeFavorite: 'Remove from favorites',
        editText: 'Edit',
        appearanceTitle: 'Appearance',
        themeLabel: 'Theme',
        languageLabel: 'Language',
        accentColorTitle: 'Primary color',
        behaviorTitle: 'App behavior',
        sortLabel: 'Sort notes',
        compactModeLabel: 'Compact mode',
        showStatsLabel: 'Show statistics',
        favoriteOnlyLabel: 'Show favorites only',
        pinnedOnlyLabel: 'Show pinned only',
        saveSettings: 'Save settings',
      );
    }

    return const AppStrings(
      appTitle: 'ملاحظاتي',
      subtitle: 'إدارة يومك بشكل أنيق ومرن',
      settingsTitle: 'الإعدادات',
      searchHint: 'بحث في الملاحظات...',
      addNewNote: 'ملاحظة جديدة',
      totalNotes: 'الملاحظات',
      favoriteCount: 'المفضلة',
      pinnedCount: 'المثبتة',
      noResults: 'لا توجد ملاحظات مطابقة لبحثك',
      filterAll: 'الكل',
      filterPinned: 'المثبتة',
      filterFavorites: 'المفضلة',
      addNoteTitle: 'إضافة ملاحظة جديدة',
      editNoteTitle: 'تعديل الملاحظة',
      titleLabel: 'العنوان',
      contentLabel: 'المحتوى',
      categoryLabel: 'الفئة',
      reminderLabel: 'التنبيه',
      reminderSet: 'تم ضبط التنبيه على',
      addText: 'إضافة',
      saveText: 'حفظ',
      cancelText: 'إلغاء',
      deleteText: 'حذف',
      titleRequired: 'أدخل عنوانًا صحيحًا',
      contentRequired: 'أدخل محتوى الملاحظة',
      deleteDialogTitle: 'حذف الملاحظة؟',
      deleteDialogContent: 'هل أنت متأكد أنك تريد حذف',
      pin: 'تثبيت',
      unpin: 'إزالة التثبيت',
      addFavorite: 'إضافة للمفضلة',
      removeFavorite: 'إزالة المفضلة',
      editText: 'تعديل',
      appearanceTitle: 'المظهر',
      themeLabel: 'النمط',
      languageLabel: 'اللغة',
      accentColorTitle: 'اللون الأساسي',
      behaviorTitle: 'سلوك التطبيق',
      sortLabel: 'ترتيب الملاحظات',
      compactModeLabel: 'الوضع المضغوط',
      showStatsLabel: 'إظهار الإحصائيات',
      favoriteOnlyLabel: 'عرض المفضلة فقط',
      pinnedOnlyLabel: 'عرض المثبتة فقط',
      saveSettings: 'حفظ الإعدادات',
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
  final int? reminderAt;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.isPinned,
    required this.isFavorite,
    required this.createdAt,
    required this.updatedAt,
    this.reminderAt,
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
    int? reminderAt,
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
      reminderAt: reminderAt ?? this.reminderAt,
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
      'reminderAt': reminderAt,
    };
  }

  factory Note.fromJson(Map<String, dynamic> map) {
    return Note(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      category: map['category'] ?? 'Work',
      isPinned: map['isPinned'] ?? false,
      isFavorite: map['isFavorite'] ?? false,
      createdAt: map['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: map['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      reminderAt: map['reminderAt'] as int?,
    );
  }
}

enum NoteSort {
  newest,
  oldest,
  pinnedFirst,
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(settings: initializationSettings);

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> scheduleReminder(Note note) async {
    if (note.reminderAt == null) return;

    final reminderTime = DateTime.fromMillisecondsSinceEpoch(note.reminderAt!);
    final now = DateTime.now();

    if (reminderTime.isBefore(now)) {
      await cancelReminder(note.id);
      return;
    }

    await _notifications.cancel(id: note.id.hashCode);

    await _notifications.zonedSchedule(
      id: note.id.hashCode,
      title: note.title,
      body: note.content,
      scheduledDate: tz.TZDateTime.from(reminderTime, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'notes_app_reminders',
          'Notes reminders',
          channelDescription: 'Scheduled reminder notifications for notes',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode(note.toJson()),
    );
  }

  Future<void> cancelReminder(String noteId) async {
    await _notifications.cancel(id: noteId.hashCode);
  }
}
