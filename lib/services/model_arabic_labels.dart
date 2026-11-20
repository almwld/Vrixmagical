/// Arabic labels for common GLB node and asset names; unknown labels remain explicit.
class ModelArabicLabels {
  static const Map<String,String> _labels={
    'duck':'بطة','cube':'مكعب','sphere':'كرة','cylinder':'أسطوانة','cone':'مخروط',
    'plane':'سطح','chair':'كرسي','table':'طاولة','car':'سيارة','tree':'شجرة',
    'person':'شخص','human':'إنسان','robot':'روبوت','character':'شخصية','body':'الجسم',
    'head':'الرأس','arm':'الذراع','leftarm':'الذراع الأيسر','rightarm':'الذراع الأيمن',
    'leg':'الساق','leftleg':'الساق اليسرى','rightleg':'الساق اليمنى','hand':'اليد',
    'eye':'العين','camera':'الكاميرا','light':'الإضاءة','mesh':'الشبكة الهندسية',
    'material':'الخامة','texture':'النسيج',
  };
  static String translate(String source) {
    final key=source.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'),'');
    return _labels[key]??source;
  }
  static String displayName(String source) {
    final translated=translate(source);
    return translated==source && RegExp(r'^[a-zA-Z0-9 _.-]+$').hasMatch(source) ? 'مجسم مستورد · $source' : translated;
  }
}
