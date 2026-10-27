class CityLocation {
  final String id;
  final String city;
  final String country;
  final String countryCode;
  int? ping;
  bool unreachable;

  CityLocation({
    required this.id,
    required this.city,
    required this.country,
    required this.countryCode,
    this.ping,
    this.unreachable = false,
  });

  factory CityLocation.fromCandidate(Map<String, dynamic> json, {String country = 'Unknown', String countryCode = 'xx'}) {
    return CityLocation(
      id: json['id'] as String,
      city: (json['city'] as String?)?.trim() ?? 'Unknown City',
      country: (json['country'] as String?)?.trim() ?? country,
      countryCode: (json['country_code'] as String?)?.trim().toLowerCase() ?? countryCode,
      ping: null,
      unreachable: false,
    );
  }
}

class CountryGroup {
  final String countryName;
  final String countryCode;
  final List<CityLocation> locations;

  CountryGroup({
    required this.countryName,
    required this.countryCode,
    required this.locations,
  });
}

class SelectedLocationMeta {
  final String id;
  final String country;
  final String city;
  final String countryCode;

  const SelectedLocationMeta({
    required this.id,
    required this.country,
    required this.city,
    required this.countryCode,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'country': country,
        'city': city,
        'countryCode': countryCode,
      };

  factory SelectedLocationMeta.fromJson(Map<String, dynamic> json) => SelectedLocationMeta(
        id: json['id'] as String,
        country: json['country'] as String,
        city: json['city'] as String,
        countryCode: json['countryCode'] as String,
      );
}