#!/usr/bin/env python3
"""
GDScript Statik Analiz Aracı — Pre-flight Kontrol
==================================================
Container'da Godot binary yok. Bu araç, Godot'a göndermeden ÖNCE
GDScript dosyalarını gerçek dil kurallarına göre denetler.

Tasarım ilkesi: şu ana kadar çıkan HER bug burada bir kural.
Yeni bug çıkarsa -> yeni kural eklenir, bir daha asla geçmez.

Çıkış kodu: 0 = temiz, 1 = hata var.
"""
import re
import sys
import glob

# Godot 4.x yerleşik tipleri (eksik liste değil ama yaygınları kapsar)
BUILTIN_TYPES = {
    "int", "float", "bool", "String", "StringName", "NodePath",
    "Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i",
    "Color", "Rect2", "Rect2i", "Transform2D", "Transform3D", "Basis",
    "Quaternion", "Plane", "AABB", "Projection",
    "Array", "Dictionary", "Variant", "Callable", "Signal", "RID",
    "PackedByteArray", "PackedInt32Array", "PackedInt64Array",
    "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray",
    "PackedVector2Array", "PackedVector3Array", "PackedColorArray",
    "Object", "RefCounted", "Node", "Resource", "void",
}

# const için izin verilen literal tipler (constant expression olabilenler)
# PackedXArray ASLA const olamaz — fonksiyon çağrısı gerektirir.
PACKED_TYPES = {t for t in BUILTIN_TYPES if t.startswith("Packed")}


class Issue:
    def __init__(self, severity, fn, line, rule, msg):
        self.severity = severity  # "ERROR" | "WARN"
        self.fn = fn
        self.line = line
        self.rule = rule
        self.msg = msg

    def __str__(self):
        loc = f"{self.fn}:{self.line}" if self.line else self.fn
        return f"  [{self.severity}] {loc}  ({self.rule})\n      {self.msg}"


def strip_comment(line):
    """Satırdan yorumu çıkarır — string içindeki # korunur."""
    in_str = False
    quote = ""
    for i, ch in enumerate(line):
        if in_str:
            if ch == quote:
                in_str = False
        else:
            if ch in ('"', "'"):
                in_str = True
                quote = ch
            elif ch == "#":
                return line[:i]
    return line


def strip_strings(line):
    """String literalleri boşaltır — parantez sayımında string içeriği bozmasın.
    Escape karakterini (\\) tanır: \\" string'i bitirmez."""
    out = []
    in_str = False
    quote = ""
    escaped = False
    for ch in line:
        if in_str:
            if escaped:
                # Bir önceki karakter \ idi — bu karakter escape'li, atla
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                in_str = False
                out.append(quote)
            # string içi atlanır
        else:
            if ch in ('"', "'"):
                in_str = True
                quote = ch
                escaped = False
                out.append(quote)
            else:
                out.append(ch)
    return "".join(out)


def analyze_file(fn):
    issues = []
    with open(fn, encoding="utf-8") as f:
        raw_lines = f.readlines()

    code_only = "".join(strip_strings(strip_comment(l)) for l in raw_lines)

    # ---- KURAL 1: @tool ilk satırda ----
    if not raw_lines or raw_lines[0].strip() != "@tool":
        issues.append(Issue("ERROR", fn, 1, "R01-tool",
            "Dosya '@tool' ile başlamalı (editör-içi çalışma için)"))

    # ---- KURAL 2: extends mevcut ----
    if not any(l.strip().startswith("extends ") for l in raw_lines[:10]):
        issues.append(Issue("ERROR", fn, None, "R02-extends",
            "'extends' bildirimi yok"))

    # ---- KURAL 3: class_name extends'ten SONRA değil ÖNCE olmamalı ----
    # GDScript: class_name extends'ten hemen sonra (veya @tool sonrası) gelir.
    cn_line = ext_line = None
    for i, l in enumerate(raw_lines, 1):
        s = l.strip()
        if s.startswith("class_name ") and cn_line is None:
            cn_line = i
        if s.startswith("extends ") and ext_line is None:
            ext_line = i
    # class_name varsa, ilk 5 satırda olmalı
    if cn_line and cn_line > 5:
        issues.append(Issue("ERROR", fn, cn_line, "R03-classname-pos",
            "class_name dosyanın başında (extends yanında) olmalı"))

    # ---- Satır-satır kurallar ----
    for i, raw in enumerate(raw_lines, 1):
        code = strip_comment(raw)
        s = code.strip()

        # ---- KURAL 4: const PackedXArray YASAK ----
        # Godot: const değeri derleme-zamanı sabiti olmalı.
        # PackedStringArray(...) bir fonksiyon çağrısı -> const olamaz.
        if s.startswith("const "):
            for pt in PACKED_TYPES:
                # const X: PackedStringArray = ...  veya  = PackedStringArray(...)
                if f": {pt}" in s or f"{pt}(" in s:
                    issues.append(Issue("ERROR", fn, i, "R04-const-packed",
                        f"const ile '{pt}' kullanılamaz (constant expression değil). "
                        f"Düz 'Array' literal kullan."))
                    break

        # ---- KURAL 5: const içinde fonksiyon/metod çağrısı ----
        # const X = generate_id(...) / Time.xxx() / Foo.new() -> hata
        if s.startswith("const "):
            rhs = s.split("=", 1)[1] if "=" in s else ""
            # X.Y( ... ) veya foo( ... ) deseni — ama Array/Dictionary literal değil
            if re.search(r'[a-zA-Z_]\w*\s*\.\s*[a-zA-Z_]\w*\s*\(', rhs):
                issues.append(Issue("ERROR", fn, i, "R05-const-call",
                    "const içinde metod çağrısı olamaz (derleme-zamanı sabiti şart)"))

        # ---- KURAL 6: space-indent (Godot tab ister) ----
        if raw.startswith("    ") and not raw.startswith("\t"):
            issues.append(Issue("ERROR", fn, i, "R06-indent",
                "Boşluk ile girinti — Godot tab bekler"))

        # ---- KURAL 7: inner class 'extends' inline olmalı ----
        # 'class Foo:' (extends ayrı satırda) -> hata; 'class Foo extends Bar:' -> ok
        m = re.match(r'\s*class\s+\w+\s*:', code)
        if m:
            issues.append(Issue("ERROR", fn, i, "R07-inner-class",
                "Inner class 'extends'i inline olmalı: 'class X extends Y:'"))

        # ---- KURAL 8: trailing whitespace olan satır sonu ':' ----
        # 'func foo() :' gibi — Godot toleranslı ama temizlik
        if re.search(r'\)\s+:\s*$', code):
            issues.append(Issue("WARN", fn, i, "R08-colon-space",
                "Parantez ile ':' arasında boşluk"))

        # ---- KURAL 9: 'func' tanımı sonrası ':' eksik ----
        if re.match(r'\s*(static\s+)?func\s+\w+\s*\(', code):
            # çok satıra yayılmış imza olabilir — basitçe aynı satırda ) ve : ara
            if ")" in code and not code.rstrip().endswith(":") and "->" not in code:
                # çok satırlı imza ihtimali — sonraki satırlara bak
                joined = code
                j = i
                while j < len(raw_lines) and not strip_comment(joined).rstrip().endswith(":"):
                    joined += strip_comment(raw_lines[j])
                    j += 1
                    if j - i > 8:
                        break
                if not strip_comment(joined).rstrip().endswith(":"):
                    issues.append(Issue("WARN", fn, i, "R09-func-colon",
                        "func tanımı ':' ile bitmiyor olabilir"))

    # ---- KURAL 10: parantez dengesi (string/yorum hariç) ----
    for op, cl, label in [("(", ")", "()"), ("[", "]", "[]"), ("{", "}", "{}")]:
        no = code_only.count(op)
        nc = code_only.count(cl)
        if no != nc:
            issues.append(Issue("ERROR", fn, None, "R10-paren",
                f"'{label}' dengesiz: {no} açık, {nc} kapalı"))

    # ---- KURAL 11: tab + space karışık girinti (aynı satır) ----
    for i, raw in enumerate(raw_lines, 1):
        lead = raw[:len(raw) - len(raw.lstrip())]
        if "\t" in lead and " " in lead:
            issues.append(Issue("ERROR", fn, i, "R11-mixed-indent",
                "Aynı satırda tab+boşluk karışık girinti"))

    # ---- KURAL 13: çift fonksiyon tanımı (aynı dosya, top-level) ----
    # Aynı isimde iki top-level func = derleme hatası.
    seen_funcs = {}
    for i, raw in enumerate(raw_lines, 1):
        stripped = raw.lstrip()
        indent = len(raw) - len(stripped)
        m = re.match(r'(static\s+)?func\s+(\w+)\s*\(', stripped)
        if m and indent == 0:  # sadece top-level (inner class metodu değil)
            fname = m.group(2)
            if fname in seen_funcs:
                issues.append(Issue("ERROR", fn, i, "R13-dup-func",
                    "'%s' fonksiyonu zaten tanımlı (satır %d) — çift tanım"
                    % (fname, seen_funcs[fname])))
            else:
                seen_funcs[fname] = i

    # ---- KURAL 14: ad çakışması — yerleşik fonksiyon VEYA miras metodu ----
    # İki çakışma türü:
    #  (a) GDScript global yerleşikleri (sign, abs, min...) — metod
    #      çağrısı yerleşiğe yönlenir, tip uymazsa ÇALIŞMADA hata.
    #  (b) Object/RefCounted/Node miras metodları (is_connected,
    #      connect, free...) — imza uymazsa DERLEMEDE parse hatası
    #      ("signature doesn't match the parent").
    # Linter ikisini de erken yakalar.
    GDSCRIPT_BUILTINS = {
        "sign", "abs", "absf", "absi", "min", "max", "clamp", "clampf",
        "clampi", "round", "roundf", "roundi", "floor", "floorf", "floori",
        "ceil", "ceilf", "ceili", "pow", "sqrt", "lerp", "lerpf", "hash",
        "sin", "cos", "tan", "log", "exp", "fmod", "fposmod", "posmod",
        "wrapf", "wrapi", "snapped", "snappedf", "snappedi", "step_decimals",
        "is_equal_approx", "is_zero_approx", "smoothstep", "move_toward",
        "deg_to_rad", "rad_to_deg", "linear_to_db", "db_to_linear",
    }
    # Object/RefCounted/Node'dan miras gelen, çakışırsa parse hatası
    # veren metodlar. Bunlar override edilebilir AMA imza birebir
    # uymak zorunda — kazara aynı ad koymak tehlikeli.
    INHERITED_METHODS = {
        "is_connected", "connect", "disconnect", "free", "queue_free",
        "duplicate", "get", "set", "call", "has_method", "has_signal",
        "emit_signal", "get_class", "is_class", "notification",
        "to_string", "get_instance_id", "is_queued_for_deletion",
        "get_signal_list", "get_method_list", "get_property_list",
        "add_to_group", "remove_from_group", "is_in_group",
    }
    for i, raw in enumerate(raw_lines, 1):
        stripped = raw.lstrip()
        indent = len(raw) - len(stripped)
        m = re.match(r'(static\s+)?func\s+(\w+)\s*\(', stripped)
        if m and indent == 0:
            fname = m.group(2)
            if fname in GDSCRIPT_BUILTINS:
                issues.append(Issue("ERROR", fn, i, "R14-builtin-shadow",
                    "'%s' metodu GDScript yerleşik fonksiyonuyla çakışıyor "
                    % fname
                    + "— farklı bir ad kullan (örn. '%s_value')" % fname))
            elif fname in INHERITED_METHODS:
                issues.append(Issue("ERROR", fn, i, "R14-builtin-shadow",
                    "'%s' metodu Object/Node miras metoduyla çakışıyor "
                    % fname
                    + "— imza uymazsa parse hatası; farklı ad kullan"))

    return issues


def parse_enums(src):
    """Bir dosyadaki enum tanımlarını parse eder.
    Dönen: {enum_adı: set(değerler)}.
    Enum değerleri BÜYÜK_HARF; her satır yorumdan önce ayıklanır."""
    enums = {}
    cur = None
    for line in src.split("\n"):
        stripped = line.strip()
        m = re.match(r'enum\s+(\w+)\s*\{', stripped)
        if m:
            cur = m.group(1)
            enums[cur] = set()
            rest = stripped[stripped.index("{") + 1:]
            if "}" in rest:
                for p in rest[:rest.index("}")].split(","):
                    n = p.split("#")[0].split("=")[0].strip()
                    if re.match(r'^[A-Z][A-Z0-9_]*$', n):
                        enums[cur].add(n)
                cur = None
            continue
        if cur is not None:
            if "}" in stripped:
                cur = None
                continue
            code = stripped.split("#")[0]
            for p in code.split(","):
                n = p.split("=")[0].strip()
                if re.match(r'^[A-Z][A-Z0-9_]*$', n):
                    enums[cur].add(n)
    return enums


def check_enum_references(files):
    """R12 — Cross-file enum referans doğrulama.
    AIXxx.EnumName.VALUE biçimindeki referanslar gerçek enum değerlerine
    karşı doğrulanır. Olmayan değer = derleme hatası (FUNCTIONAL bug'ı gibi)."""
    # 1. class_name -> enum tablosu kur
    class_enums = {}
    for fn in files:
        try:
            src = open(fn, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        m = re.search(r'^class_name\s+(\w+)', src, re.M)
        if m:
            class_enums[m.group(1)] = parse_enums(src)

    # 2. Her dosyada ClassName.EnumName.VALUE referanslarını doğrula
    issues = []
    for fn in files:
        try:
            src = open(fn, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        for i, line in enumerate(src.split("\n"), 1):
            code = line.split("#")[0]
            for m in re.finditer(r'\b(AI\w+)\.(\w+)\.([A-Z][A-Z0-9_]*)\b', code):
                cls, mid, val = m.group(1), m.group(2), m.group(3)
                if cls in class_enums and mid in class_enums[cls]:
                    if val not in class_enums[cls][mid]:
                        valid = sorted(class_enums[cls][mid])
                        issues.append(Issue(
                            "ERROR", fn, i, "R12-enum-ref",
                            "'%s.%s.%s' — '%s' enum'da yok. Geçerli: %s"
                            % (cls, mid, val, val, valid)
                        ))
    return issues


def main():
    targets = sys.argv[1:] if len(sys.argv) > 1 else ["."]
    files = []
    for t in targets:
        if t.endswith(".gd"):
            files.append(t)
        else:
            files.extend(glob.glob(f"{t}/**/*.gd", recursive=True))
    files = sorted(set(files))

    all_issues = []
    for fn in files:
        all_issues.extend(analyze_file(fn))

    # R12 — cross-file enum doğrulama (tüm dosyalar birlikte)
    all_issues.extend(check_enum_references(files))

    errors = [x for x in all_issues if x.severity == "ERROR"]
    warns = [x for x in all_issues if x.severity == "WARN"]

    print(f"=== GDScript Statik Analiz — {len(files)} dosya ===")
    if not all_issues:
        print(f"  ✓ TEMİZ — {len(files)} dosya, 0 hata, 0 uyarı")
        return 0

    for x in all_issues:
        print(x)
    print(f"\n--- {len(errors)} HATA, {len(warns)} uyarı ---")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
