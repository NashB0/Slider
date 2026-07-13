import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _kBorrar = 'slider_para_borrar';
  static const _kGuardadas = 'slider_guardadas';
  static const _kFavoritos = 'slider_favoritos';

  CardSwiperController _controlador = CardSwiperController();
  final Map<String, Uint8List> _cache = {};

  bool _cargando = true;
  bool _sinPermiso = false;
  bool _borrando = false;

  List<AssetEntity> _pendientes = [];

  Set<String> _idsBorrar = {};
  Set<String> _idsGuardadas = {};
  Set<String> _idsFavoritos = {};

  int _revisadosSesion = 0;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    _idsBorrar = (prefs.getStringList(_kBorrar) ?? []).toSet();
    _idsGuardadas = (prefs.getStringList(_kGuardadas) ?? []).toSet();
    _idsFavoritos = (prefs.getStringList(_kFavoritos) ?? []).toSet();
    await _cargarFotos();
  }

  Future<void> _guardarEstado() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kBorrar, _idsBorrar.toList());
    await prefs.setStringList(_kGuardadas, _idsGuardadas.toList());
    await prefs.setStringList(_kFavoritos, _idsFavoritos.toList());
  }

  Future<void> _cargarFotos() async {
    setState(() => _cargando = true);

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
        _pendientes = [];
      });
      return;
    }

    final total = await albums[0].assetCountAsync;
    final todas = await albums[0].getAssetListRange(start: 0, end: total);

    final decididos = <String>{}
      ..addAll(_idsGuardadas)
      ..addAll(_idsFavoritos)
      ..addAll(_idsBorrar);

    final pendientes =
        todas.where((a) => !decididos.contains(a.id)).toList();

    if (!mounted) return;
    setState(() {
      _cargando = false;
      _pendientes = pendientes;
      _controlador = CardSwiperController();
    });
  }

  Future<Uint8List?> _mini(AssetEntity asset) async {
    if (_cache.containsKey(asset.id)) return _cache[asset.id];
    final datos =
        await asset.thumbnailDataWithSize(const ThumbnailSize(800, 800));
    if (datos != null) _cache[asset.id] = datos;
    return datos;
  }

  bool _alDeslizar(int anterior, int? actual, CardSwiperDirection dir) {
    final asset = _pendientes[anterior];
    setState(() {
      _revisadosSesion++;
      if (dir == CardSwiperDirection.left) {
        _idsBorrar.add(asset.id);
      } else if (dir == CardSwiperDirection.right) {
        _idsGuardadas.add(asset.id);
      } else if (dir == CardSwiperDirection.top) {
        _idsFavoritos.add(asset.id);
      }
    });
    _guardarEstado();
    return true;
  }

  Future<void> _borrarMarcadas() async {
    if (_idsBorrar.isEmpty) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar archivos'),
        content: Text(
          'Vas a borrar ${_idsBorrar.length} archivo(s) de tu teléfono.\n\n'
          'Android te va a pedir una confirmación final.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _borrando = true);

    final borrados =
        await PhotoManager.editor.deleteWithIds(_idsBorrar.toList());

    _idsBorrar.removeAll(borrados);
    await _guardarEstado();

    if (!mounted) return;
    setState(() => _borrando = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          borrados.isEmpty
              ? 'No se borró ningún archivo.'
              : 'Se borraron ${borrados.length} archivo(s).',
        ),
      ),
    );

    await _cargarFotos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Slider'),
        backgroundColor: Colors.transparent,
        actions: [
          if (_idsBorrar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _borrando ? null : _borrarMarcadas,
                icon: const Icon(Icons.delete_forever,
                    color: Colors.redAccent),
                label: Text(
                  '${_idsBorrar.length}',
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 16),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(child: _cuerpo()),
    );
  }

  Widget _cuerpo() {
    if (_cargando || _borrando) {
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
    if (_pendientes.isEmpty) {
      return _sinPendientes();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '${_pendientes.length} pendientes  ·  '
            '$_revisadosSesion revisados hoy',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          child: CardSwiper(
            controller: _controlador,
            cardsCount: _pendientes.length,
            numberOfCardsDisplayed:
                _pendientes.length >= 3 ? 3 : _pendientes.length,
            isLoop: false,
            backCardOffset: const Offset(0, 32),
            padding: const EdgeInsets.all(20),
            allowedSwipeDirection: const AllowedSwipeDirection.only(
              left: true,
              right: true,
              up: true,
            ),
            onSwipe: _alDeslizar,
            cardBuilder: (context, index, dx, dy) => _tarjeta(index, dx, dy),
          ),
        ),
        _panelInferior(),
      ],
    );
  }

  Widget _sinPendientes() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                color: Colors.greenAccent, size: 64),
            const SizedBox(height: 16),
            const Text('No hay archivos pendientes',
                style: TextStyle(fontSize: 20), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Text('Marcados para borrar: ${_idsBorrar.length}'),
            Text('Guardados: ${_idsGuardadas.length}'),
            Text('Favoritos: ${_idsFavoritos.length}'),
            const SizedBox(height: 24),
            if (_idsBorrar.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _borrarMarcadas,
                icon: const Icon(Icons.delete_forever),
                label: Text('Borrar ${_idsBorrar.length} archivo(s)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tarjeta(int index, int dx, int dy) {
    final asset = _pendientes[index];
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFF1B1F2A)),
          FutureBuilder<Uint8List?>(
            future: _mini(asset),
            builder: (context, snap) {
              if (snap.data == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return Image.memory(snap.data!, fit: BoxFit.cover);
            },
          ),
          if (asset.type == AssetType.video)
            const Positioned(
              top: 16,
              right: 16,
              child:
                  Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
            ),
          if (dx < -10)
            _etiqueta('BORRAR', Colors.redAccent, Alignment.topRight),
          if (dx > 10)
            _etiqueta('GUARDAR', Colors.greenAccent, Alignment.topLeft),
          if (dy < -10)
            _etiqueta('FAVORITO', Colors.amber, Alignment.bottomCenter),
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
            'Para borrar: ${_idsBorrar.length}   ·   '
            'Guardadas: ${_idsGuardadas.length}   ·   '
            'Favoritos: ${_idsFavoritos.length}',
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
}
