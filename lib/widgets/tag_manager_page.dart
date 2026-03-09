import 'package:flutter/material.dart';
import '../models/tag.dart';
import '../repositories/expense_repository.dart';

class TagManagerPage extends StatefulWidget {
  const TagManagerPage({super.key});

  @override
  State<TagManagerPage> createState() => _TagManagerPageState();
}

class _TagManagerPageState extends State<TagManagerPage> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  TagType _selectedType = TagType.expense;
  List<Tag> _tags = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tags = await ExpenseRepository.getAllTags();
      setState(() {
        _tags = tags;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load tags: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _addTag() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();

    // Check for duplicates
    if (_tags.any((t) => t.name.toLowerCase() == name.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tag with this name already exists')),
      );
      return;
    }

    try {
      final tag = Tag(name: name, type: _selectedType);
      await ExpenseRepository.insertTag(tag);

      _nameController.clear();
      setState(() => _selectedType = TagType.expense);

      await _loadTags();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tag created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create tag: $e')),
        );
      }
    }
  }

  Future<void> _editTag(Tag tag) async {
    final nameController = TextEditingController(text: tag.name);
    final formKey = GlobalKey<FormState>();
    var selectedType = tag.type;

    final updatedTag = await showDialog<Tag>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Tag'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tag Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'Please enter a name';
                    }
                    if (trimmed.length > 50) {
                      return 'Name too long (max 50 chars)';
                    }
                    final duplicateExists = _tags.any(
                      (existingTag) =>
                          existingTag.id != tag.id &&
                          existingTag.name.toLowerCase() == trimmed.toLowerCase(),
                    );
                    if (duplicateExists) {
                      return 'Tag with this name already exists';
                    }
                    return null;
                  },
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                SegmentedButton<TagType>(
                  segments: const [
                    ButtonSegment(
                      value: TagType.expense,
                      label: Text('Expense'),
                      icon: Icon(Icons.arrow_downward, color: Colors.red),
                    ),
                    ButtonSegment(
                      value: TagType.income,
                      label: Text('Income'),
                      icon: Icon(Icons.arrow_upward, color: Colors.green),
                    ),
                  ],
                  selected: {selectedType},
                  onSelectionChanged: (selection) {
                    setDialogState(() => selectedType = selection.first);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) {
                  return;
                }

                Navigator.of(context).pop(
                  Tag(
                    id: tag.id,
                    name: nameController.text.trim(),
                    type: selectedType,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();

    if (updatedTag == null) {
      return;
    }

    try {
      await ExpenseRepository.updateTag(updatedTag);
      await _loadTags();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tag updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update tag: $e')),
        );
      }
    }
  }

  Future<void> _deleteTag(Tag tag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tag'),
        content: Text('Are you sure you want to delete "${tag.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ExpenseRepository.deleteTag(tag.id!);
      await _loadTags();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tag deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot delete tag: It may be in use by existing entries'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Tags'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTags,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: _loadTags,
              child: const Text('Retry'),
            ),
          ],
        ),
      )
          : Column(
        children: [
          // Add Tag Form
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Tag Name',
                        border: OutlineInputBorder(),
                        hintText: 'e.g., Food, Salary, Transport',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a name';
                        }
                        if (value.length > 50) {
                          return 'Name too long (max 50 chars)';
                        }
                        return null;
                      },
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<TagType>(
                      segments: const [
                        ButtonSegment(
                          value: TagType.expense,
                          label: Text('Expense'),
                          icon: Icon(Icons.arrow_downward, color: Colors.red),
                        ),
                        ButtonSegment(
                          value: TagType.income,
                          label: Text('Income'),
                          icon: Icon(Icons.arrow_upward, color: Colors.green),
                        ),
                      ],
                      selected: {_selectedType},
                      onSelectionChanged: (set) {
                        setState(() => _selectedType = set.first);
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addTag,
                        icon: const Icon(Icons.add),
                        label: const Text('Create Tag'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Tag List
          Expanded(
            child: _tags.isEmpty
                ? const Center(
              child: Text(
                'No tags yet.\nCreate your first tag above!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
                : ListView.builder(
              itemCount: _tags.length,
              itemBuilder: (context, index) {
                final tag = _tags[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: tag.type.color.withValues(alpha: 0.1),
                    child: Icon(
                      tag.type.icon,
                      color: tag.type.color,
                      size: 20,
                    ),
                  ),
                  title: Text(tag.name),
                  subtitle: Text(
                    tag.type.name.toUpperCase(),
                    style: TextStyle(
                      color: tag.type.color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () => _editTag(tag),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit Tag',
                        onPressed: () => _editTag(tag),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'Delete Tag',
                        onPressed: () => _deleteTag(tag),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
