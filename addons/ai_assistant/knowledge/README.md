# Layer 2 — Knowledge & RAG (Bilgi & Anlamsal Arama)

Bellekteki (Layer 1) ve koddaki bilgiyi anlamsal olarak aranabilir yapar.

## Dosyalar

- tokenizer.gd — Metni kök kelimelere ayırır (TR+EN, fixed-point normalize)
- knowledge_doc.gd — RAG belge birimi contract'ı
- tfidf_retriever.gd — TF-IDF anlamsal arama motoru (bütçesiz, lokal)
- knowledge_base.gd — Layer 2 ana yönetici
- _knowledge_test.gd — sıkı testler (idempotency + koruma + stress dahil)

## normalize() — mühendislik garantileri

Kelimeyi köküne indirir. Üç sağlamlık garantisi:

1. IDEMPOTENT: normalize(normalize(x)) == normalize(x).
   Fixed-point döngü ile çok katmanlı ekler tek seferde soyulur.
   ("renderings" -> "render", iki kez çağrılsa da aynı sonuç.)

2. KORUMA LİSTESİ: PROTECTED_STEMS'teki teknik terimler asla kırpılmaz.
   "render" kelimesi "-er" eki sanılıp "rend"e kırpılmaz.

3. AŞIRI KIRPMA YOK: kök her zaman >= MIN_STEM_LENGTH (3) karakter.

TR+EN: hem Türkçe sonekler (sıdır, ları, landırma...) hem İngilizce
sonekler (ing, tion, ization...) kırpılır. İndeksleme ve arama AYNI
normalize'i kullanır.

## TF-IDF

IDF formülü log(1 + total/(1+df)) — negatif IDF'e karşı korumalı.
Prefix eşleşme — normalize sonrası kök farkları için ek güvenlik.

## Kalite süreci

Bu katman bir GDScript statik analiz aracı (ai-asistann/gdlint.py) ve
agresif stress testlerden geçirildi. Çıkan her bug kalıcı bir test/kural
haline getirildi — aynı hata bir daha geçemez.
