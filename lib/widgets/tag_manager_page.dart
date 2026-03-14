import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../models/tag_group.dart';
import '../repositories/expense_repository.dart';

class TagManagerPage extends StatefulWidget {
  const TagManagerPage({super.key});

  @override
  State<TagManagerPage> createState() => _TagManagerPageState();
}

class _TagManagerPageState extends State<TagManagerPage> {
  final _tagNameController = TextEditingController();
  final _groupNameController = TextEditingController();
  final _tagFormKey = GlobalKey<FormState>();
  final _groupFormKey = GlobalKey<FormState>();

  TagType _selectedType = TagType.expense;
  List<Tag> _tags = [];
  List<TagGroup> _groups = [];
  final Set<int> _selectedGroupTagIds = <int>{};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _tagNameController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tags = await ExpenseRepository.getAllTags();
      final groups = await ExpenseRepository.getAllTagGroups();
      setState(() {
        _tags = tags;
        _groups = groups;
        _selectedGroupTagIds.removeWhere(
          (tagId) => !_tags.any((tag) => tag.id == tagId),
        );
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
    if (!_tagFormKey.currentState!.validate()) return;

    final name = _tagNameController.text.trim();
    final duplicateExists = _tags.any(
      (tag) => tag.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicateExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tag with this name already exists')),
      );
      return;
    }

    try {
      await ExpenseRepository.insertTag(Tag(name: name, type: _selectedType));
      _tagNameController.clear();
      setState(() => _selectedType = TagType.expense);
      await _loadData();

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

  Future<void> _addGroup() async {
    if (!_groupFormKey.currentState!.validate()) return;

    final name = _groupNameController.text.trim();
    final duplicateExists = _groups.any(
      (group) => group.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicateExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group with this name already exists')),
      );
      return;
    }

    try {
      final groupId = await ExpenseRepository.insertTagGroup(TagGroup(name: name));
      await ExpenseRepository.replaceGroupMembership(
        groupId,
        _selectedGroupTagIds.toList(),
      );

      _groupNameController.clear();
      setState(() => _selectedGroupTagIds.clear());
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
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
                    groupId: tag.groupId,
                    groupName: tag.groupName,
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
      await _loadData();
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

  Future<void> _editGroup(TagGroup group) async {
    final nameController = TextEditingController(text: group.name);
    final formKey = GlobalKey<FormState>();
    final selectedIds = _tags
        .where((tag) => tag.groupId == group.id && tag.id != null)
        .map((tag) => tag.id!)
        .toSet();

    final result = await showDialog<(String, Set<int>)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Group'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Group Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) {
                          return 'Please enter a group name';
                        }
                        if (trimmed.length > 50) {
                          return 'Name too long (max 50 chars)';
                        }
                        final duplicateExists = _groups.any(
                          (existingGroup) =>
                              existingGroup.id != group.id &&
                              existingGroup.name.toLowerCase() == trimmed.toLowerCase(),
                        );
                        if (duplicateExists) {
                          return 'Group with this name already exists';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Tags in this group',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    ..._buildSelectableTagTiles(
                      selectedIds,
                      onToggle: (tagId) {
                        setDialogState(() {
                          if (selectedIds.contains(tagId)) {
                            selectedIds.remove(tagId);
                          } else {
                            selectedIds.add(tagId);
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
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
                Navigator.of(context).pop((nameController.text.trim(), selectedIds));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();

    if (result == null) {
      return;
    }

    try {
      await ExpenseRepository.updateTagGroup(
        TagGroup(id: group.id, name: result.$1),
      );
      await ExpenseRepository.replaceGroupMembership(group.id!, result.$2.toList());
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update group: $e')),
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
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tag deleted')),
        );
      }
    } catch (_) {
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

  Future<void> _deleteGroup(TagGroup group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text(
          'Delete "${group.name}"? Tags inside it will stay available but become ungrouped.',
        ),
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
      await ExpenseRepository.deleteTagGroup(group.id!);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete group: $e')),
        );
      }
    }
  }

  List<Widget> _buildSelectableTagTiles(
    Set<int> selectedIds, {
    required void Function(int tagId) onToggle,
  }) {
    final availableTags = _tags.where((tag) => tag.id != null).toList();
    if (availableTags.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Create tags first, then add them to a group.'),
        ),
      ];
    }

    return availableTags.map((tag) {
      final tagId = tag.id!;
      final isSelected = selectedIds.contains(tagId);
      return CheckboxListTile(
        value: isSelected,
        contentPadding: EdgeInsets.zero,
        title: Text(tag.name),
        subtitle: Text(tag.groupName == null ? tag.type.name.toUpperCase() : '${tag.type.name.toUpperCase()} - ${tag.groupName}'),
        secondary: Icon(tag.type.icon, color: tag.type.color),
        onChanged: (_) => onToggle(tagId),
      );
    }).toList();
  }

  List<Tag> _tagsForGroup(int groupId) {
    return _tags.where((tag) => tag.groupId == groupId).toList();
  }

  List<Tag> get _ungroupedTags {
    return _tags.where((tag) => tag.groupId == null).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Tags'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
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
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _tagFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create Tag',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _tagNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Tag Name',
                                  border: OutlineInputBorder(),
                                  hintText: 'e.g., Food, Salary, Transport',
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter a name';
                                  }
                                  if (value.trim().length > 50) {
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
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _groupFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create Group',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _groupNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Group Name',
                                  border: OutlineInputBorder(),
                                  hintText: 'e.g., Household, Work, Personal',
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter a group name';
                                  }
                                  if (value.trim().length > 50) {
                                    return 'Name too long (max 50 chars)';
                                  }
                                  return null;
                                },
                                textCapitalization: TextCapitalization.words,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Add existing tags to this group',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              ..._buildSelectableTagTiles(
                                _selectedGroupTagIds,
                                onToggle: (tagId) {
                                  setState(() {
                                    if (_selectedGroupTagIds.contains(tagId)) {
                                      _selectedGroupTagIds.remove(tagId);
                                    } else {
                                      _selectedGroupTagIds.add(tagId);
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _addGroup,
                                  icon: const Icon(Icons.create_new_folder_outlined),
                                  label: const Text('Create Group'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Groups',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (_groups.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No groups yet. Create one to organize existing tags.'),
                        ),
                      )
                    else
                      ..._groups.map((group) {
                        final groupTags = _tagsForGroup(group.id!);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ExpansionTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.folder_open),
                            ),
                            title: Text(group.name),
                            subtitle: Text(
                              groupTags.isEmpty
                                  ? 'No tags assigned yet'
                                  : '${groupTags.length} tag${groupTags.length == 1 ? '' : 's'}',
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _editGroup(group),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Edit'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _deleteGroup(group),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Delete'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              if (groupTags.isEmpty)
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('No tags inside this group.'),
                                )
                              else
                                ...groupTags.map(
                                  (tag) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor: tag.type.color.withValues(alpha: 0.1),
                                      child: Icon(tag.type.icon, color: tag.type.color, size: 20),
                                    ),
                                    title: Text(tag.name),
                                    subtitle: Text(tag.type.name.toUpperCase()),
                                    trailing: Wrap(
                                      spacing: 4,
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
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                    Text(
                      'Ungrouped Tags',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: _ungroupedTags.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('All tags are already inside groups.'),
                            )
                          : Column(
                              children: _ungroupedTags.map((tag) {
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: tag.type.color.withValues(alpha: 0.1),
                                    child: Icon(tag.type.icon, color: tag.type.color, size: 20),
                                  ),
                                  title: Text(tag.name),
                                  subtitle: Text(tag.type.name.toUpperCase()),
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
                              }).toList(),
                            ),
                    ),
                  ],
                ),
    );
  }
}
