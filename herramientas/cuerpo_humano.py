"""INTERROGART - los sospechosos humanos (Danner, Sara, Elena) sentados al otro lado de la mesa.
Mismo convenio que cuerpo_ilvari.py: Blender (x, y, z) = Godot (x, -z, y), mira hacia -Y,
mesa en z = 0.795 con el borde en y = -0.35. Lado -1 = x negativa = su mano DERECHA (_R).
Esqueleto con los nombres del ilvari (así lo anima Ilvari.gd) más comisura_R/L (sonrisa).
Un modelo por personaje: VARIANTES fija complexión, peinado, cicatriz y dientes; los colores
salen de su ficha (data/sospechosos.json -> rasgos), así que no hace falta teñir en Godot.
Todas las funciones reciben V = variante(id).
"""
import os
import json
import numpy as np
from sdf import (Escultura, Esfera, Elipsoide, ConoRedondo, CajaRedonda, Toro, Funcion,
                 rot_euler, rot_matriz, smoothstep, smin, smax, ruido, fbm, _v)
from cuerpo_kthar import superficie

AQUI = os.path.dirname(os.path.abspath(__file__))
FICHAS = os.path.join(os.path.dirname(AQUI), "data", "sospechosos.json")

MESA = 0.795
H = _v([0.0, -0.065, 1.265])          # centro del cráneo
P_PELVIS = _v([0.0, 0.06, 0.56])
P_LUMBAR = _v([0.0, 0.05, 0.71])
P_PECHO = _v([0.0, 0.015, 0.88])
P_CUELLO = _v([0.0, -0.02, 1.055])
P_CUELLO2 = _v([0.0, -0.033, 1.12])
P_CRANEO = H + _v([0.0, 0.02, -0.08])
P_CORONILLA = H + _v([0.0, 0.01, 0.11])
CODO_BASE = _v([0.215, -0.30, 0.865])
MUNECA_XY = _v([0.125, -0.53])
YAW_MANO = 0.2
PITCH_MANO = np.radians(3.0)
FLEX_REPOSO = (8.0, 16.0, 10.0)        # el mismo que el ilvari: Ilvari.gd resta este reposo
CADERA_J = _v([0.095, 0.045, 0.54])
RODILLA = _v([0.11, -0.33, 0.55])
TOBILLO = _v([0.12, -0.36, 0.08])
LEAN = 0.2

# regiones del mono (las mismas que el ilvari/kthar)
R_TORSO_B, R_TORSO_A, R_HOMBRO, R_BRAZO, R_ANTEBRAZO, R_CUELLO_T, R_PIERNA = 1, 2, 3, 4, 5, 6, 7
# regiones de la piel
R_CUELLO, R_CABEZA, R_MANDIBULA, R_OREJA, R_CEJA, R_LABIO = 20, 21, 22, 23, 24, 26

# rasgos de la cara (relativos a H)
OJO = _v([0.0315, -0.0835, -0.022])
R_OJO = 0.0122
BOCA_Z = -0.083
COMISURA = _v([0.0235, -0.1, BOCA_Z])
CEJA = _v([0.03, -0.095, 0.006])
BISAGRA = H + _v([0.0, 0.0, -0.045])
MENTON = H + _v([0.0, -0.09, -0.118])

# ----------------------------------------------------------------------- variantes

VARIANTES = {
    # 38 años, flaco y fibroso; cara chupada, pelo grasiento hacia atrás, sonrisa de Glasgow
    # cosida, dientes podridos, barba de tres días y ojeras.
    "danner": dict(genero="m", hombro=0.172, cadera=1.0, cuello=1.0, flaco=1.0, mandibula=1.0, nariz=1.12,
                   labios=0.85, pecho=0.0, edad=0.55, ojeras=0.85, barba=0.65, mano=1.0,
                   cara=1.0, pelo="grasiento", cicatriz="sonrisa", dientes="podridos"),
    # 34 años, ex piloto: cara angulosa y fría, pelo negro largo, cicatriz cosida que le cruza
    # el ojo izquierdo, dientes limados en punta.
    "sara": dict(genero="f", hombro=0.158, cadera=1.06, cuello=0.86, flaco=0.55, mandibula=0.84, nariz=0.86,
                 labios=1.0, pecho=0.9, edad=0.25, ojeras=0.45, barba=0.0, mano=0.93,
                 cara=0.92, pelo="largo", cicatriz="ojo", dientes="afilados"),
    # 41 años, enfermera jefe: cara suave y maternal, moño, una cicatriz vieja en la mejilla
    # derecha y una sonrisa demasiado fácil.
    "elena": dict(genero="f", hombro=0.162, cadera=1.1, cuello=0.88, flaco=0.0, mandibula=0.86, nariz=0.9,
                  labios=1.05, pecho=1.1, edad=0.7, ojeras=0.3, barba=0.0, mano=0.92,
                  cara=0.97, pelo="moño", cicatriz="mejilla", dientes="normal"),
}


def lineal(hexa, defecto=(0.5, 0.5, 0.5)):
    """'#RRGGBB' (sRGB, como en el JSON) -> color lineal (lo que se hornea)."""
    if not hexa:
        return _v(defecto)
    s = str(hexa).lstrip("#")
    c = np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4).astype(np.float32)


def variante(ident):
    """Variante + ficha del JSON + colores lineales derivados."""
    V = dict(VARIANTES[ident])
    V["id"] = ident
    r = {}
    if os.path.exists(FICHAS):
        with open(FICHAS, encoding="utf-8") as f:
            for s in json.load(f)["sospechosos"]:
                if s["id"] == ident:
                    r = s.get("rasgos", {})
    V["ficha"] = r
    V["PIEL"] = lineal(r.get("piel"), (0.45, 0.32, 0.24))
    V["MANCHA"] = lineal(r.get("mancha"), (0.2, 0.1, 0.08))
    V["VENA"] = lineal(r.get("vena"), (0.08, 0.06, 0.15))
    V["ROPA"] = lineal(r.get("ropa"), (0.45, 0.07, 0.007))
    V["MANCHA_ROPA"] = lineal(r.get("mancha_ropa"), (0.02, 0.005, 0.002))
    V["PELO"] = lineal(r.get("pelo"), (0.01, 0.008, 0.006))
    V["LABIO"] = lineal(r.get("labios")) if r.get("labios") else V["PIEL"] * _v([0.75, 0.48, 0.45])
    V["UNA"] = lineal(r.get("unas"), (0.5, 0.35, 0.3))
    V["DIENTE"] = lineal(r.get("dientes_color"), (0.75, 0.7, 0.6))
    V["manchas"] = float(r.get("manchas", 0.4))
    V["venas"] = float(r.get("venas", 0.4))
    V["suciedad"] = float(r.get("suciedad", 0.2))
    V["puntadas"] = bool(r.get("puntadas", False))
    cab = r.get("cabeza", [1.0, 1.0, 1.0])
    # la ficha exagera (es para el modelo procedural): aquí solo un matiz
    V["cab"] = _v([float(cab[0]) ** 0.5, float(cab[2]) ** 0.5, float(cab[1]) ** 0.5])   # ancho, fondo, alto
    V["semilla"] = int(r.get("semilla", 5))
    return V


def h(x, y, z):
    return H + _v([x, y, z])


def espejo(p, lado):
    return _v([p[0] * lado, p[1], p[2]])


def hombro(V):
    return _v([V["hombro"], -0.045, 1.035])


def codo(V):
    return CODO_BASE + _v([V["hombro"] - 0.172, 0.0, 0.0])


def ojo(s):
    return h(OJO[0] * s, OJO[1], OJO[2])


# ----------------------------------------------------------------------- manos

def mano_transform(lado):
    """La mano local (mano.py) es derecha, dedos +Y y pulgar hacia -X. Para lado -1 los dedos
    apuntan a -Y y un poco hacia el centro; lado +1 se obtiene reflejando X."""
    return rot_matriz((0, 0, 1), np.pi + YAW_MANO) @ rot_matriz((1, 0, 0), PITCH_MANO)


def muneca(lado, z):
    return _v([MUNECA_XY[0] * lado, MUNECA_XY[1], z])


def a_mundo(v_local, lado, W):
    R = mano_transform(-1)
    p = np.asarray(v_local, np.float32) @ R.T
    p = p + _v([-MUNECA_XY[0], MUNECA_XY[1], W])
    if lado > 0:
        p = p * _v([-1, 1, 1])
    return p


def altura_muneca(v_local):
    R = mano_transform(-1)
    z = (np.asarray(v_local, np.float32) @ R.T)[:, 2]
    return MESA + 0.0015 - z.min()


def puno(V, lado, W):
    """Final de la manga, un poco antes de la muñeca."""
    c = espejo(codo(V), lado)
    d = (W - c) / np.linalg.norm(W - c)
    return W - d * 0.03


def colores_mano(V, v, reg, n, A):
    import mano as M
    c = M.colores(v, reg, n, A, piel=tuple(V["PIEL"] * 1.05), escala=V["mano"])
    # mugre en los nudillos y alrededor de las uñas, manchas de la piel
    e = V["mano"]
    mug = smoothstep(0.0, 0.4, fbm(v / e * 60.0, 3, 41))[:, None] * V["suciedad"] * 0.5
    for f in range(5):
        tip = A[f][3]
        w = np.exp(-(np.linalg.norm(v - tip, axis=1) / (0.012 * e)) ** 2)[:, None] * V["suciedad"] * 0.6
        mug = np.maximum(mug, w)
    c = c * (1 - mug) + _v([0.06, 0.045, 0.03]) * mug
    man = smoothstep(0.15, 0.4, fbm(v / e * 35.0, 3, 9))[:, None] * V["manchas"] * 0.3 * smoothstep(-0.3, 0.5, n[:, 2])[:, None]
    c = c * (1 - man) + V["MANCHA"] * man
    return np.clip(c, 0, 1)


# ----------------------------------------------------------------------- mono del penal

def _torso(S, V, inflar=0.0, k=1.0):
    L = rot_euler(LEAN, 0, 0)
    a = V["hombro"] / 0.172
    ca = V["cadera"]
    S.add(Elipsoide((0, 0.06, 0.6), (0.158 * ca + inflar, 0.118 + inflar, 0.1 + inflar), R_TORSO_B), 0.0)
    S.add(Elipsoide((0, 0.04, 0.74), (0.13 * a + inflar, 0.092 + inflar, 0.12 + inflar), R_TORSO_B, rot=L), 0.07 * k)
    S.add(Elipsoide((0, 0.005, 0.9), (0.148 * a + inflar, 0.098 + inflar, 0.14 + inflar), R_TORSO_A, rot=L), 0.07 * k)
    hm = hombro(V)
    S.add(ConoRedondo(espejo(hm, -1) + _v([0.035, 0.0, -0.012]), hm + _v([-0.035, 0.0, -0.012]), 0.046 + inflar, 0.046 + inflar,
                      R_HOMBRO, aplastar=(1.0, 0.82), arriba=(0, -0.3, 1)), 0.06 * k)
    if V["pecho"] > 0:
        b = V["pecho"]
        for s in (-1, 1):
            S.add(Elipsoide((0.052 * s, -0.082, 0.925), (0.048 * b + inflar, 0.036 * b + inflar, 0.042 * b + inflar), R_TORSO_A,
                            rot=rot_euler(LEAN, 0, 0.25 * s)), 0.04 * k)


def mono(V, W_R, W_L):
    S = Escultura(banda=0.016)
    _torso(S, V, inflar=0.004)
    for lado, W in ((-1, W_R), (1, W_L)):
        hm = espejo(hombro(V), lado)
        c = espejo(codo(V), lado)
        pe = puno(V, lado, W)
        S.add(Esfera(hm + _v([0.006 * lado, 0.0, 0.004]), 0.05, R_HOMBRO), 0.035)
        S.add(ConoRedondo(hm, c, 0.046, 0.041, R_BRAZO), 0.03)
        S.add(ConoRedondo(c, pe, 0.041, 0.035, R_ANTEBRAZO, aplastar=(1.0, 0.82), arriba=(0, 0, 1)), 0.022)
        d = (pe - c) / np.linalg.norm(pe - c)
        S.add(ConoRedondo(pe - d * 0.022, pe, 0.036, 0.034, R_ANTEBRAZO, aplastar=(1.0, 0.8), arriba=(0, 0, 1)), 0.006)
        S.sub(ConoRedondo(pe - d * 0.05, pe + d * 0.03, 0.029, 0.029, aplastar=(1.0, 0.78), arriba=(0, 0, 1)), 0.003)
        S.add(ConoRedondo(espejo(CADERA_J, lado), espejo(RODILLA, lado), 0.085 * V["cadera"], 0.066, R_PIERNA), 0.05)
        S.add(ConoRedondo(espejo(RODILLA, lado), espejo(TOBILLO, lado), 0.062, 0.056, R_PIERNA), 0.02)
    rc = 0.052 * V["cuello"]
    S.add(ConoRedondo(_v([0, -0.012, 1.0]), _v([0, -0.024, 1.085]), rc + 0.022, rc + 0.017, R_CUELLO_T), 0.03)
    S.sub(ConoRedondo(_v([0, -0.005, 0.96]), _v([0, -0.05, 1.22]), rc + 0.005, rc + 0.003), 0.004)
    # bolsillo en el pecho derecho (x < 0) con solapa
    S.add(CajaRedonda(_v([-0.072, -0.108, 0.915]), (0.028, 0.004, 0.032), 0.002, R_TORSO_A, rot=rot_euler(LEAN * 0.8, 0, 0)), 0.004)
    S.add(CajaRedonda(_v([-0.072, -0.117, 0.946]), (0.03, 0.004, 0.009), 0.002, R_TORSO_A, rot=rot_euler(LEAN * 0.8, 0, 0)), 0.002)
    S.sub(CajaRedonda((0, -0.2, -0.05), (0.6, 0.6, 0.06), 0.0), 0.0)
    S.desplazar.append(_detalle_mono(V, W_R, W_L))
    return S


def _cremallera(p):
    frente = smoothstep(0.0, -0.08, p[:, 1])
    return smoothstep(0.006, 0.003, np.abs(p[:, 0])) * frente * (p[:, 2] > 0.62) * (p[:, 2] < 1.07)


def _detalle_mono(V, W_R, W_L):
    def fn(p, d, reg):
        out = np.zeros(len(p), np.float32)
        out += _cremallera(p) * (0.0012 + 0.0004 * np.sign(np.sin(p[:, 2] * 1400.0)))
        out -= 0.0008 * np.exp(-((p[:, 2] - 1.083) / 0.002) ** 2) * (p[:, 2] < 1.11)
        for lado in (-1, 1):
            c = espejo(codo(V), lado)
            dd = np.linalg.norm(p - c, axis=1)
            fold = np.sin((p[:, 1] * 0.7 + p[:, 2] * 0.7) * 160.0 + ruido(p * 14.0, 4) * 3.0)
            out += 0.0026 * fold * np.exp(-(dd / 0.08) ** 2)
            W = W_R if lado < 0 else W_L
            dc = np.linalg.norm(p - W, axis=1)
            out += 0.0011 * np.sin(p[:, 1] * 300.0 + ruido(p * 28.0, 9) * 2.0) * np.exp(-(dc / 0.055) ** 2)
            ax = np.linalg.norm(p - espejo(hombro(V), lado) - _v([-0.03 * lado, 0.0, -0.07]), axis=1)
            out += 0.0016 * np.sin(p[:, 2] * 220.0 + p[:, 1] * 80.0) * np.exp(-(ax / 0.055) ** 2)
        out += 0.0022 * np.sin(p[:, 2] * 90.0 + ruido(p * 10.0, 3) * 4.0) * smoothstep(0.8, 0.66, p[:, 2]) * smoothstep(0.45, 0.62, p[:, 2])
        out += 0.0009 * fbm(p * 9.0, 3, 31) + 0.00012 * ruido(p * 600.0, 2)
        return out
    return fn


def colores_mono(V, v):
    base = np.tile(V["ROPA"], (len(v), 1))
    base *= (1.0 + fbm(v * 14.0, 3, 7)[:, None] * 0.22)
    base = base * 0.88 + V["ROPA"] * _v([1.1, 1.5, 2.0]) * 0.12 * smoothstep(0.0, 0.3, fbm(v * 6.0, 2, 44))[:, None]
    # manchas (color de la ficha) en puños, vientre y regazo, según lo sucio que vaya
    zona = np.clip(smoothstep(0.92, 0.78, v[:, 2]) * smoothstep(-0.15, -0.4, v[:, 1]) * 0.9
                   + smoothstep(0.6, 0.85, v[:, 2]) * 0.3, 0, 1)
    g = smoothstep(0.12, 0.38, fbm(v * _v([20.0, 20.0, 28.0]), 4, 51))[:, None] * zona[:, None] * (0.3 + V["suciedad"])
    g = np.clip(g, 0, 0.9)
    base = base * (1 - g) + V["MANCHA_ROPA"] * g
    sp = smoothstep(0.64, 0.7, ruido(v * 90.0, 61))[:, None] * 0.35 * V["suciedad"]
    base = base * (1 - sp) + V["MANCHA_ROPA"] * sp
    cz = _cremallera(v)[:, None]
    base = base * (1 - cz) + _v([0.07, 0.065, 0.06]) * cz
    rib = (smoothstep(1.075, 1.083, v[:, 2]) * (v[:, 2] < 1.12))[:, None] * 0.45
    base = base * (1 - rib) + V["ROPA"] * 0.5 * rib
    return np.clip(base, 0, 1)


def placa_pos(S):
    """Punto del pecho izquierdo (x > 0) donde va la placa de preso, y su normal."""
    p = superficie(S, _v([0.07, 0.0, 0.95]), (0, -1, 0.0), 0.3, 0.001)
    e = 0.002
    g = _v([S.evaluar((p + _v(dx))[None])[0] - S.evaluar((p - _v(dx))[None])[0]
            for dx in ((e, 0, 0), (0, e, 0), (0, 0, e))])
    return p, g / np.linalg.norm(g)


# ----------------------------------------------------------------------- cabeza

def _forma(S, V):
    """Volúmenes de cabeza y cuello sin agujeros ni detalle (sirve también para el pelo)."""
    m = V["mandibula"]
    fl = V["flaco"]
    fem = V["genero"] == "f"
    cx, cy, cz = V["cab"]
    n = V["nariz"]
    rc = 0.052 * V["cuello"]
    S.add(ConoRedondo(P_CUELLO + _v([0, 0.012, -0.07]), P_CRANEO + _v([0, 0.0, 0.03]), rc, rc * 0.93, R_CUELLO), 0.0)
    for s in (-1, 1):
        # esternocleidomastoideo: de detrás de la oreja al esternón
        S.add(ConoRedondo(h(0.054 * s, 0.012, -0.065), _v([0.013 * s, -0.062, 1.045]), 0.0105 * V["cuello"], 0.009, R_CUELLO), 0.016)
    if not fem:
        S.add(Elipsoide(_v([0, -0.071, 1.115]), (0.009, 0.008, 0.012), R_CUELLO), 0.012)
    # cráneo y frente
    S.add(Elipsoide(h(0, 0.008, 0.008), (0.073 * cx, 0.095 * cy, 0.094 * cz), R_CABEZA), 0.03)
    S.add(Elipsoide(h(0, -0.05, 0.022), (0.06 * cx, 0.045, 0.056), R_CABEZA), 0.03)
    # tercio inferior de la cara, mejillas y hocico
    ca = V["cara"]
    S.add(Elipsoide(h(0, -0.045, -0.058), (0.056 * ca, 0.058, 0.062), R_CABEZA), 0.035)
    S.add(Elipsoide(h(0, -0.081, -0.068), (0.03, 0.026, 0.027), R_CABEZA), 0.02)
    for s in (-1, 1):
        # pómulo y arco cigomático
        S.add(Elipsoide(h(0.046 * s * ca, -0.07, -0.033 + 0.004 * (1 - ca) / 0.08), (0.015, 0.018, 0.0105 + 0.0015 * fl), R_CABEZA, rot=rot_euler(0, 0, 0.5 * s)), 0.02)
        S.add(ConoRedondo(h(0.05 * s, -0.062, -0.034), h(0.062 * s, -0.012, -0.038), 0.0052, 0.0045, R_CABEZA), 0.014)
        # almohadilla de la mejilla (cara llena; se pierde en las caras chupadas)
        if fl < 0.9:
            S.add(Elipsoide(h(0.04 * s, -0.072, -0.056), tuple(_v([0.016, 0.013, 0.016]) * (1.0 - 0.4 * fl)), R_CABEZA), 0.022)
        # mandíbula: rama y cuerpo hasta el mentón
        ang = h(0.055 * m * s, -0.006, -0.088 + 0.004 * (1 - m))
        S.add(ConoRedondo(h(0.058 * s, 0.004, -0.04), ang, 0.011, 0.012 * m, R_MANDIBULA), 0.02)
        S.add(ConoRedondo(ang, h(0.021 * s, -0.078, -0.115), 0.012 * m, 0.0105, R_MANDIBULA), 0.02)
        # masetero: rellena el hueco entre el pómulo y el ángulo de la mandíbula
        S.add(ConoRedondo(h(0.054 * s, -0.035, -0.042), h(0.054 * m * s, -0.02, -0.084), 0.012, 0.0125, R_CABEZA), 0.02)
        # arco superciliar (más marcado en él)
        S.add(ConoRedondo(h(0.008 * s, -0.093, -0.001), h(0.051 * s, -0.078, 0.004), 0.0095 if not fem else 0.0066, 0.0068 if not fem else 0.0058, R_CEJA), 0.014)
        # oreja: pabellón aplastado, lóbulo y trago
        S.add(Elipsoide(h(0.073 * s, 0.005, -0.03), (0.0075, 0.019, 0.029), R_OREJA, rot=rot_euler(0.12, 0.0, -0.35 * s)), 0.005)
        S.add(Esfera(h(0.072 * s, 0.001, -0.055), 0.0068, R_OREJA), 0.005)
        S.add(Esfera(h(0.07 * s, -0.012, -0.034), 0.0042, R_OREJA), 0.004)
        # nariz: aletas
        S.add(Elipsoide(h(0.0104 * s * n, -0.106, -0.062), (0.0064 * n, 0.0082, 0.0062), R_CABEZA), 0.006)
    S.add(Elipsoide(h(0, -0.088, -0.112), (0.0195 * (0.88 if fem else 1.0), 0.014, 0.016), R_MANDIBULA), 0.014)
    S.add(Esfera(h(0, -0.093, -0.005), 0.0098, R_CEJA), 0.012)
    # nariz: tabique y punta
    S.add(ConoRedondo(h(0, -0.097, -0.014), h(0, -0.114 - 0.004 * n, -0.054), 0.0062 * n, 0.0082 * n, R_CABEZA), 0.012)
    S.add(Elipsoide(h(0, -0.115 - 0.004 * n, -0.057), (0.0088 * n, 0.0095, 0.0092), R_CABEZA), 0.006)
    # labios
    lb = V["labios"]
    S.add(Elipsoide(h(0, -0.1005, BOCA_Z + 0.0052), (0.0215 * lb, 0.0082, 0.0052 * lb), R_LABIO, rot=rot_euler(-0.25, 0, 0)), 0.004)
    S.add(Elipsoide(h(0, -0.0985, BOCA_Z - 0.0066), (0.0195 * lb, 0.0085, 0.0062 * lb), R_LABIO, rot=rot_euler(0.3, 0, 0)), 0.004)
    # mejillas chupadas
    if fl > 0:
        for s in (-1, 1):
            S.sub(Esfera(h(0.086 * s, -0.066, -0.071), 0.03 - 0.003 * fl), 0.02)


def _ojos_y_boca(S, V):
    """Párpados (una esfera hueca con la ranura abierta), boca, fosas y oídos."""
    for s in (-1, 1):
        c = ojo(s)
        tilt = 0.08 * s if V["genero"] == "f" else 0.04 * s
        S.sub(Elipsoide(c + _v([0.0016 * s, -0.012, 0.001]), (0.0185, 0.012, 0.0135)), 0.006)
        # párpados: una esfera 2,6 mm mayor que el ojo (gruesa para que la decimación no la rompa)
        S.add(Esfera(c, R_OJO + 0.0026, R_CABEZA), 0.003)
        S.sub(Elipsoide(c + _v([0.0005 * s, -0.013, -0.0003]), (0.0132, 0.0095, 0.0043), rot=rot_euler(0, -tilt, 0)), 0.001)
        # fosas nasales y conducto del oído
        S.sub(Elipsoide(h(0.006 * s * V["nariz"], -0.111, -0.0668), (0.0028, 0.0044, 0.0021), rot=rot_euler(0.3, 0, 0.3 * s)), 0.0015)
        S.sub(Elipsoide(h(0.077 * s, -0.004, -0.032), (0.004, 0.009, 0.012), rot=rot_euler(0, 0, -0.35 * s)), 0.003)
        S.sub(Esfera(h(0.072 * s, -0.004, -0.034), 0.0028), 0.002)
    S.sub(Elipsoide(h(0, -0.108, BOCA_Z), (0.0235 * V["labios"], 0.013, 0.0009)), 0.0008)
    S.sub(cavidad_boca(), 0.003)


def cavidad_boca():
    return Elipsoide(h(0, -0.087, BOCA_Z - 0.004), (0.021, 0.022, 0.011))


def cabeza(V):
    S = Escultura(banda=0.0025)
    _forma(S, V)
    _ojos_y_boca(S, V)
    S.desplazar.append(_detalle_piel(V))
    return S


_FORMA = {}


def forma(V):
    """Cabeza sin detalle (cacheada): la usan el pelo y los colores."""
    if V["id"] not in _FORMA:
        S = Escultura()
        _forma(S, V)
        _FORMA[V["id"]] = S
    return _FORMA[V["id"]]


# --- cicatrices: polilíneas sobre la piel (relativas a H)

def cicatriz(V):
    t = V["cicatriz"]
    if t == "sonrisa":
        return [[h(0.024 * s, -0.103, BOCA_Z + 0.001), h(0.037 * s, -0.096, -0.075), h(0.05 * s, -0.082, -0.063),
                 h(0.062 * s, -0.06, -0.05), h(0.069 * s, -0.035, -0.046)] for s in (-1, 1)]
    if t == "ojo":
        # ojo izquierdo (x > 0): de la ceja al pómulo, cruzando los párpados
        return [[h(0.024, -0.091, 0.03), h(0.028, -0.097, 0.012), h(0.031, -0.1, -0.004), h(0.033, -0.1, -0.022),
                 h(0.035, -0.099, -0.038), h(0.038, -0.093, -0.055)]]
    if t == "mejilla":
        return [[h(-0.041, -0.089, -0.03), h(-0.05, -0.081, -0.045), h(-0.058, -0.07, -0.061)]]
    return []


def _dist_polilinea(p, pts):
    """Distancia a la polilínea y parámetro (longitud de arco) del punto más cercano."""
    mejor = np.full(len(p), 1e3, np.float32)
    arco = np.zeros(len(p), np.float32)
    lado = np.zeros((len(p), 3), np.float32)
    acum = 0.0
    for a, b in zip(pts[:-1], pts[1:]):
        ab = b - a
        L = float(np.linalg.norm(ab))
        t = np.clip(((p - a) @ ab) / (L * L), 0, 1)
        q = a + t[:, None] * ab
        d = np.linalg.norm(p - q, axis=1)
        m = d < mejor
        mejor = np.where(m, d, mejor)
        arco = np.where(m, acum + t * L, arco)
        lado = np.where(m[:, None], p - q, lado)
        acum += L
    return mejor, arco, lado


def _detalle_piel(V):
    edad = V["edad"]
    cics = cicatriz(V)
    vieja = V["cicatriz"] == "mejilla"

    def fn(p, d, reg):
        q = p - H
        out = 0.00011 * fbm(p * 420.0, 2, 8) + 0.00004 * ruido(p * 1500.0, 3)
        # arrugas de la frente
        frente = smoothstep(0.012, 0.03, q[:, 2]) * smoothstep(0.065, 0.045, q[:, 2]) * smoothstep(-0.07, -0.09, q[:, 1]) \
            * smoothstep(0.045, 0.025, np.abs(q[:, 0]))
        out -= 0.0003 * (0.3 + edad) * frente * np.maximum(np.sin(q[:, 2] * 700.0 + ruido(p * 50.0, 4) * 1.2), 0.0) ** 4
        # entrecejo
        out -= 0.0003 * edad * np.exp(-((q[:, 0] / 0.008) ** 2 + ((q[:, 2] + 0.002) / 0.008) ** 2)) * smoothstep(-0.085, -0.095, q[:, 1]) \
            * np.maximum(np.sin(q[:, 0] * 900.0), 0) ** 2
        for s in (-1, 1):
            o = q - _v([OJO[0] * s, OJO[1], OJO[2]])
            # pliegue del párpado superior
            r = np.linalg.norm(o / _v([0.016, 0.03, 0.0125]), axis=1)
            out -= 0.00045 * np.exp(-((r - 1.0) / 0.08) ** 2) * (o[:, 2] > 0.004)
            # bolsas bajo los ojos y patas de gallo
            bol = np.exp(-(((o[:, 2] + 0.016) / 0.005) ** 2 + ((o[:, 0] * s - 0.002) / 0.012) ** 2)) * (o[:, 1] < -0.004)
            out += 0.0005 * (0.4 + V["ojeras"]) * bol
            out -= 0.0003 * (0.4 + V["ojeras"]) * np.exp(-((o[:, 2] + 0.0225) / 0.0022) ** 2) * smoothstep(0.016, 0.006, np.abs(o[:, 0] * s - 0.002)) * (o[:, 1] < -0.004)
            pata = smoothstep(0.012, 0.018, o[:, 0] * s) * smoothstep(0.03, 0.02, o[:, 0] * s) * smoothstep(0.016, 0.0, np.abs(o[:, 2]))
            out -= 0.00025 * edad * pata * np.maximum(np.sin(np.arctan2(o[:, 2], o[:, 0] * s) * 30.0), 0) ** 3
            # surco nasogeniano (de la aleta de la nariz a la comisura)
            a = h(0.017 * s, -0.104, -0.062)
            b = h(0.031 * s, -0.097, -0.094)
            ab = b - a
            t = np.clip(((p - a) @ ab) / float(ab @ ab), 0, 1)
            dn = np.linalg.norm(p - (a + t[:, None] * ab), axis=1)
            out -= 0.0009 * (0.35 + edad + 0.5 * V["flaco"]) * np.exp(-(dn / 0.0028) ** 2)
            # comisuras hundidas
            out -= 0.0005 * np.exp(-(np.linalg.norm(q - _v([0.026 * s, -0.1, BOCA_Z]), axis=1) / 0.003) ** 2)
        # filtrum: dos crestas suaves sobre el labio
        fil = smoothstep(BOCA_Z + 0.008, BOCA_Z + 0.012, q[:, 2]) * smoothstep(-0.058, -0.064, q[:, 2]) * (q[:, 1] < -0.097)
        out += 0.0004 * fil * (np.exp(-((np.abs(q[:, 0]) - 0.0045) / 0.0018) ** 2) - 0.6 * np.exp(-(q[:, 0] / 0.002) ** 2))
        # labios: grietas verticales
        lab = (reg == R_LABIO) if reg is not None else np.zeros(len(p), bool)
        out -= 0.00012 * lab * np.maximum(np.sin(q[:, 0] * 1300.0 + ruido(p * 200.0, 6) * 2.0), 0) ** 2
        # cuello: pliegues horizontales
        cu = smoothstep(-0.11, -0.14, q[:, 2]) * smoothstep(1.06, 1.1, p[:, 2]) * smoothstep(-0.03, -0.06, q[:, 1])
        out -= 0.0003 * (0.4 + edad) * cu * np.maximum(np.sin(p[:, 2] * 380.0 + ruido(p * 30.0, 2)), 0) ** 4
        # cicatrices: cordón en relieve (hundido si es vieja) y puntadas cruzadas
        for pts in cics:
            dc, arco, lado = _dist_polilinea(p, pts)
            if vieja:
                out -= 0.0005 * np.exp(-(dc / 0.0016) ** 2)
            else:
                out += 0.0007 * np.exp(-(dc / 0.0015) ** 2) - 0.0003 * np.exp(-((dc - 0.0028) / 0.0012) ** 2)
                if V["puntadas"]:
                    paso = 0.0045
                    fase = np.abs(((arco + paso * 0.5) % paso) - paso * 0.5)
                    out += 0.0006 * np.exp(-(fase / 0.0006) ** 2) * smoothstep(0.0042, 0.003, dc)
        return out
    return fn


def colores_cabeza(V, v, n):
    q = v - H
    P = V["PIEL"]
    c = np.tile(P, (len(v), 1))
    c *= 1.0 + fbm(v * 45.0, 3, 5)[:, None] * 0.07
    rojo = P * _v([1.18, 0.78, 0.74])
    # rojeces: mejillas, nariz, orejas, párpados
    w = np.zeros(len(v), np.float32)
    for s in (-1, 1):
        w = np.maximum(w, np.exp(-(np.linalg.norm(q - _v([0.042 * s, -0.08, -0.05]), axis=1) / 0.02) ** 2) * 0.5)
        w = np.maximum(w, np.exp(-(np.linalg.norm(q - _v([0.074 * s, 0.002, -0.03]), axis=1) / 0.022) ** 2) * 0.6)
        w = np.maximum(w, np.exp(-(np.linalg.norm((q - _v([OJO[0] * s, OJO[1] - 0.008, OJO[2]])) / _v([0.016, 0.01, 0.011]), axis=1)) ** 2) * 0.45)
    w = np.maximum(w, np.exp(-(np.linalg.norm(q - _v([0, -0.117, -0.056]), axis=1) / 0.014) ** 2) * 0.5)
    c = c * (1 - w[:, None]) + rojo * w[:, None]
    # manchas de la piel (color de la ficha)
    man = smoothstep(0.12, 0.35, fbm(v * 28.0, 3, 9))[:, None] * V["manchas"] * 0.35
    c = c * (1 - man) + V["MANCHA"] * man
    # venas en sienes y párpados
    nv = ruido(v * _v([60.0, 30.0, 60.0]) + fbm(v * 30.0, 2, 3)[:, None] * 0.3, 17)
    zona = np.clip(smoothstep(0.05, 0.068, np.abs(q[:, 0])) * smoothstep(-0.05, 0.0, q[:, 2]) * smoothstep(0.04, -0.02, q[:, 1]), 0, 1)
    vena = smoothstep(0.035, 0.0, np.abs(nv))[:, None] * 0.25 * V["venas"] * zona[:, None]
    c = c * (1 - vena) + V["VENA"] * vena
    # ojeras
    for s in (-1, 1):
        o = q - _v([OJO[0] * s, OJO[1], OJO[2]])
        oj = np.exp(-(((o[:, 2] + 0.016) / 0.008) ** 2 + ((o[:, 0] * s) / 0.016) ** 2)) * (o[:, 1] < 0.0)
        c = c * (1 - oj[:, None] * 0.55 * V["ojeras"]) + _v([0.09, 0.05, 0.07]) * oj[:, None] * 0.55 * V["ojeras"]
        # borde húmedo del párpado (dentro de la ranura)
        rb = np.linalg.norm((o - _v([0, -0.013, -0.0003])) / _v([0.0136, 0.0105, 0.0048]), axis=1)
        b = smoothstep(1.12, 0.97, rb)
        arriba = (o[:, 2] > -0.0003)
        c = c * (1 - (b * 0.5 * ~arriba)[:, None]) + _v([0.3, 0.08, 0.07]) * (b * 0.5 * ~arriba)[:, None]
        pest = b * arriba * (0.85 if V["genero"] == "f" else 0.65)
        c = c * (1 - pest[:, None]) + _v([0.012, 0.01, 0.01]) * pest[:, None]
    # cejas: trazos del color del pelo, hacia fuera
    ce = np.zeros(len(v), np.float32)
    for s in (-1, 1):
        x = q[:, 0] * s
        zc = 0.004 + 0.011 * np.sin(np.clip((x - 0.008) / 0.045, 0, 1) * np.pi * 0.85) - 0.002 * (x > 0.04)
        grosor = (0.0055 if V["genero"] == "m" else 0.0036) * (1.0 - 0.45 * smoothstep(0.02, 0.05, x))
        banda = smoothstep(grosor, grosor * 0.4, np.abs(q[:, 2] - zc)) * smoothstep(0.006, 0.011, x) * smoothstep(0.056, 0.046, x)
        trazo = 0.72 + 0.28 * np.sin(x * 4200.0 + q[:, 2] * 1600.0 + ruido(v * 500.0, 5) * 3.0) * (0.5 + 0.5 * ruido(v * 900.0, 6))
        ce = np.maximum(ce, banda * trazo * (q[:, 1] < -0.06))
    c = c * (1 - ce[:, None] * 0.85) + V["PELO"] * ce[:, None] * 0.85
    # barba de tres días
    if V["barba"] > 0:
        cara_baja = smoothstep(-0.055, -0.075, q[:, 2]) * smoothstep(-0.03, -0.06, q[:, 1]) * smoothstep(1.075, 1.12, v[:, 2])
        bigote = np.exp(-(((q[:, 2] - (BOCA_Z + 0.012)) / 0.006) ** 2)) * smoothstep(0.03, 0.02, np.abs(q[:, 0])) * (q[:, 1] < -0.09)
        sin_labio = smoothstep(0.004, 0.008, np.abs(q[:, 2] - BOCA_Z + 0.001))
        pelillo = smoothstep(0.1, 0.6, ruido(v * 900.0, 77))
        b = np.clip(cara_baja + bigote, 0, 1) * sin_labio * (0.45 + 0.55 * pelillo) * V["barba"] * 0.7
        c = c * (1 - b[:, None]) + V["PELO"] * b[:, None]
    # mugre: frente, cuello y orejas
    sucio = smoothstep(0.1, 0.4, fbm(v * 18.0, 3, 33))[:, None] * V["suciedad"] * 0.35
    c = c * (1 - sucio) + _v([0.05, 0.04, 0.03]) * sucio
    # labios
    lab = np.zeros(len(v), np.float32)
    for zc, rx, rz in ((BOCA_Z + 0.0052, 0.0215, 0.0062), (BOCA_Z - 0.0068, 0.0195, 0.0072)):
        lab = np.maximum(lab, smoothstep(1.1, 0.85, np.linalg.norm((q - _v([0, -0.101, zc])) / _v([rx * V["labios"], 0.014, rz * V["labios"]]), axis=1)))
    c = c * (1 - lab[:, None]) + V["LABIO"] * lab[:, None]
    # cicatrices: tejido pálido y algo morado; puntadas de hilo negro
    for pts in cicatriz(V):
        dc, arco, _ = _dist_polilinea(v, pts)
        cc = smoothstep(0.0035, 0.001, dc)[:, None] * (0.5 if V["cicatriz"] == "mejilla" else 0.85)
        c = c * (1 - cc) + (P * _v([1.25, 0.9, 1.0]) + _v([0.04, 0.0, 0.03])) * cc
        if V["puntadas"]:
            paso = 0.0045
            fase = np.abs(((arco + paso * 0.5) % paso) - paso * 0.5)
            hilo = (smoothstep(0.0009, 0.0004, fase) * smoothstep(0.0045, 0.0032, dc))[:, None]
            c = c * (1 - hilo) + _v([0.02, 0.012, 0.01]) * hilo
    # interior de la boca, fosas y oídos
    dentro = smoothstep(0.002, -0.002, cavidad_boca().dist(v) - 0.002)[:, None]
    c = c * (1 - dentro) + _v([0.12, 0.02, 0.025]) * dentro
    for s in (-1, 1):
        for pt, r in (((0.006 * s * V["nariz"], -0.111, -0.0668), 0.0045), ((0.075 * s, -0.004, -0.032), 0.007)):
            w = smoothstep(r, r * 0.3, np.linalg.norm(q - _v(pt), axis=1))[:, None] * 0.85
            c = c * (1 - w) + _v([0.05, 0.02, 0.02]) * w
    # bajo el pelo: el cuero cabelludo toma el color del pelo (no se ve la costura)
    if V["pelo"]:
        cu = smoothstep(-0.004, 0.006, q[:, 2] - linea_pelo(V, q))[:, None] * 0.8
        c = c * (1 - cu) + V["PELO"] * cu
    return np.clip(c, 0, 1)


def ojos(V):
    S = Escultura()
    for s in (-1, 1):
        S.add(Esfera(ojo(s), R_OJO, 0), 0.0)
    return S


def uv_ojos(v):
    """UV de proyección frontal: el centro (0.5, 0.5) es el frente de cada ojo (lo que
    Ilvari.SHADER_OJO_UV toma como centro del iris). v crece hacia arriba (Blender)."""
    s = np.where(v[:, 0] < 0, -1.0, 1.0)
    cx = H[0] + OJO[0] * s
    cz = H[2] + OJO[2]
    return np.stack([0.5 + (v[:, 0] - cx) / (2 * R_OJO), 0.5 + (v[:, 2] - cz) / (2 * R_OJO)], axis=1).astype(np.float32)


# ----------------------------------------------------------------------- dientes

def dientes(V):
    """Dos filas en arco: las de arriba van con la cabeza, las de abajo con la mandíbula.
    normal = paletas y colmillos redondeados; afilados = limados en punta; podridos = rotos,
    cortos y con huecos."""
    estilo = V["dientes"]
    rng = np.random.default_rng(V["semilla"] + 3)
    sup, inf = Escultura(), Escultura()
    anchos = [0.0043, 0.0035, 0.0038, 0.0034, 0.0032]       # central, lateral, colmillo, premolares
    for S, z0, sentido in ((sup, BOCA_Z + 0.0045, -1), (inf, BOCA_Z - 0.0062, 1)):
        for s in (-1, 1):
            x = 0.0
            for i, w in enumerate(anchos):
                w = w * (0.9 if sentido > 0 else 1.0)
                xc = x + w * 0.5
                x += w
                u = xc / 0.0175
                y = -0.099 + 0.0095 * u * u
                if sentido > 0:
                    y += 0.0012
                largo = (0.0098 if i < 3 else 0.0082) * (0.85 if sentido > 0 else 1.0)
                if estilo == "podridos":
                    if rng.random() < 0.22 and i < 4:
                        continue
                    largo *= rng.uniform(0.45, 0.95)
                p0 = h(xc * s, y, z0)
                p1 = h(xc * s * 1.02, y - 0.0012, z0 + sentido * largo)
                ang = np.arctan2(0.019 * u, 1.0) * s
                if estilo == "afilados" or (i == 2 and estilo != "podridos"):
                    S.add(ConoRedondo(p0, p1, w * 0.48, 0.00035 if estilo == "afilados" else 0.0012), 0.0)
                else:
                    c = (p0 + p1) * 0.5
                    S.add(CajaRedonda(c, (w * 0.36, 0.0012, largo * 0.42), 0.0009, rot=rot_euler(0.1 * sentido, 0, -ang)), 0.0)
    return sup, inf


# ----------------------------------------------------------------------- pelo

def linea_pelo(V, q):
    """Altura (z relativa a H) a partir de la cual hay pelo, según el ángulo alrededor de la
    cabeza (0 = frente, pi = nuca). q relativo a H."""
    phi = np.abs(np.arctan2(q[:, 0], -q[:, 1]))
    est = V["pelo"]
    if est == "grasiento":   # entradas en las sienes
        a, z = [0, 0.3, 0.6, 0.95, 1.4, 1.9, 2.4, np.pi], [0.04, 0.046, 0.054, 0.036, 0.012, -0.05, -0.08, -0.092]
    elif est == "largo":
        a, z = [0, 0.5, 1.0, 1.4, 1.9, np.pi], [0.044, 0.04, 0.026, 0.01, -0.03, -0.06]
    else:
        a, z = [0, 0.5, 1.0, 1.4, 1.9, np.pi], [0.046, 0.042, 0.028, 0.012, -0.046, -0.08]
    return np.interp(phi, a, z).astype(np.float32)


GROSOR_PELO = {"grasiento": 0.0065, "largo": 0.0105, "moño": 0.0085}
MONO = h(0.0, 0.097, 0.012)     # centro del moño


def pelo(V):
    S0 = forma(V)
    est = V["pelo"]
    g = GROSOR_PELO[est]
    S = Escultura(banda=0.003)

    def casco(p):
        q = p - H
        dc = S0.evaluar(p)
        # cáscara (no un sólido): si no, el corte de la línea del pelo deja una tapa dentro del cráneo
        d = smax(dc - g, -(dc + 0.003), 0.0)
        d = smax(d, linea_pelo(V, q) - q[:, 2], 0.004)
        # las orejas quedan fuera
        for s in (-1, 1):
            d = smax(d, 0.024 - np.linalg.norm((q - _v([0.074 * s, 0.003, -0.03])) / _v([1.0, 1.0, 1.3]), axis=1), 0.004)
        return d
    S.add(Funcion(casco), 0.0)
    if est == "grasiento":
        # mechones sueltos que caen sobre la frente
        for x, dx in ((-0.012, 0.008), (0.012, 0.005)):
            pts = [superficie(S0, h(x + dx * t, 0.0, 0.05 - 0.034 * t), (0, -1, 0.1)) + _v([0, -0.0016, 0]) for t in (0.0, 0.5, 1.0)]
            S.add(ConoRedondo(pts[0] + _v([0, 0.002, 0.004]), pts[1], 0.0036, 0.0028), 0.004)
            S.add(ConoRedondo(pts[1], pts[2], 0.0028, 0.0016), 0.003)
    elif est == "largo":
        # melena: cae por la espalda y por detrás de los hombros
        S.add(ConoRedondo(h(0, 0.06, -0.02), _v([0, 0.13, 0.99]), 0.072, 0.085, aplastar=(1.0, 0.32), arriba=(0, 1, 0)), 0.03)
        for s in (-1, 1):
            S.add(ConoRedondo(h(0.068 * s, 0.03, -0.03), _v([0.105 * s, 0.1, 1.0]), 0.022, 0.03, aplastar=(1.0, 0.5), arriba=(s, 0.5, 0)), 0.025)
    else:
        S.add(Esfera(MONO, 0.031), 0.008)
        S.add(Toro(MONO + _v([0, 0.004, 0]), 0.024, 0.011, rot=rot_euler(np.pi / 2 + 0.25, 0, 0)), 0.006)
    S.desplazar.append(_mechones(V))
    return S


def _mechones(V):
    est = V["pelo"]

    def fn(p, d, reg):
        q = p - H
        if est == "grasiento":
            # peinado hacia atrás con grasa: surcos que van de la frente a la nuca, en mazos
            a = q[:, 0] * 520.0 + ruido(p * 60.0, 4) * 2.0
            out = 0.0006 * np.sin(a) + 0.0003 * np.sin(a * 2.7 + 1.0)
        elif est == "largo":
            # raya en medio; mechones que caen
            raya = -0.0012 * np.exp(-(q[:, 0] / 0.0025) ** 2) * smoothstep(0.03, 0.06, q[:, 2]) * (q[:, 1] < 0.02)
            ang = np.arctan2(q[:, 0], -q[:, 1])
            out = raya + 0.00035 * np.sin(ang * 110.0 + q[:, 2] * 40.0 + ruido(p * 40.0, 4) * 2.5) \
                + 0.0007 * np.sin(ang * 23.0 + q[:, 2] * 15.0 + ruido(p * 12.0, 7) * 3.0)
        else:
            # recogido hacia el moño: surcos que convergen en él, y vueltas en el moño
            r = p - MONO
            ang = np.arctan2(r[:, 0], r[:, 2])
            en_mono = np.linalg.norm(r, axis=1) < 0.04
            out = np.where(en_mono, 0.0007 * np.sin(np.arctan2(r[:, 0], -r[:, 2]) * 7.0 + np.linalg.norm(r, axis=1) * 600.0),
                           0.0003 * np.sin(ang * 90.0 + ruido(p * 50.0, 4) * 1.5) + 0.0005 * np.sin(ang * 21.0 + ruido(p * 14.0, 7) * 2.5))
        return out + 0.0004 * fbm(p * 80.0, 2, 5)
    return fn


def colores_pelo(V, v):
    q = v - H
    base = np.tile(V["PELO"], (len(v), 1))
    # mechones claros y oscuros siguiendo el peinado
    if V["pelo"] == "grasiento":
        f = np.sin(q[:, 0] * 520.0 + ruido(v * 60.0, 4) * 2.0)
    elif V["pelo"] == "largo":
        f = np.sin(np.arctan2(q[:, 0], -q[:, 1]) * 90.0 + q[:, 2] * 40.0 + ruido(v * 40.0, 4) * 2.5)
    else:
        f = np.sin(np.arctan2((v - MONO)[:, 0], (v - MONO)[:, 2]) * 70.0)
    base = base * (1.0 + 0.35 * f[:, None]) + 0.012 * smoothstep(0.3, 1.0, f)[:, None]
    # canas (Elena)
    if V["edad"] > 0.6:
        cana = smoothstep(0.82, 0.9, ruido(v * _v([400.0, 400.0, 60.0]), 91))[:, None] * 0.6
        base = base * (1 - cana) + _v([0.45, 0.43, 0.4]) * cana
    # grasa y suciedad: más oscuro en la raíz y junto a la piel
    base *= 1.0 - 0.3 * smoothstep(0.012, 0.0, q[:, 2] - linea_pelo(V, q))[:, None]
    return np.clip(base, 0, 1)


# ----------------------------------------------------------------------- huesos

def huesos_cuerpo(V, W_R, W_L, placa=None):
    fr = (0, -1, 0)
    hs = [
        dict(nombre="raiz", cabeza=(0, 0.06, 0.45), cola=tuple(P_PELVIS), arriba=fr, padre=None),
        dict(nombre="cadera", cabeza=tuple(P_PELVIS), cola=tuple(P_LUMBAR), arriba=fr, padre="raiz"),
        dict(nombre="columna", cabeza=tuple(P_LUMBAR), cola=tuple(P_PECHO), arriba=fr, padre="cadera"),
        dict(nombre="pecho", cabeza=tuple(P_PECHO), cola=tuple(P_CUELLO), arriba=fr, padre="columna"),
        dict(nombre="cuello", cabeza=tuple(P_CUELLO), cola=tuple(P_CUELLO2), arriba=fr, padre="pecho"),
        dict(nombre="cuello2", cabeza=tuple(P_CUELLO2), cola=tuple(P_CRANEO), arriba=fr, padre="cuello"),
        dict(nombre="cabeza", cabeza=tuple(P_CRANEO), cola=tuple(P_CORONILLA), arriba=fr, padre="cuello2"),
        dict(nombre="mandibula", cabeza=tuple(BISAGRA), cola=tuple(MENTON), arriba=(0, -0.6, 0.8), padre="cabeza"),
    ]
    for s, suf in ((-1, "_R"), (1, "_L")):
        c = h(CEJA[0] * s, CEJA[1], CEJA[2])
        hs.append(dict(nombre="ceja" + suf, cabeza=tuple(c), cola=tuple(c + _v([0, -0.015, 0])), arriba=(0, 0, 1), padre="cabeza"))
        c = h(COMISURA[0] * s, COMISURA[1], COMISURA[2])
        hs.append(dict(nombre="comisura" + suf, cabeza=tuple(c), cola=tuple(c + _v([0.012 * s, 0.004, 0])), arriba=(0, 0, 1), padre="cabeza"))
    if placa is not None:
        p, n = placa
        hs.append(dict(nombre="placa", cabeza=tuple(p), cola=tuple(p + n * 0.02), arriba=(0, 0, 1), padre="pecho", deform=False))
    for lado, s, W in ((-1, "_R", W_R), (1, "_L", W_L)):
        hm = espejo(hombro(V), lado)
        c = espejo(codo(V), lado)
        hs += [
            dict(nombre="clavicula" + s, cabeza=(0.03 * lado, -0.02, 1.06), cola=tuple(hm), arriba=(0, 0, 1), padre="pecho"),
            dict(nombre="brazo" + s, cabeza=tuple(hm), cola=tuple(c), arriba=(lado, 0.3, 0), padre="clavicula" + s),
            dict(nombre="antebrazo" + s, cabeza=tuple(c), cola=tuple(W), arriba=(0, 0, 1), padre="brazo" + s),
        ]
    return hs


def mascara_cabeza(q):
    """1 por encima del plano inclinado que separa la cabeza del cuello (bajo el mentón por
    delante, en la nuca por detrás)."""
    zb = -0.132 + 0.36 * (q[:, 1] + 0.1)
    return smoothstep(-0.008, 0.016, q[:, 2] - zb)


def pesos_cabeza(v, dist_seg):
    """Cadena del cuello por distancia; encima, máscaras de mandíbula, cejas y comisuras."""
    q = v - H
    cadena = ["pecho", "cuello", "cuello2", "cabeza"]
    D = np.stack([dist_seg(n) for n in cadena], axis=1)
    W = 1.0 / np.maximum(D, 1e-4) ** 4
    W[:, 3] += mascara_cabeza(q) * 1e9
    W[:, 0] *= smoothstep(1.1, 1.05, v[:, 2])
    W /= W.sum(axis=1, keepdims=True)
    # mandíbula: bajo la boca, por delante de la bisagra; se funde con el cuello bajo el mentón
    jaw = smoothstep(BOCA_Z + 0.002, BOCA_Z - 0.0045, q[:, 2]) * smoothstep(0.012, -0.012, q[:, 1]) * mascara_cabeza(q)
    jaw *= smoothstep(0.075, 0.062, np.abs(q[:, 0]))
    jaw = np.maximum(jaw, (cavidad_boca().dist(v) < 0.004) * (q[:, 2] < BOCA_Z - 0.002) * 1.0)
    com = np.zeros((len(v), 2), np.float32)
    for i, s in enumerate((-1, 1)):
        dc = np.linalg.norm((q - _v([COMISURA[0] * s, COMISURA[1], COMISURA[2]])) / _v([1.0, 1.4, 1.0]), axis=1)
        com[:, i] = smoothstep(0.02, 0.003, dc) * 0.9
    comt = np.clip(com.sum(axis=1), 0, 0.9)
    jaw *= (1 - comt)
    ceja = np.zeros(len(v), np.float32)
    for s in (-1, 1):
        dc = np.linalg.norm(q - _v([CEJA[0] * s, CEJA[1], CEJA[2]]), axis=1)
        ceja = np.maximum(ceja, smoothstep(0.026, 0.007, dc))
    ceja *= (1 - jaw) * (1 - comt)
    resto = np.clip(1 - jaw - ceja - comt, 0, 1)[:, None]
    W = W * resto
    nombres = cadena + ["mandibula", "ceja_R", "ceja_L", "comisura_R", "comisura_L"]
    W = np.concatenate([W, jaw[:, None], (ceja * (v[:, 0] < 0))[:, None], (ceja * (v[:, 0] >= 0))[:, None], com], axis=1)
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    return nombres, W


def pesos_pelo(V, v, dist_seg):
    """El pelo va con la cabeza; la melena larga pasa poco a poco al cuello y al pecho."""
    if V["pelo"] != "largo":
        return ["cabeza"], np.ones((len(v), 1), np.float32)
    nombres = ["pecho", "cuello", "cuello2", "cabeza"]
    D = np.stack([dist_seg(n) for n in nombres], axis=1)
    W = 1.0 / np.maximum(D, 1e-4) ** 3
    arriba = smoothstep(H[2] - 0.09, H[2] - 0.05, v[:, 2])
    W[:, 3] += arriba * 1e9
    W /= W.sum(axis=1, keepdims=True)
    return nombres, W
