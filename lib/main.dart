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

enum Medio { imagen, video }

enum Seccion { revisar, paraBorrar, guardadas, favoritos }

class PantallaPrincipal extends StatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  State<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends State<PantallaPrincipal> {
  static const int _ventana = 6;

  CardSwiperController _controlador = CardSwiperController();

  final Map<String, Uint8List> _imagenesCache = {};
  final Set<String> _pidiendo = {};

  bool _cargando = true;
  bool _sinPermiso = false;
  bool _ocupado = false;

  Medio _medio = Medio.imagen;
  Seccion _seccion = Seccion.revisar;

  List<AssetEntity> _todas = [];
  List<AssetEntity> _pendientes = [];

  final Map<Medio, Set<String>> _borrar = {
    Medio.imagen: {},
    Medio.video: {},
  };
  final Map<Medio, Set<String>> _guardadas = {
    Medio.imagen: {},
    Medio.video: {},
  };
  final Map<Medio, Set<String>> _favoritos = {
    Medio.imagen: {},
    Medio.video: {},
  };

  int _indiceActual = 0;

  String _clave(String base, Medio m) =>
      'slider_${base}_${m == Medio.imagen ? 'img' : 'vid'}';

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

    for (final m in Medio.values) {
      _borrar[m] =
          (prefs.getStringList(_clave('borrar', m)) ?? []).toSet();
      _guardadas[m] =
          (prefs.getStringList(_clave('guardadas', m)) ?? []).toSet();
      _favoritos[m] =
          (prefs.getStringList(_clave('favoritos', m)) ?? []).toSet();
    }

    final viejasGuardadas = prefs.getStringList('slider_guardadas');
    if (viejasGuardadas != null && viejasGuardadas.isNotEmpty) {
      _guardadas[Medio.imagen]!.addAll(viejasGuardadas);
      await prefs.remove('slider_guardadas');
    }
    final viejasBorrar = prefs.getStringList('slider_para_borrar');
    if (viejasBorrar != null && viejasBorrar.isNotEmpty) {
      _borrar[Medio.imagen]!.addAll(viejasBorrar);
      await prefs.remove('slider_para_borrar');
    }
    final viejasFav = prefs.getStringList('slider_favoritos');
    if (viejasFav != null && viejasFav.isNotEmpty) {
      _favoritos[Medio.imagen]!.addAll(viejasFav);
      await prefs.remove('slider_favoritos');
    }

    await _guardarEstado();
    await _cargarTodo();
  }

  Future<void> _guardarEstado() async {
    final prefs = await SharedPreferences.getInstance();
    for (final m in Medio.values) {
      await prefs.setStringList(_clave('borrar', m), _borrar[m]!.toList());
      await prefs.setStringList(
          _clave('guardadas', m), _guardadas[m]!.toList());
      await prefs.setStringList(
          _clave('favoritos', m), _favoritos[m]!.toList());
    }
  }

  Future<void> _cargarTodo() async {
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
    });
    _recalcular();
  }

  bool _esDelMedio(AssetEntity a, Medio m) {
    if (m == Medio.video) return a.type == AssetType.video;
    return a.type == AssetType.image;
  }

  void _recalcular() {
    final decididos = <String>{}
      ..addAll(_borrar[_medio]!)
      ..addAll(_guardadas[_medio]!)
      ..addAll(_favoritos[_medio]!);

    setState(() {
      _pendientes = _todas
          .where((a) => _esDelMedio(a, _medio) && !decididos.contains(a.id))
          .toList();
      _controlador = CardSwiperController();
      _indiceActual = 0;
      _imagenesCache.clear();
    });
    _precargar();
  }

  void _precargar() {
    final hasta = (_indiceActual + _ventana).clamp(0, _pendientes.length);
    for (var i = _indiceActual; i < hasta; i++) {
      final asset = _pendientes[i];
      if (_imagenesCache.containsKey(asset.id)) continue;
      if (_pidiendo.contains(asset.id)) continue;
      _pidiendo.add(asset.id);
      asset
          .thumbnailDataWithSize(const ThumbnailSize(800, 800))
          .then((datos) {
        _pidiendo.remove(asset.id);
        if (datos == null || !mounted) return;
        _imagenesCache[asset.id] = datos;
        setState(() {});
      });
    }

    final vigentes = <String>{};
    for (var i = _indiceActual; i < hasta; i++) {
      vigentes.add(_pendientes[i].id);
    }
    _imagenesCache.removeWhere((id, _) => !vigentes.contains(id));
  }

  Set<String> _idsDe(Seccion s, Medio m) {
    if (s == Seccion.paraBorrar) return _borrar[m]!;
    if (s == Seccion.guardadas) return _guardadas[m]!;
    return _favoritos[m]!;
  }

  List<AssetEntity> _listaDe(Seccion s, Medio m) {
    final ids = _idsDe(s, m);
    return _todas
        .where((a) => _esDelMedio(a, m) && ids.contains(a.id))
        .toList();
  }

  bool _alDeslizar(int anterior, int? actual, CardSwiperDirection dir) {
    final asset = _pendientes[anterior];
    setState(() {
      _indiceActual = actual ?? anterior + 1;
      if (dir == CardSwiperDirection.left) {
        _borrar[_medio]!.add(asset.id);
      } else if (dir == CardSwiperDirection.right) {
        _guardadas[_medio]!.add(asset.id);
      } else if (dir == CardSwiperDirection.top) {
        _favoritos[_medio]!.add(asset.id);
      }
    });
    _guardarEstado();
    _precargar();
    return true;
  }

  Future<void> _quitarDeLista(AssetEntity asset, Seccion s, Medio m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deshacer'),
        content: const Text(
          'Este archivo va a volver a la pila de pendientes '
          'para que lo revises de nuevo.',
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
      _borrar[m]!.remove(asset.id);
      _guardadas[m]!.remove(asset.id);
      _favoritos[m]!.remove(asset.id);
    });
    await _guardarEstado();
    _recalcular();
  }

  Future<void> _borrarMarcadas(Medio m) async {
    final ids = _borrar[m]!;
    if (ids.isEmpty) return;

    final tipo = m == Medio.video ? 'video(s)' : 'imagen(es)';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar archivos'),
        content: Text(
          'Vas a borrar ${ids.length} $tipo de tu teléfono.\n\n'
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

    final borrados = await PhotoManager.editor.deleteWithIds(ids.toList());

    _borrar[m]!.removeAll(borrados);
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

    await _cargarTodo();
  }

  String get _titulo {
    final tipo = _medio == Medio.video ? 'Videos' : 'Imágenes';
    switch (_seccion) {
      case Seccion.revisar:
        return '$tipo · Revisar';
      case Seccion.paraBorrar:
        return '$tipo · Para borrar';
      case Seccion.guardadas:
        return '$tipo · Guardadas';
      case Seccion.favoritos:
        return '$tipo · Favoritos';
    }
  }

  int _pendientesDe(Medio m) {
    final decididos = <String>{}
      ..addAll(_borrar[m]!)
      ..addAll(_guardadas[m]!)
      ..addAll(_favoritos[m]!);
    return _todas
        .where((a) => _esDelMedio(a, m) && !decididos.contains(a.id))
        .length;
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
          _encabezado('IMÁGENES'),
          ..._itemsDe(Medio.imagen),
          const Divider(color: Colors.white24),
          _encabezado('VIDEOS'),
          ..._itemsDe(Medio.video),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _encabezado(String texto) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        texto,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  List<Widget> _itemsDe(Medio m) {
    return [
      _item(Icons.style, 'Revisar', _pendientesDe(m), m, Seccion.revisar),
      _item(Icons.delete_outline, 'Para borrar', _borrar[m]!.length, m,
          Seccion.paraBorrar),
      _item(Icons.check_circle_outline, 'Guardadas', _guardadas[m]!.length,
          m, Seccion.guardadas),
      _item(Icons.star_outline, 'Favoritos', _favoritos[m]!.length, m,
          Seccion.favoritos),
    ];
  }

  Widget _item(
      IconData icono, String texto, int cantidad, Medio m, Seccion s) {
    final activo = _medio == m && _seccion == s;
    return ListTile(
      dense: true,
      leading: Icon(icono,
          size: 22, color: activo ? Colors.amber : Colors.white70),
      title: Text(
        texto,
        style: TextStyle(color: activo ? Colors.amber : Colors.white),
      ),
      trailing:
          Text('$cantidad', style: const TextStyle(color: Colors.white54)),
      onTap: () {
        final cambioMedio = _medio != m;
        setState(() {
          _medio = m;
          _seccion = s;
        });
        Navigator.pop(context);
        if (cambioMedio) _recalcular();
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
                'Slider necesita permiso para ver tus fotos y videos.',
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

    if (_seccion == Seccion.revisar) return _vistaRevisar();
    return _vistaLista(_seccion, _medio);
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
              Text(
                _medio == Medio.video
                    ? 'No hay videos pendientes'
                    : 'No hay imágenes pendientes',
                style: const TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
              ),
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
            '${_pendientes.length} pendientes',
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

  Widget _vistaLista(Seccion s, Medio m) {
    final lista = _listaDe(s, m);

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
                onTap: () => _quitarDeLista(asset, s, m),
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
        if (s == Seccion.paraBorrar)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _borrarMarcadas(m),
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
    final datos = _imagenesCache[asset.id];

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
            TarjetaVideo(
              key: ValueKey(asset.id),
              asset: asset,
              miniatura: datos,
            ),
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
            'Para borrar: ${_borrar[_medio]!.length}   ·   '
            'Guardadas: ${_guardadas[_medio]!.length}   ·   '
            'Favoritos: ${_favoritos[_medio]!.length}',
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
  final Uint8List? miniatura;

  const TarjetaVideo({
    super.key,
    required this.asset,
    this.miniatura,
  });

  @override
  State<TarjetaVideo> createState() => _TarjetaVideoState();
}

class _TarjetaVideoState extends State<TarjetaVideo> {
  VideoPlayerController? _ctrl;
  bool _listo = false;
  bool _fallo = false;

  @override
  void initState() {
    super.initState();
    _preparar();
  }

  Future<void> _preparar() async {
    try {
      final File? archivo = await widget.asset.file;
      if (archivo == null || !mounted) {
        _marcarFallo();
        return;
      }

      final ctrl = VideoPlayerController.file(archivo);
      await ctrl.initialize();
      await ctrl.setVolume(0);
      await ctrl.setLooping(true);
      await ctrl.play();

      if (!mounted) {
        ctrl.dispose();
        return;
      }

      setState(() {
        _ctrl = ctrl;
        _listo = true;
      });
    } catch (_) {
      _marcarFallo();
    }
  }

  void _marcarFallo() {
    if (!mounted) return;
    setState(() => _fallo = true);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_listo && _ctrl != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _ctrl!.value.size.width,
          height: _ctrl!.value.size.height,
          child: VideoPlayer(_ctrl!),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.miniatura != null)
          Image.memory(widget.miniatura!, fit: BoxFit.cover)
        else
          Container(color: const Color(0xFF1B1F2A)),
        if (!_fallo) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
