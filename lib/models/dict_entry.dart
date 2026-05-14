class DictEntry {
  final String traditional;
  final String simplified;
  final String pinyinRead;
  final String pinyinType;
  final List<String> definition;

  const DictEntry({
    required this.traditional,
    required this.simplified,
    required this.pinyinRead,
    required this.pinyinType,
    required this.definition,
  });

  factory DictEntry.fromJson(Map<String, dynamic> json) {
    return DictEntry(
      traditional: json['traditional'] as String? ?? '',
      simplified: json['simplified'] as String? ?? '',
      pinyinRead: json['pinyinRead'] as String? ?? '',
      pinyinType: json['pinyinType'] as String? ?? '',
      definition: (json['definition'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}
