/// Dark sci-fi Google Maps style: near-black land, teal roads, cyan water.
const String kSonicMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#05080f"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#3d8fa3"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#05080f"}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#12324a"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"visibility": "on"}, {"color": "#071a1c"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#0d2a36"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#0f4c5c"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#0f4c5c"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#00e5ff"}, {"weight": 0.4}]},
  {"featureType": "road", "elementType": "labels", "stylers": [{"visibility": "simplified"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#021e2b"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#1b6f7f"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry.stroke", "stylers": [{"color": "#0b2233"}]}
]
''';
