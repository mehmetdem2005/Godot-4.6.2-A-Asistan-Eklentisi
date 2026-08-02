# Godot 4.6.3 Editor Undo/Redo Smoke

Bu harness yalnız izole fixture sahnesini değiştirir. Gerçek oyun sahnelerinde çalışmaz.

## Çalıştırma

1. Godot 4.6.3 ile projeyi açın.
2. `res://tools/editor_smoke/fixture.tscn` sahnesini açın.
3. Script Editor'de `res://tools/editor_smoke/editor_undo_redo_smoke.gd` dosyasını açın.
4. **File > Run** seçeneğini kullanın veya `Ctrl+Shift+X` tuşlarına basın.
5. Output panelinde aşağıdaki sonucu arayın:

```text
SMOKE_OK: 3/3 smoke testi geçti
```

Harness şu gerçek editör işlemlerini doğrular:

- `NODE_ADD`: do → undo → redo → cleanup undo
- `PROPERTY_SET`: do → undo → redo → cleanup undo
- `SCRIPT_ATTACH`: do → undo → redo → cleanup undo

Her testten sonra fixture başlangıç durumuna döndürülür ve kaydedilir.

## Güvenlik davranışı

Açık sahne tam olarak `res://tools/editor_smoke/fixture.tscn` değilse harness `SMOKE_FAIL` ile durur ve hiçbir mutasyon yapmaz. Fixture kirliyse sahneyi diskten yeniden açıp testi tekrar çalıştırın.
