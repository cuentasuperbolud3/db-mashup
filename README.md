# Dragon Ball in Los Santos

Configuracion del mashup para **GTA V Legacy** como juego host y **Dragon Ball: Sparking! Zero** como companion obligatorio de solo lectura.

## Rutas del workspace

- Receta: `mashup/melty.json`
- Script Lua existente: `mashup/src/dbz_abilities.lua`
- Imagen del proyecto: `mashup/0e9717-DBZ.webp`
- Fuente local del companion en la receta: `{game:custom-dragon-ball-sparking-zero}`
- Host: `gta-v`, ejecutable de Legacy `GTA5.exe`

La receta referencia los modelos, animaciones, sonidos y efectos desde la instalacion local del companion. No copia ni incluye archivos de Sparking! Zero en el paquete.

## Compatibilidad pendiente

La instalacion de desarrollo detectada es GTA V Legacy `1.0.3889.0`. El script Lua actual usa APIs FiveM/Cfx y no se ejecuta directamente con Script Hook V ni Ultimate ASI Loader. La receta marca `requires_adapter`: hace falta portar el script a un runtime compatible con Legacy antes de instalarlo, probarlo o publicar una release.

Los archivos de partidas guardadas bajo `mashup/assets/saves/` no forman parte de la receta ni se deben instalar como parte del mashup.
