# INTERROGART — interrogatorio 3045 (Godot 4, no fotorealista)

Eres humano. Interrogas humanos y aliens en un cuarto cerrado con una sola luz,
estilo Batman vs Joker. Sacas la verdad con **evidencias + empatía**.

## Regla (igual en Godot y en prototipo web)
- Verdad 0–100%. Al 100% el sospechoso **confiesa: ganas**.
- 12 turnos. Si se acaban sin confesar, **gana el interrogado y pierdes**.
- Al pulsar **Nuevo interrogatorio** sale **otro caso al azar**.
- Presionar sin empatía rinde la mitad (se cierra). Empatía alta potencia las evidencias.

## Jugar YA (sin instalar nada)
Abre `prototipo_web/index.html` o doble clic en `probar_prototipo.bat`.

## Abrir en Godot 4 (versión 3D real)
1. Instala Godot 4.3+ (https://godotengine.org) — elige la versión normal de 64 bits.
2. Abre Godot → Importar → elige `project.godot` de esta carpeta → Abrir.
3. Pulsa ▶ (F5). Escena principal: `scenes/room3d.tscn` (cuarto 3D + UI).
   `scenes/main.tscn` es la versión solo-texto por si tu PC es muy vieja.
4. Casos en `data/sospechosos.json` — agrega más copiando el formato.
5. Lógica en `scripts/GameManager.gd`.

## Estructura
- `project.godot` → proyecto Godot 4
- `scenes/main.tscn` → escena (UI construida por código)
- `scripts/GameManager.gd` → bucle interrogatorio
- `data/sospechosos.json` → 3 casos: Vex'ahl (alien), Sara (humana), Gruul (alien jefe)
- `prototipo_web/index.html` → misma mecánica jugable en navegador
- `abrir_godot.bat` / `probar_prototipo.bat`

## Cómo diseñar tu avatar (alien/humano)

### Opción A — rápida (sin salir del proyecto, recomendada)
Cada caso en `data/sospechosos.json` tiene un bloque `avatar`. Edítalo y listo:
```json
"avatar": {
  "piel": "#8CA39A",
  "ropa": "#C24614",
  "cabeza": [0.9, 1.3, 0.95],
  "cuerpo": [0.85, 1.0, 0.85],
  "ojos": "#E8D44D",
  "ojos_tam": 1.4
}
```
- `piel` / `ropa` / `ojos`: colores en hexadecimal.
- `cabeza` / `cuerpo`: escala [x, y, z]. Ej: cabeza `[0.9, 1.3, 0.95]` = cráneo alargado.
- `ojos_tam`: 0.8 = ojos cansados, 1.4 = ojos grandes de alien.
- Las expresiones (miedo, tristeza), el sudor y la boca se adaptan solos.

### Opción B — modelos gratis (mejor acabado, sin modelar)
1. Descarga un pack CC0: **Quaternius** (quaternius.com, personajes low-poly) o **Kenney** (kenney.nl, alien/civiles).
2. Descomprime el `.glb` en una carpeta `modelos/` del proyecto.
3. En Godot: arrastra el `.glb` a la escena del sospechoso (`Sospechoso` en `Room3D`).
4. Ajusta escala a ~1.7 m de alto sentado y rota a +Z (mirando a cámara).

### Opción C — Blender (control total)
Modela tu alien, expórtalo como `.glb` y sigue el paso 3-4 de la opción B.
La lógica (`react`, `set_emotion`) sigue funcionando si conservas los nombres
de nodos: `Sospechoso`, ojos y boca.

## Modelos esculpidos (`herramientas/`, Blender 5.2)
Cada script esculpe con SDF en numpy, malla, hornea texturas (color, normal, AO) en
`modelos/tex/` y exporta el `.glb` con esqueleto. Los anima `scripts/Ilvari.gd`
(`PERFILES`); `rasgos.modelo` en la ficha elige el perfil. Si el `.glb` no existe, el
sospechoso usa el modelo procedural.

| Script | Modelo | Sospechosos |
|---|---|---|
| `construir_ilvari.py` | `ilvari.glb` | Vehl |
| `construir_kthar.py` | `kthar.glb` | Vex'ahl, Yul'Keth (teñido) |
| `construir_humano.py` | `humano_<id>.glb` (uno por personaje) | Danner, Sara, Elena |
| `construir_molk.py` | `molk.glb` (+ máscara de grietas `mlk_*_emi.png`) | Gruul |

```
blender --background --factory-startup --python herramientas/construir_humano.py -- danner sara elena previa
blender --background --factory-startup --python herramientas/construir_molk.py -- previa
```
`CALIDAD=2` construye rápido (texturas a la mitad); `previa` deja renders en `herramientas/_previa/`.

## Casos con árbol de diálogo
`data/caso_<id>.json` (`"modo": "arbol"`): `caso_vehl.json` y `caso_elena.json`. Si el id ya
existe en `sospechosos.json`, el árbol sustituye a la versión clásica. Validar:
`python herramientas/simular_arbol.py data/caso_elena.json 1500000`.
