import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  runApp(const SliderApp());
}

class SliderApp extends StatelessWidget {
  const SliderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slider',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF11131A),
        useMaterial3: true,
      ),
      home: const PantallaFotos(),
    );
  }
}

class PantallaFotos extends StatefulWidget {
  const PantallaFotos({super.key});

  @override
  State<PantallaFotos> createState() => _PantallaFotosState();
}

class _PantallaFotosState extends State<PantallaFotos> {
  final CardSwiperController _controlador = CardSwiperController();
  final Map<int, Uint8List> _cache = {};

  bool _cargando = true;
  bool _sinPermiso = false;
  bool _termino = false;
  List<AssetEntity> _fotos = [];

  final List<AssetEntity> _paraBorrar = [];
  final List<AssetEntity> _favoritos = [];
  int _guardadas = 0;
  int _revisados = 0;

  @override
  void initState() {
    super.initState();
    _cargarFotos();
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
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
    final lista = await albums[0].getAssetListRange(start: 0, end: total);

    if (!mounted) return;
    setState(() {
      _cargando = false;
      _fotos = lista;
    });
  }

  Future<Uint8List?> _mini(int index) async {
    if (_cache.containsKey(index)) return _cache[index];
    final datos = await _fotos[index].thumbnailDataWithSize(
      const ThumbnailSize(800, 800),
    );
    if (datos != null) _cache[index] = datos;
    return datos;
  }

  bool _alDeslizar(int anterior, int? actual, CardSwiperDirection dir) {
    final asset = _fotos[anterior];
    setState(() {
      _revisados++;
      if (dir == CardSwiperDirection.left) {
        _paraBorrar.add(asset);
      } else if (dir == CardSwiperDirection.right) {
        _guardadas++;
      } else if (dir == CardSwiperDirection.top) {
        _favoritos.add(asset);
      }
    });
    _cache.remove(anterior);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Slider'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(child: _cuerpo()),
    );
  }

  Widget _cuerpo() {
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
    if (_termino) {
      return _resumen();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '$_revisados de ${_fotos.length} revisados',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          child: CardSwiper(
            controller: _controlador,
            cardsCount: _fotos.length,
            numberOfCardsDisplayed: _fotos.length >= 3 ? 3 : _fotos.length,
            isLoop: false,
            backCardOffset: const Offset(0, 32),
            padding: const EdgeInsets.all(20),
            allowedSwipeDirection: const AllowedSwipeDirection.only(
              left: true,
              right: true,
              up: true,
            ),
            onSwipe: _alDeslizar,
            onEnd: () => setState(() => _termino = true),
            cardBuilder: (context, index, dx, dy) {
              return _tarjeta(index, dx, dy);
            },
          ),
        ),
        _panelInferior(),
      ],
    );
  }

  Widget _tarjeta(int index, int dx, int dy) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFF1B1F2A)),
          FutureBuilder<Uint8List?>(
            future: _mini(index),
            builder: (context, snap) {
              if (snap.data == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return Image.memory(snap.data!, fit: BoxFit.cover);
            },
          ),
          if (_fotos[index].type == AssetType.video)
            const Positioned(
              top: 16,
              right: 16,
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white, size: 40),
            ),
          if (dx < -10) _etiqueta('BORRAR', Colors.redAccent, Alignment.topRight),
          if (dx > 10) _etiqueta('GUARDAR', Colors.greenAccent, Alignment.topLeft),
          if (dy < -10) _etiqueta('FAVORITO', Colors.amber, Alignment.bottomCenter),
        ],
      ),
    );
  }

  Widget _etiqueta(String texto, Color color, Alignment alineacion) {
    return Align(
      alignment: alineacion,
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(10),
          color: Colors.black54,
        ),
        child: Text(
          texto,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  Widget _panelInferior() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _boton(Icons.delete_outline, Colors.redAccent,
                  () => _controlador.swipe(CardSwiperDirection.left)),
              _boton(Icons.star_outline, Colors.amber,
                  () => _controlador.swipe(CardSwiperDirection.top)),
              _boton(Icons.check, Colors.greenAccent,
                  () => _controlador.swipe(CardSwiperDirection.right)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Para borrar: ${_paraBorrar.length}   ·   '
            'Guardadas: $_guardadas   ·   '
            'Favoritos: ${_favoritos.length}',
            style: const TextStyle(fontSize: 13, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _boton(IconData icono, Color color, VoidCallback alTocar) {
    return GestureDetector(
      onTap: alTocar,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1B1F2A),
          border: Border.all(color: color, width: 2),
        ),
        child: Icon(icono, color: color, size: 30),
      ),
    );
  }

  Widget _resumen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                color: Colors.greenAccent, size: 64),
            const SizedBox(height: 16),
            const Text('¡Revisaste todos los archivos!',
                style: TextStyle(fontSize: 20), textAlign: TextAlign.center),
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
