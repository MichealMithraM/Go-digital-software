import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/office_address_search.dart';

class HomeMapSelection {
  const HomeMapSelection(this.point, this.address);
  final LatLng point;
  final String address;
}

class HomeLocationPicker extends StatefulWidget {
  const HomeLocationPicker({super.key, this.center, this.address = ''});
  final LatLng? center;
  final String address;
  @override
  State<HomeLocationPicker> createState() => _HomeLocationPickerState();
}

class _HomeLocationPickerState extends State<HomeLocationPicker> {
  late final _address = TextEditingController(text: widget.address);
  GoogleMapController? _controller;
  LatLng? _selected;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_searching || _address.text.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });
    try {
      final results = await searchOfficeAddress(_address.text.trim());
      if (!mounted) return;
      setState(() {
        _results = results;
        if (results.isEmpty)
          _error = 'No address found. Zoom the map and place your Home pin.';
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Address search is unavailable. You can still zoom the map and place your Home pin.',
        );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _confirm() {
    if (_selected == null) return;
    if (_address.text.trim().isEmpty) {
      setState(
        () => _error =
            'Enter your Home address so admin can verify the selected pin.',
      );
      return;
    }
    Navigator.pop(context, HomeMapSelection(_selected!, _address.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Select Home on Map'),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Search your address, then tap the map to place the pin on your home. Admin must verify this location before Home check-in is available.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              maxLength: 500,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(
                labelText: 'Home address',
                border: OutlineInputBorder(),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _searching ? null : _search,
              icon: const Icon(Icons.search),
              label: Text(_searching ? 'Searching...' : 'Find address'),
            ),
            for (final result in _results.take(4))
              ListTile(
                title: Text('${result['address']}'),
                onTap: () {
                  final point = LatLng(
                    (result['latitude'] as num).toDouble(),
                    (result['longitude'] as num).toDouble(),
                  );
                  setState(() {
                    _address.text = '${result['address']}';
                    _results = [];
                    _selected = point;
                    _error = null;
                  });
                  _controller?.animateCamera(
                    CameraUpdate.newLatLngZoom(point, 18),
                  );
                },
              ),
            SizedBox(
              height: 300,
              child: GoogleMap(
                // World view is only a camera fallback; no pin is preselected.
                initialCameraPosition: CameraPosition(
                  target: widget.center ?? const LatLng(0, 0),
                  zoom: widget.center == null ? 2 : 15,
                ),
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                onMapCreated: (controller) => _controller = controller,
                onTap: (point) => setState(() {
                  _selected = point;
                  _error = null;
                }),
                markers: _selected == null
                    ? {}
                    : {
                        Marker(
                          markerId: const MarkerId('home-pin'),
                          position: _selected!,
                          draggable: true,
                          onDragEnd: (point) =>
                              setState(() => _selected = point),
                        ),
                      },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selected == null
                  ? 'Tap your home on the map to select it.'
                  : 'Selected Home: ${_selected!.latitude.toStringAsFixed(7)}, ${_selected!.longitude.toStringAsFixed(7)}',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _selected == null || _searching ? null : _confirm,
        child: const Text('Use Selected Home'),
      ),
    ],
  );
}
