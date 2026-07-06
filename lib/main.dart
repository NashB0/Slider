import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  runApp(const SliderApp());
}

class SliderApp extends StatelessWidget {
  const SliderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Slider',
      home: PantallaFotos(),
    );
  }
}

class PantallaFotos extends StatefulWidget {
  const PantallaFotos({super.key});

  @override
  State<PantallaFotos> createState() => _PantallaFotosState();
}

class _PantallaFotosState extends State<PantallaFotos> {
  bool _cargando = true;
  bool _sinPermiso = false;
  List<AssetEntity> _fotos = [];
  Uint8List? _miniatura;

  @override
  void initState() {
    super.initState();
    _cargarFotos();
  }

  Future<void> _cargarFotos() async {
    final permiso = await PhotoManager.requestPermissionExtend();
    if (!permiso.isAuth) {
      setState(() {
        _cargando = false;
        _sinPermiso = true;
      });
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
    );

    if (albums.isEmpty) {
      setState(() {
        _cargando = false;
        _fotos = [];
      });
      return;
    }

    final total = await albums[0].assetCountAsync;
    final lista = await albums[0].getAssetListRange(
      start: 0,
      end: total,
    );

    Uint8List? mini;
    if (lista.isNotEmpty) {
      mini = await lista[0].thumbnailDataWithSize(
        const ThumbnailSize(600, 600),
      );
    }

    setState(() {
      _cargando = false;
      _fotos = lista;
      _miniatura = mini;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Slider')),
      body: Center(child: _construirCuerpo()),
    );
  }

  Widget _construirCuerpo() {
    if (_cargando) {
      return const CircularProgressIndicator();
    }
    if (_sinPermiso) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Slider necesita permiso para ver tus fotos.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => PhotoManager.openSetting(),
              child: const Text('Abrir ajustes'),
            ),
          ],
        ),
      );
    }
    if (_fotos.isEmpty) {
      return const Text('No se encontraron fotos ni videos.');
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Se encontraron ${_fotos.length} archivos'),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _miniatura == null
                ? const Text('No se pudo cargar la vista previa.')
                : Image.memory(_miniatura!, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }
}
