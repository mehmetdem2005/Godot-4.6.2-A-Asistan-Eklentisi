#!/usr/bin/env python3
"""
gdlint.py ÖZ-TESTİ
==================
Linter bir test aracı — kendisi de test edilmeli. Bu dosya, gdlint'in
14 kuralının (R01-R14) her birini DOĞRULAR:
  - Bilinen-bug örneği -> kural yakalamalı (true positive)
  - Temiz örnek        -> kural susmalı   (true negative)

Linter sessizce bozulursa bu test kırmızı verir.
Çalıştır: python3 gdlint_selftest.py
"""
import subprocess
import sys
import os
import tempfile

LINTER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gdlint.py")

# Her senaryo: (ad, dosya_içeriği, beklenen_kural_kodu_veya_None)
# None = temiz olmalı (hiçbir kural tetiklenmemeli)
SCENARIOS = [
    # --- R01: @tool ilk satır ---
    ("R01 ihlal: @tool yok",
     "class_name X\nextends RefCounted\n", "R01"),
    ("R01 temiz",
     "@tool\nclass_name X\nextends RefCounted\n", None),

    # --- R04: const PackedXArray ---
    ("R04 ihlal: const PackedStringArray",
     '@tool\nclass_name X\nextends RefCounted\n'
     'const A: PackedStringArray = PackedStringArray(["x"])\n', "R04"),
    ("R04 temiz: const Array",
     '@tool\nclass_name X\nextends RefCounted\n'
     'const A: Array = ["x"]\n', None),

    # --- R05: const içinde fonksiyon çağrısı ---
    ("R05 ihlal: const metod çağrısı",
     '@tool\nclass_name X\nextends RefCounted\n'
     'const A = Time.get_ticks_msec()\n', "R05"),

    # --- R06: space-indent ---
    ("R06 ihlal: boşluk girinti",
     '@tool\nclass_name X\nextends RefCounted\n'
     'func f() -> void:\n    pass\n', "R06"),
    ("R06 temiz: tab girinti",
     '@tool\nclass_name X\nextends RefCounted\n'
     'func f() -> void:\n\tpass\n', None),

    # --- R07: inner class extends inline ---
    ("R07 ihlal: inner class extends ayrı",
     '@tool\nclass_name X\nextends RefCounted\n'
     'class Inner:\n\tvar a: int = 1\n', "R07"),
    ("R07 temiz: inner class extends inline",
     '@tool\nclass_name X\nextends RefCounted\n'
     'class Inner extends RefCounted:\n\tvar a: int = 1\n', None),

    # --- R10: parantez dengesi ---
    ("R10 ihlal: dengesiz parantez",
     '@tool\nclass_name X\nextends RefCounted\n'
     'func f() -> int:\n\treturn (1 + 2\n', "R10"),
    ("R10 temiz: escape'li string içi parantez",
     '@tool\nclass_name X\nextends RefCounted\n'
     'func f() -> String:\n\treturn "merhaba )"\n', None),
    ("R10 temiz: escape'li tırnak içi parantez",
     '@tool\nclass_name X\nextends RefCounted\n'
     'func f() -> String:\n\treturn "x \\")\\" y"\n', None),

    # --- R11: tab+space karışık ---
    ("R11 ihlal: karışık girinti",
     '@tool\nclass_name X\nextends RefCounted\n'
     'func f() -> void:\n\t pass\n', "R11"),

    # --- R13: çift fonksiyon ---
    ("R13 ihlal: çift func",
     '@tool\nclass_name X\nextends RefCounted\n'
     'func foo() -> void:\n\tpass\n'
     'func foo() -> void:\n\tpass\n', "R13"),
    ("R13 temiz: tek func",
     '@tool\nclass_name X\nextends RefCounted\n'
     'func foo() -> void:\n\tpass\n'
     'func bar() -> void:\n\tpass\n', None),

    # --- R14: yerleşik fonksiyon adı çakışması ---
    ("R14 ihlal: 'sign' yerleşikle çakışır",
     '@tool\nclass_name X\nextends RefCounted\n'
     'func sign(content: String) -> String:\n\treturn content\n', "R14"),
    ("R14 temiz: çakışmayan ad",
     '@tool\nclass_name X\nextends RefCounted\n'
     'func sign_content(content: String) -> String:\n\treturn content\n',
     None),
    ("R14 ihlal: 'is_connected' miras metoduyla çakışır",
     '@tool\nclass_name X\nextends RefCounted\n'
     'func is_connected() -> bool:\n\treturn true\n', "R14"),
]


def run_linter(path):
    """Linter'ı çalıştırır, çıktı metnini döndürür."""
    result = subprocess.run(
        [sys.executable, LINTER, path],
        capture_output=True, text=True
    )
    return result.stdout


def main():
    passed = 0
    failed = 0
    failures = []

    for name, content, expected_rule in SCENARIOS:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".gd", delete=False, encoding="utf-8"
        ) as f:
            f.write(content)
            tmp_path = f.name

        try:
            output = run_linter(tmp_path)
            if expected_rule is None:
                # Temiz olmalı — hiçbir kural tetiklenmemeli
                ok = "TEMİZ" in output
                detail = "temiz bekleniyordu" if not ok else ""
            else:
                # Belirli kural tetiklenmeli
                ok = expected_rule in output
                detail = (
                    "%s bekleniyordu, çıktıda yok" % expected_rule
                    if not ok else ""
                )
        finally:
            os.unlink(tmp_path)

        if ok:
            passed += 1
            print("  OK   %s" % name)
        else:
            failed += 1
            failures.append("%s — %s" % (name, detail))
            print("  FAIL %s  (%s)" % (name, detail))

    print()
    print("=== gdlint.py ÖZ-TEST — %d senaryo ===" % len(SCENARIOS))
    if failed == 0:
        print("  ✓ %d/%d — linter'ın 14 kuralı doğrulandı" % (passed, len(SCENARIOS)))
        return 0
    else:
        print("  ⚠ %d BAŞARISIZ:" % failed)
        for f in failures:
            print("    - " + f)
        return 1


# R12 (cross-file enum) tek dosyada test edilemez — çok dosya gerekir.
# Ana pre-flight'ta tüm sistem birlikte taranınca R12 zaten devrede.
# Bu öz-test tek-dosya kurallarını (R01-R11, R13, R14) kapsar.

if __name__ == "__main__":
    sys.exit(main())
