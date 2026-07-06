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
  int _indice = 0;
  Uint8List? _miniatura;
  bool _cargandoMini = false;

  final List<AssetEntity> _paraBorrar = [];
  final List<AssetEntity> _favoritos = [];
  int _guardadas = 0;

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

    setState(() {
      _cargando = false;
      _fotos = lista;
      _indice = 0;
    });

    await _cargarMiniatura();
  }

  Future<void> _cargarMiniatura() async {
    if (_indice >= _fotos.length) {
      setState(() {
        _miniatura = null;
      });
      return;
    }
    setState(() {
      _cargandoMini = true;
    });
    final mini = await _fotos[_indice].thumbnailDataWithSize(
      const ThumbnailSize(600, 600),
    );
    if (!mounted) return;
    setState(() {
      _miniatura = mini;
      _cargandoMini = false;
    });
  }

  void _accion(String tipo) {
    if (_indice >= _fotos.length) return;
    final actual = _fotos[_indice];
    if (tipo == 'borrar') {
      _paraBorrar.add(actual);
    } else if (tipo == 'guardar') {
      _guardadas++;
    } else if (tipo == 'favorito') {
      _favoritos.add(actual);
    }
    setState(() {
      _indice++;
      _miniatura = null;
    });
    _cargarMiniatura();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Slider')),
      body: SafeArea(child: _construirCuerpo()),
    );
  }

  Widget _construirCuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sinPermiso) {
      return Center(
        child: Padding(
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
        ),
      );
    }
    if (_fotos.isEmpty) {
      return const Center(child: Text('No se encontraron fotos ni videos.'));
    }
    if (_indice >= _fotos.length) {
      return _construirResumen();
    }
    return _construirRevisor();
  }

  Widget _construirRevisor() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Archivo ${_indice + 1} de ${_fotos.length}',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < 0) {
                _accion('borrar');
              } else if (v > 0) {
                _accion('guardar');
              }
            },
            onVerticalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < 0) {
                _accion('favorito');
              }
            },
            child: Container(
              width: double.infinity,
              color: Colors.black12,
              alignment: Alignment.center,
              child: _cargandoMini || _miniatura == null
                  ? const CircularProgressIndicator()
                  : Image.memory(_miniatura!, fit: BoxFit.contain),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            children: [
              const Text(
                '←  Borrar          Guardar  →',
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                '↑  Favorito',
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 12),
              Text(
                'Para borrar: ${_paraBorrar.length}   ·   '
                'Guardadas: $_guardadas   ·   '
                'Favoritos: ${_favoritos.length}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _construirResumen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '¡Revisaste todos los archivos!',
              style: TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text('Marcadas para borrar: ${_paraBorrar.length}'),
            Text('Guardadas: $_guardadas'),
            Text('Favoritos: ${_favoritos.length}'),
          ],
        ),
      ),
    );
  }
}
