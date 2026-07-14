import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

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
      home: const PantallaPrincipal(),
    );
  }
}

enum Vista { revisar, paraBorrar, guardadas, favoritos }

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  static const _kBorrar = 'slider_para_borrar';
  static const _kGuardadas = 'slider_guardadas';
  static const _kFavoritos = 'slider_favoritos';

  static const int _ventana = 6;

  CardSwiperController _controlador = CardSwiperController();

  final Map<String, Uint8List> _imagenes = {};
  final Set<String> _pidiendo = {};

  bool _cargando = true;
  bool _sinPermiso = false;
  bool _ocupado = false;

  Vista _vista = Vista.revisar;

  List<AssetEntity> _todas = [];
  List<AssetEntity> _pendientes = [];

  Set<String> _idsBorrar = {};
  Set<String> _idsGuardadas = {};
  Set<String> _idsFavoritos = {};

  int _revisadosSesion = 0;
  int _indiceActual = 0;

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
        _todas = [];
        _pendientes = [];
      });
      return;
    }

    final total = await albums[0].assetCountAsync;
    final todas = await albums[0].getAssetListRange(start: 0, end: total);

    if (!mounted) return;
    setState(() {
      _cargando = false;
      _todas = todas;
      _pendientes = _calcularPendientes(todas);
      _controlador = CardSwiperController();
      _indiceActual = 0;
    });

    _precargar();
  }

  List<AssetEntity> _calcularPendientes(List<AssetEntity> todas) {
    final decididos = <String>{}
      ..addAll(_idsGuardadas)
      ..addAll(_idsFavoritos)
      ..addAll(_idsBorrar);
    return todas.where((a) => !decididos.contains(a.id)).toList();
  }

  void _recalcular() {
    setState(() {
      _pendientes = _calcularPendientes(_todas);
      _controlador = CardSwiperController();
      _indiceActual = 0;
    });
    _precargar();
  }

  // Precarga las próximas miniaturas y libera las que quedaron atrás.
  void _precargar() {
    final hasta = (_indiceActual + _ventana).clamp(0, _pendientes.length);
    for (var i = _indiceActual; i < hasta; i++) {
      final asset = _pendientes[i];
      if (_imagenes.containsKey(asset.id)) continue;
      if (_pidiendo.contains(asset.id)) continue;
      _pidiendo.add(asset.id);
      asset
          .thumbnailDataWithSize(const ThumbnailSize(800, 800))
          .then((datos) {
        _pidiendo.remove(asset.id);
        if (datos == null || !mounted) return;
        _imagenes[asset.id] = datos;
        setState(() {});
      });
    }

    // Liberar memoria de lo ya revisado
    final vigentes = <String>{};
    for (var i = _indiceActual; i < hasta; i++) {
      vigentes.add(_pendientes[i].id);
    }
    _imagenes.removeWhere((id, _) => !vigentes.contains(id));
  }

  List<AssetEntity> _listaDe(Vista v) {
    late Set<String> ids;
    if (v == Vista.paraBorrar) {
      ids = _idsBorrar;
    } else if (v == Vista.guardadas) {
      ids = _idsGuardadas;
    } else {
      ids = _idsFavoritos;
    }
    return _todas.where((a) => ids.contains(a.id)).toList();
  }

  bool _alDeslizar(int anterior, int? actual, CardSwiperDirection dir) {
    final asset = _pendientes[anterior];
    setState(() {
      _revisadosSesion++;
      _indiceActual = actual ?? anterior + 1;
      if (dir == CardSwiperDirection.left) {
        _idsBorrar.add(asset.id);
      } else if (dir == CardSwiperDirection.right) {
        _idsGuardadas.add(asset.id);
      } else if (dir == CardSwiperDirection.top) {
        _idsFavoritos.add(asset.id);
      }
    });
    _guardarEstado();
    _precargar();
    return true;
  }

  Future<void> _quitarDeLista(AssetEntity asset, Vista v) async {
    final nombre = v == Vista.paraBorrar
        ? 'Para borrar'
        : v == Vista.guardadas
            ? 'Guardadas'
            : 'Favoritos';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deshacer'),
        content: Text(
          'Sacar este archivo de "$nombre".\n\n'
          'Va a volver a la pila de pendientes para que lo revises de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deshacer'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      _idsBorrar.remove(asset.id);
      _idsGuardadas.remove(asset.id);
      _idsFavoritos.remove(asset.id);
    });
    await _guardarEstado();
    _recalcular();
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

    setState(() => _ocupado = true);

    final borrados =
        await PhotoManager.editor.deleteWithIds(_idsBorrar.toList());

    _idsBorrar.removeAll(borrados);
    await _guardarEstado();

    if (!mounted) return;
    setState(() => _ocupado = false);

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

  String get _titulo {
    switch (_vista) {
      case Vista.revisar:
        return 'Slider';
      case Vista.paraBorrar:
        return 'Para borrar';
      case Vista.guardadas:
        return 'Guardadas';
      case Vista.favoritos:
        return 'Favoritos';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titulo),
        backgroundColor: Colors.transparent,
      ),
      drawer: _menu(),
      body: SafeArea(child: _cuerpo()),
    );
  }

  Widget _menu() {
    return Drawer(
      backgroundColor: const Color(0xFF1B1F2A),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF232838)),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'Slider',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          _itemMenu(Icons.style, 'Revisar', _pendientes.length, Vista.revisar),
          _itemMenu(Icons.delete_outline, 'Para borrar', _idsBorrar.length,
              Vista.paraBorrar),
          _itemMenu(Icons.check_circle_outline, 'Guardadas',
              _idsGuardadas.length, Vista.guardadas),
          _itemMenu(Icons.star_outline, 'Favoritos', _idsFavoritos.length,
              Vista.favoritos),
        ],
      ),
    );
  }

  Widget _itemMenu(IconData icono, String texto, int cantidad, Vista v) {
    final activo = _vista == v;
    return ListTile(
      leading: Icon(icono, color: activo ? Colors.amber : Colors.white70),
      title: Text(
        texto,
        style: TextStyle(color: activo ? Colors.amber : Colors.white),
      ),
      trailing:
          Text('$cantidad', style: const TextStyle(color: Colors.white54)),
      onTap: () {
        setState(() => _vista = v);
        Navigator.pop(context);
      },
    );
  }

  Widget _cuerpo() {
    if (_cargando || _ocupado) {
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

    if (_vista == Vista.revisar) return _vistaRevisar();
    return _vistaLista(_vista);
  }

  Widget _vistaRevisar() {
    if (_pendientes.isEmpty) {
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
                  style: TextStyle(fontSize: 20)),
              const SizedBox(height: 12),
              const Text(
                'Abrí el menú ☰ para ver tus listas.',
                style: TextStyle(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
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

  Widget _vistaLista(Vista v) {
    final lista = _listaDe(v);

    if (lista.isEmpty) {
      return const Center(
        child: Text('Esta lista está vacía.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '${lista.length} archivo(s)  ·  Tocá uno para deshacer',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: lista.length,
            itemBuilder: (context, i) {
              final asset = lista[i];
              return GestureDetector(
                onTap: () => _quitarDeLista(asset, v),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: const Color(0xFF1B1F2A)),
                      FutureBuilder<Uint8List?>(
                        future: asset.thumbnailDataWithSize(
                            const ThumbnailSize(300, 300)),
                        builder: (context, snap) {
                          if (snap.data == null) return const SizedBox();
                          return Image.memory(snap.data!, fit: BoxFit.cover);
                        },
                      ),
                      if (asset.type == AssetType.video)
                        const Positioned(
                          bottom: 4,
                          right: 4,
                          child: Icon(Icons.play_circle_fill,
                              color: Colors.white, size: 20),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (v == Vista.paraBorrar)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _borrarMarcadas,
                icon: const Icon(Icons.delete_forever),
                label: Text('Borrar ${lista.length} archivo(s)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tarjeta(int index, int dx, int dy) {
    final asset = _pendientes[index];
    final esVideo = asset.type == AssetType.video;
    final esActual = index == _indiceActual;
    final datos = _imagenes[asset.id];

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFF1B1F2A)),
          if (datos != null)
            Image.memory(datos, fit: BoxFit.cover, gaplessPlayback: true)
          else
            const Center(child: CircularProgressIndicator()),
          if (esVideo && esActual)
            TarjetaVideo(key: ValueKey(asset.id), asset: asset),
          if (esVideo)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      _duracion(asset.duration),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
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

  String _duracion(int segundos) {
    final m = segundos ~/ 60;
    final s = segundos % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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

class TarjetaVideo extends StatefulWidget {
  final AssetEntity asset;

  const TarjetaVideo({super.key, required this.asset});

  @override
  State<TarjetaVideo> createState() => _TarjetaVideoState();
}

class _TarjetaVideoState extends State<TarjetaVideo> {
  VideoPlayerController? _ctrl;
  bool _listo = false;

  @override
  void initState() {
    super.initState();
    _preparar();
  }

  Future<void> _preparar() async {
    final File? archivo = await widget.asset.file;
    if (archivo == null || !mounted) return;

    final ctrl = VideoPlayerController.file(archivo);
    try {
      await ctrl.initialize();
      await ctrl.setVolume(0);
      await ctrl.setLooping(true);
      await ctrl.play();
    } catch (_) {
      return;
    }

    if (!mounted) {
      ctrl.dispose();
      return;
    }

    setState(() {
      _ctrl = ctrl;
      _listo = true;
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_listo || _ctrl == null) return const SizedBox();

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _ctrl!.value.size.width,
        height: _ctrl!.value.size.height,
        child: VideoPlayer(_ctrl!),
      ),
    );
  }
}
