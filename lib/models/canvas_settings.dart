enum ColorModel {
  sRGB,
  adobeRGB,
  proPhoto,
  cmyk;
}

enum CanvasUnit { px, mm }

class CanvasSettings {
  final int width;
  final int height;
  final CanvasUnit unit;
  final double resolution;
  final ColorModel colorModel;
  final int channelDepth;
  final String? iccProfilePath;
  final List<int>? iccProfileData;

  const CanvasSettings({
    required this.width,
    required this.height,
    this.unit = CanvasUnit.px,
    this.resolution = 72,
    this.colorModel = ColorModel.sRGB,
    this.channelDepth = 8,
    this.iccProfilePath,
    this.iccProfileData,
  });

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'unit': unit.name,
        'resolution': resolution,
        'colorModel': colorModel.name,
        'channelDepth': channelDepth,
        'iccProfilePath': iccProfilePath,
      };

  factory CanvasSettings.fromJson(Map<String, dynamic> json) =>
      CanvasSettings(
        width: json['width'] as int,
        height: json['height'] as int,
        unit: CanvasUnit.values.firstWhere(
            (e) => e.name == json['unit'],
            orElse: () => CanvasUnit.px),
        resolution: (json['resolution'] as num).toDouble(),
        colorModel: ColorModel.values.firstWhere(
            (e) => e.name == json['colorModel'],
            orElse: () => ColorModel.sRGB),
        channelDepth: json['channelDepth'] as int? ?? 8,
        iccProfilePath: json['iccProfilePath'] as String?,
      );

  CanvasSettings copyWith({
    int? width,
    int? height,
    CanvasUnit? unit,
    double? resolution,
    ColorModel? colorModel,
    int? channelDepth,
    String? iccProfilePath,
    List<int>? iccProfileData,
  }) =>
      CanvasSettings(
        width: width ?? this.width,
        height: height ?? this.height,
        unit: unit ?? this.unit,
        resolution: resolution ?? this.resolution,
        colorModel: colorModel ?? this.colorModel,
        channelDepth: channelDepth ?? this.channelDepth,
        iccProfilePath: iccProfilePath ?? this.iccProfilePath,
        iccProfileData: iccProfileData ?? this.iccProfileData,
      );
}
