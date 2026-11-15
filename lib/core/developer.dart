/// developer.dart — بيانات المطوّر (حقوق + دعم). مصدر واحد لكل الشاشات.
library;

abstract final class Developer {
  static const name = 'معين العباسي';
  static const phone = '+967770941666';
  static const phoneDisplay = '+967 770 941 666';
  static const website = 'alabbasi.uk';
  static const downloads = 'downloads.alabbasi.uk';

  static Uri get tel => Uri.parse('tel:$phone');
  static Uri whatsapp([String text = '']) =>
      Uri.https('wa.me', '/${phone.replaceAll('+', '')}', text.isEmpty ? null : {'text': text});
  static Uri get site => Uri.https(website);
  static Uri get downloadsSite => Uri.https(downloads);
}
