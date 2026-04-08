/// Project selector — title bar dropdown for switching projects.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_message.dart';
import '../../models/project.dart';
import '../../providers/agent_provider.dart';
import '../../providers/project_provider.dart';

class ProjectSelector extends ConsumerStatefulWidget {
  const ProjectSelector({super.key});

  @override
  ConsumerState<ProjectSelector> createState() => _ProjectSelectorState();
}

class _ProjectSelectorState extends ConsumerState<ProjectSelector> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  bool _isSwitching = false;

  void _toggle() {
    if (_overlay != null) {
      _close();
    } else {
      _open();
    }
  }

  void _close() {
    _overlay?.remove();
    _overlay = null;
  }

  void _open() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject()! as RenderBox;
    final size = renderBox.size;

    _overlay = OverlayEntry(
      builder: (context) => _ProjectPopover(
        link: _layerLink,
        anchorWidth: size.width,
        onClose: _close,
        onSelectProject: _switchTo,
        onPickFolder: _pickFolder,
        onRename: _rename,
      ),
    );
    overlay.insert(_overlay!);
  }

  Future<void> _switchTo(Project project) async {
    _close();
    setState(() => _isSwitching = true);
    try {
      await ref.read(projectProvider.notifier).switchProject(project.path);
    } finally {
      if (mounted) setState(() => _isSwitching = false);
    }
  }

  Future<void> _pickFolder() async {
    _close();
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Обрати проєкт',
    );
    if (result == null) return;
    setState(() => _isSwitching = true);
    try {
      await ref.read(projectProvider.notifier).switchProject(result);
    } finally {
      if (mounted) setState(() => _isSwitching = false);
    }
  }

  Future<void> _rename(String newName) async {
    await ref.read(projectProvider.notifier).renameProject(newName);
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider);
    final hasActiveAgents = ref.watch(agentsProvider).values.any(
      (a) => a.status != AgentStatus.idle,
    );
    final disabled = hasActiveAgents || _isSwitching;

    final displayName = project?.displayName ?? '...';
    final fullPath = project?.path;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: fullPath ?? '',
        child: GestureDetector(
          onTap: disabled ? null : _toggle,
          child: MouseRegion(
            cursor: disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 14,
                  color: Colors.white.withValues(alpha: disabled ? 0.2 : 0.4),
                ),
                const SizedBox(width: 6),
                if (_isSwitching)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  )
                else
                  Text(
                    displayName,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: disabled ? 0.3 : 0.5),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more,
                  size: 14,
                  color: Colors.white.withValues(alpha: disabled ? 0.1 : 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Popover ─────────────────────────────────────────────────────────────────

class _ProjectPopover extends ConsumerStatefulWidget {
  final LayerLink link;
  final double anchorWidth;
  final VoidCallback onClose;
  final ValueChanged<Project> onSelectProject;
  final VoidCallback onPickFolder;
  final ValueChanged<String> onRename;

  const _ProjectPopover({
    required this.link,
    required this.anchorWidth,
    required this.onClose,
    required this.onSelectProject,
    required this.onPickFolder,
    required this.onRename,
  });

  @override
  ConsumerState<_ProjectPopover> createState() => _ProjectPopoverState();
}

class _ProjectPopoverState extends ConsumerState<_ProjectPopover> {
  bool _isEditing = false;
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _startEditing(String currentName) {
    _nameCtrl.text = currentName;
    setState(() => _isEditing = true);
  }

  void _saveEdit() {
    final name = _nameCtrl.text.trim();
    if (name.isNotEmpty) {
      widget.onRename(name);
    }
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider);
    final recentProjects = ref.watch(recentProjectsProvider);

    return Stack(
      children: [
        // Dismiss barrier
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        // Popover
        CompositedTransformFollower(
          link: widget.link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 8),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 320,
              constraints: const BoxConstraints(maxHeight: 400),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Current project header
                  _buildCurrentProject(project),
                  _divider(),
                  // Recent projects
                  _buildRecentSection(project, recentProjects),
                  _divider(),
                  // Open folder button
                  _buildOpenFolder(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentProject(Project? project) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.folder,
                size: 16,
                color: Color(0xFF00C0D1),
              ),
              const SizedBox(width: 8),
              if (_isEditing)
                Expanded(
                  child: SizedBox(
                    height: 24,
                    child: TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _saveEdit(),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    project?.displayName ?? '...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (!_isEditing)
                GestureDetector(
                  onTap: () => _startEditing(project?.displayName ?? ''),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              if (_isEditing)
                GestureDetector(
                  onTap: _saveEdit,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(
                      Icons.check,
                      size: 14,
                      color: const Color(0xFF00C0D1).withValues(alpha: 0.8),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            project?.path ?? '',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSection(Project? current, List<Project> recent) {
    final others = recent.where((p) => p.path != current?.path).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Останні проєкти',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          if (others.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Поки немає інших проєктів',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 12,
                ),
              ),
            )
          else
            ...others.take(8).map((project) => _buildRecentItem(project)),
        ],
      ),
    );
  }

  Widget _buildRecentItem(Project project) {
    return GestureDetector(
      onTap: () => widget.onSelectProject(project),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 14,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.displayName,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      project.path,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpenFolder() {
    return GestureDetector(
      onTap: widget.onPickFolder,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.folder_open,
                size: 16,
                color: const Color(0xFF00C0D1).withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                'Відкрити папку...',
                style: TextStyle(
                  color: const Color(0xFF00C0D1).withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      height: 1,
      color: Colors.white.withValues(alpha: 0.06),
    );
  }
}
