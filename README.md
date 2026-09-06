# Gobby

macOS 14 ve üzeri için, yalnızca menü çubuğundan çalışan bir pano geçmişi uygulaması.

## Dahil olanlar

- Metin, URL, dosya yolu ve görüntü/screenshot yakalama; renk, kod, e-posta ve telefon sınıflaması
- Disk üzerinde üretilen küçük görseller, büyük görüntü önizlemesi ve yerel kalıcı saklama
- Apple Vision ile yalnızca cihaz üzerinde çalışan, aranabilir OCR
- Anlık sabitleme, aranabilir özel sabit adı ve renk grupları
- Kartı sağa sürükleyerek silme, sola sürükleyerek sabitleme
- Gün bazında öğe işaretleri olan aylık takvim
- Gobby Stack: sıraya ekleme, sıralama, sıradakini panoya alma, başa sarma ve temizleme
- Arama alanına otomatik odak, ok tuşları/Enter/Escape ve panel içi klavye kısayolları
- Yapılandırılabilir genel `⌥ Space` ve `⌥ V` kısayolları
- Düz metin olarak panoya alma
- Hariç tutulan uygulamalar, gizli/geçici pano türlerine saygı ve yerel-first depolama
- 1/7/30/90 gün veya sınırsız saklama; sabitlenmiş öğeler her zaman korunur
- Tek tıklamayla geçmiş öğesini sistem panosuna geri alma
- Apple Universal Clipboard ile iPhone’a yapıştırma
- Otomatik, açık, koyu ve desteklenen macOS sürümünde yerel SwiftUI Liquid Glass görünümü
- Dock'ta ayrı bir uygulama penceresi oluşturmadan menü çubuğunda çalışma; Ayarlar tek ayrı penceredir

## Çalıştırma

1. Xcode 15 veya daha yenisiyle `ClipCalendar.xcodeproj` dosyasını açın.
2. Gerekirse Signing & Capabilities altında kendi Team'inizi seçin ve `PRODUCT_BUNDLE_IDENTIFIER` değerini benzersiz bir değerle değiştirin.
3. **Run**'a basın. Menü çubuğundaki Gobby simgesine tıklayın.

Bir geçmiş öğesine tıklamak onu Mac'in genel panosuna yazar. Aynı Apple hesabındaki iPhone’da Wi‑Fi, Bluetooth ve Handoff açıksa, iPhone’da yapıştırma alanına dokunup yapıştırarak bu öğeyi kullanabilirsiniz. Bu Apple'ın Universal Clipboard özelliğidir.

Ekran görüntülerinin kayda girmesi için görüntünün panoya kopyalanması gerekir. macOS'ta `Control` + `Shift` + `Command` + `3/4` ile alınan screenshot bu şekilde yakalanır.

Gobby hiçbir pano içeriğini, OCR sonucunu veya arama sorgusunu ağa göndermez. Apple Universal Clipboard aktarımı, Apple’ın sistem düzeyindeki Continuity özelliğidir.
