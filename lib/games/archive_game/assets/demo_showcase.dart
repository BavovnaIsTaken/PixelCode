import 'package:flutter/material.dart';
import 'index.dart';

/// Демонстраційний компонент для показу всіх асетів гри
class ArchiveGameAssetsShowcase extends StatefulWidget {
  const ArchiveGameAssetsShowcase({super.key});

  @override
  State<ArchiveGameAssetsShowcase> createState() =>
      _ArchiveGameAssetsShowcaseState();
}

class _ArchiveGameAssetsShowcaseState extends State<ArchiveGameAssetsShowcase> {
  int selectedLevel = 1;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Асети гри про архівацію'),
          backgroundColor: ArchiveGameColors.primaryBlue,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Файли'),
              Tab(text: 'Контейнери'),
              Tab(text: 'Кнопки'),
              Tab(text: 'Анімації'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildFilesTab(),
            _buildContainersTab(),
            _buildButtonsTab(),
            _buildAnimationsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Іконки файлів',
            style: ArchiveGameTextStyles.heading,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: FileType.values.map((type) {
              return Column(
                children: [
                  CustomPaint(
                    painter: FileIconPainter(
                      fileType: type,
                      isSelected: false,
                    ),
                    size: const Size(64, 80),
                  ),
                  const SizedBox(height: 8),
                  Text(type.toString().split('.').last),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          const Text(
            'Вибрані іконки',
            style: ArchiveGameTextStyles.heading,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: FileType.values.map((type) {
              return Column(
                children: [
                  CustomPaint(
                    painter: FileIconPainter(
                      fileType: type,
                      isSelected: true,
                    ),
                    size: const Size(64, 80),
                  ),
                  const SizedBox(height: 8),
                  Text('${type.toString().split('.').last} (вибран)'),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildContainersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Папка',
            style: ArchiveGameTextStyles.heading,
          ),
          const SizedBox(height: 16),
          Row(
            spacing: 24,
            children: [
              Column(
                children: [
                  CustomPaint(
                    painter: FolderPainter(isOpen: false),
                    size: const Size(64, 64),
                  ),
                  const SizedBox(height: 8),
                  const Text('Закрита'),
                ],
              ),
              Column(
                children: [
                  CustomPaint(
                    painter: FolderPainter(isOpen: true),
                    size: const Size(64, 64),
                  ),
                  const SizedBox(height: 8),
                  const Text('Відкрита'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Архів (ZIP)',
            style: ArchiveGameTextStyles.heading,
          ),
          const SizedBox(height: 16),
          CustomPaint(
            painter: ArchivePainter(compressionLevel: 0.7),
            size: const Size(64, 80),
          ),
          const SizedBox(height: 32),
          const Text(
            'Контейнер',
            style: ArchiveGameTextStyles.heading,
          ),
          const SizedBox(height: 16),
          Row(
            spacing: 24,
            children: [
              Column(
                children: [
                  CustomPaint(
                    painter: ContainerPainter(isEmpty: true),
                    size: const Size(64, 64),
                  ),
                  const SizedBox(height: 8),
                  const Text('Порожній'),
                ],
              ),
              Column(
                children: [
                  CustomPaint(
                    painter: ContainerPainter(
                      isEmpty: false,
                      fileCount: 3,
                    ),
                    size: const Size(64, 64),
                  ),
                  const SizedBox(height: 8),
                  const Text('З файлами'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildButtonsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Кнопки гри',
            style: ArchiveGameTextStyles.heading,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              ArchiveGameButton(
                label: 'Архівувати',
                buttonType: GameButtonType.archive,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Архівування!')),
                  );
                },
              ),
              ArchiveGameButton(
                label: 'Розпакувати',
                buttonType: GameButtonType.extract,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Розпакування!')),
                  );
                },
              ),
              ArchiveGameButton(
                label: 'Далі',
                buttonType: GameButtonType.next,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('До наступного рівня!')),
                  );
                },
              ),
              ArchiveGameButton(
                label: 'Повернути',
                buttonType: GameButtonType.reset,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Повернення!')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Вимкнені кнопки',
            style: ArchiveGameTextStyles.heading,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              ArchiveGameButton(
                label: 'Архівувати',
                buttonType: GameButtonType.archive,
                isDisabled: true,
              ),
              ArchiveGameButton(
                label: 'Далі',
                buttonType: GameButtonType.next,
                isDisabled: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimationsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Фони рівнів',
            style: ArchiveGameTextStyles.heading,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: LevelBackground(
              levelNumber: selectedLevel,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Center(
                  child: Text(
                    'Рівень $selectedLevel',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          blurRadius: 2,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            spacing: 8,
            children: [
              for (int i = 1; i <= 3; i++)
                ElevatedButton(
                  onPressed: () => setState(() => selectedLevel = i),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedLevel == i
                        ? ArchiveGameColors.accentYellow
                        : Colors.grey,
                  ),
                  child: Text('Рівень $i'),
                ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Анімація файла в архів',
            style: ArchiveGameTextStyles.heading,
          ),
          const SizedBox(height: 16),
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1),
              color: Colors.white,
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  right: 20,
                  child: CustomPaint(
                    painter: ArchivePainter(),
                    size: const Size(60, 70),
                  ),
                ),
                FileToArchiveAnimation(
                  fileLabel: 'photo.png',
                  onComplete: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Файл архівовано!')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Анімація стискання',
            style: ArchiveGameTextStyles.heading,
          ),
          const SizedBox(height: 16),
          const CompressionAnimation(),
          const SizedBox(height: 32),
          const Text(
            'Анімація розпакування',
            style: ArchiveGameTextStyles.heading,
          ),
          const SizedBox(height: 16),
          Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1),
              color: Colors.white,
            ),
            child: const ExtractionAnimation(
              fileCount: 4,
              duration: Duration(seconds: 3),
            ),
          ),
        ],
      ),
    );
  }
}
