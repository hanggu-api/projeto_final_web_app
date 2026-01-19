import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../features/shared/camera_modal.dart';
// import 'camera_capture_modal.dart';

class ImageMediaWidget extends StatefulWidget {
  final int imageCount;
  final void Function(List<XFile>) onImagesSelected;

  const ImageMediaWidget({
    super.key,
    required this.imageCount,
    required this.onImagesSelected,
  });

  @override
  State<ImageMediaWidget> createState() => _ImageMediaWidgetState();
}

class _ImageMediaWidgetState extends State<ImageMediaWidget> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _showSourceSelector() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Adicionar Fotos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Tirar Foto'),
                onTap: () {
                  Navigator.pop(context);
                  // _pickFromSource(ImageSource.camera);
                  _openCameraModal();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Escolher da Galeria'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromSource(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openCameraModal() async {
    try {
      final result = await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height - 20,
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: const CameraModal(onlyPhoto: true),
          ),
        ),
      );

      if (result != null && result is Map) {
        final file = result['file'] as XFile?;
        if (file != null) {
          widget.onImagesSelected([file]);
        }
      }
    } catch (e) {
      debugPrint('Erro ao abrir câmera: $e');
    }
  }

  Future<void> _pickFromSource(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final XFile? image = await _picker.pickImage(source: source);
        if (image != null) {
          widget.onImagesSelected([image]);
        }
      } else {
        final List<XFile> images = await _picker.pickMultiImage();
        if (images.isNotEmpty) {
          widget.onImagesSelected(images);
        }
      }
    } catch (e) {
      debugPrint('Erro ao selecionar fotos: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showSourceSelector,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.imageCount > 0 ? Icons.check : Icons.image,
                    color: Colors.green,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.imageCount > 0
                            ? '${widget.imageCount} Foto(s) selecionada(s)'
                            : 'Adicionar Fotos',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.imageCount > 0
                            ? 'Toque para adicionar mais'
                            : 'Mostre o problema em fotos',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                    ],
                  ),
                ),
                if (widget.imageCount > 0)
                  const Icon(Icons.add_a_photo, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
