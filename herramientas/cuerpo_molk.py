"""INTERROGART - Gruul, el molk (2,3 m de roca viva con núcleo de magma), sentado y encorvado
al otro lado de la mesa. Mismo convenio que cuerpo_ilvari.py: Blender (x, y, z) = Godot
(x, -z, y), mira hacia -Y; lado -1 = x negativa = su mano DERECHA (_R).
Mismos nombres de huesos que el ilvari (lo anima Ilvari.gd): la losa de la frente cuelga de
ceja_R/L y la mandíbula con sus colmillos de "mandibula".
Piezas: cabeza (cráneo de bloques, losa de la frente, ojos de brasa hundidos, nariz chata,
quijada con colmillos), cuerpo de piedra al aire (hombros de roca, brazos), mono del penal sin
mangas y manos (mano_molk.py). Las grietas brillan: grietas() es la máscara de emisión.
"""
import os
import json
import numpy as np
from sdf import (Escultura, Esfera, Elipsoide, ConoRedondo, CajaRedonda, Funcion,
                 rot_euler, rot_matriz, smoothstep, smin, smax, ruido, fbm, _v)
from cuerpo_kthar import superficie
from cuerpo_humano import lineal
from mano_molk import grietas, _roca

AQUI = os.path.dirname(os.path.abspath(__file__))
FICHAS = os.path.join(os.path.dirname(AQUI), "data", "sospechosos.json")

MESA = 0.795
H = _v([0.0, -0.14, 1.40])           # centro de la cabeza
P_PELVIS = _v([0.0, 0.1, 0.58])
P_LUMBAR = _v([0.0, 0.09, 0.77])
P_PECHO = _v([0.0, 0.04, 1.0])
P_CUELLO = _v([0.0, -0.05, 1.2])
P_CUELLO2 = _v([0.0, -0.085, 1.26])
P_CRANEO = H + _v([0.0, 0.03, -0.08])
P_CORONILLA = H + _v([0.0, 0.02, 0.13])
HOMBRO = _v([0.27, 0.0, 1.17])
CODO = _v([0.36, -0.33, 0.9])
MUNECA_XY = _v([0.2, -0.66])
YAW_MANO = 0.25
PITCH_MANO = np.radians(3.0)
FLEX_REPOSO = (8.0, 16.0, 10.0)
CADERA_J = _v([0.15, 0.07, 0.56])
RODILLA = _v([0.17, -0.38, 0.58])
TOBILLO = _v([0.18, -0.42, 0.08])
LEAN = 0.3

R_TORSO_B, R_TORSO_A, R_HOMBRO, R_BRAZO, R_ANTEBRAZO, R_CUELLO_T, R_PIERNA = 1, 2, 3, 4, 5, 6, 7
R_CUELLO, R_CABEZA, R_MANDIBULA, R_CEJA, R_ROCA = 20, 21, 22, 24, 25

OJO = _v([0.043, -0.098, 0.004])
R_OJO = 0.0125
BOCA_Z = -0.066
CEJA = _v([0.042, -0.115, 0.03])
BISAGRA = H + _v([0.0, 0.0, -0.05])
MENTON = H + _v([0.0, -0.12, -0.125])


def ficha(ident="gruul"):
    r = {}
    if os.path.exists(FICHAS):
        with open(FICHAS, encoding="utf-8") as f:
            for s in json.load(f)["sospechosos"]:
                if s["id"] == ident:
                    r = s.get("rasgos", {})
    return dict(PIEL=lineal(r.get("piel"), (0.045, 0.04, 0.034)), MANCHA=lineal(r.get("mancha"), (0.012, 0.01, 0.009)),
                ROPA=lineal(r.get("ropa"), (0.25, 0.04, 0.005)), MANCHA_ROPA=lineal(r.get("mancha_ropa"), (0.006, 0.002, 0.001)),
                suciedad=float(r.get("suciedad", 0.6)), semilla=int(r.get("semilla", 9)))


def h(x, y, z):
    return H + _v([x, y, z])


def espejo(p, lado):
    return _v([p[0] * lado, p[1], p[2]])


def ojo(s):
    return h(OJO[0] * s, OJO[1], OJO[2])


# ----------------------------------------------------------------------- manos

def mano_transform(lado):
    return rot_matriz((0, 0, 1), np.pi + YAW_MANO) @ rot_matriz((1, 0, 0), PITCH_MANO)


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


# ----------------------------------------------------------------------- cuerpo de piedra

def _torso(S, inflar=0.0, k=1.0):
    L = rot_euler(LEAN, 0, 0)
    S.add(Elipsoide((0, 0.1, 0.62), (0.24 + inflar, 0.17 + inflar, 0.12 + inflar), R_TORSO_B), 0.0)
    S.add(Elipsoide((0, 0.08, 0.78), (0.21 + inflar, 0.15 + inflar, 0.15 + inflar), R_TORSO_B, rot=L), 0.08 * k)
    S.add(Elipsoide((0, 0.02, 0.99), (0.25 + inflar, 0.16 + inflar, 0.19 + inflar), R_TORSO_A, rot=L), 0.08 * k)


def cuerpo(W_R, W_L):
    """La piel de roca que asoma: torso (bajo el mono), trapecios, hombros y brazos."""
    rng = np.random.default_rng(31)
    S = Escultura(banda=0.006)
    _torso(S)
    # trapecios: el cuello casi desaparece entre los hombros
    for s in (-1, 1):
        S.add(ConoRedondo(_v([0.05 * s, -0.02, 1.2]), espejo(HOMBRO, s) + _v([-0.04 * s, 0.0, 0.03]), 0.07, 0.075, R_TORSO_A), 0.06)
    for lado, W in ((-1, W_R), (1, W_L)):
        hm = espejo(HOMBRO, lado)
        c = espejo(CODO, lado)
        S.add(Esfera(hm, 0.095, R_HOMBRO), 0.05)
        S.add(ConoRedondo(hm, c, 0.085, 0.07, R_BRAZO), 0.04)
        S.add(ConoRedondo(c, W, 0.072, 0.05, R_ANTEBRAZO, aplastar=(1.0, 0.85), arriba=(0, 0, 1)), 0.03)
        S.add(Esfera(c + _v([0.01 * lado, 0.02, -0.01]), 0.06, R_BRAZO), 0.03)
        # hombrera de rocas
        for i in range(4):
            cc = hm + _v([rng.uniform(-0.03, 0.06) * lado, rng.uniform(-0.06, 0.06), rng.uniform(0.04, 0.09)])
            S.add(CajaRedonda(cc, (rng.uniform(0.035, 0.055), rng.uniform(0.03, 0.05), rng.uniform(0.02, 0.035)), 0.01, R_HOMBRO,
                              rot=rot_euler(rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6))), 0.015)
        # placas en el antebrazo
        for i in range(3):
            u = 0.2 + 0.25 * i
            cc = c + (W - c) * u + _v([0.03 * lado, 0.0, 0.045])
            S.add(CajaRedonda(cc, (0.03, 0.035, 0.012), 0.006, R_ANTEBRAZO, rot=rot_euler(rng.uniform(-0.3, 0.3), 0, rng.uniform(-0.4, 0.4))), 0.01)

    def det(p, d, reg):
        return _roca(p, 2.0) - 0.0022 * grietas(p, 2.0)
    S.desplazar.append(det)
    return S


def colores_roca(F, v, n, escala=2.0):
    c = np.tile(F["PIEL"], (len(v), 1))
    c *= 1.0 + fbm(v / escala * 40.0, 3, 21)[:, None] * 0.3
    mot = smoothstep(0.0, 0.35, fbm(v / escala * 25.0, 3, 5))[:, None] * 0.6
    c = c * (1 - mot) + F["MANCHA"] * mot
    c *= 1.0 + 0.5 * ((1.0 - np.abs(ruido(v / escala * 55.0, 61))) ** 6)[:, None]
    polvo = smoothstep(0.3, 0.9, n[:, 2])[:, None] * F["suciedad"] * 0.2
    c = c * (1 - polvo) + _v([0.09, 0.08, 0.07]) * polvo
    g = grietas(v, escala)[:, None]
    c = c * (1 - g) + _v([0.35, 0.06, 0.01]) * g
    return np.clip(c, 0, 1)


# ----------------------------------------------------------------------- mono sin mangas

def mono():
    S = Escultura(banda=0.016)
    _torso(S, inflar=0.012)
    for lado in (-1, 1):
        S.add(ConoRedondo(espejo(CADERA_J, lado), espejo(RODILLA, lado), 0.13, 0.1, R_PIERNA), 0.06)
        S.add(ConoRedondo(espejo(RODILLA, lado), espejo(TOBILLO, lado), 0.095, 0.085, R_PIERNA), 0.02)
        # sisa: arrancadas las mangas
        S.sub(Esfera(espejo(HOMBRO, lado) + _v([0.03 * lado, 0.0, -0.02]), 0.13), 0.02)
    # cuello: sin cuello de mono, un escote ancho
    S.sub(Elipsoide(_v([0, -0.03, 1.2]), (0.15, 0.2, 0.1)), 0.02)
    S.sub(CajaRedonda((0, -0.2, -0.05), (0.8, 0.8, 0.06), 0.0), 0.0)

    def det(p, d, reg):
        out = 0.0028 * np.sin(p[:, 2] * 70.0 + ruido(p * 9.0, 3) * 4.0) * smoothstep(0.86, 0.66, p[:, 2]) * smoothstep(0.45, 0.62, p[:, 2])
        out += 0.0016 * fbm(p * 7.0, 3, 31) + 0.00015 * ruido(p * 500.0, 2)
        # bordes deshilachados de las sisas
        for lado in (-1, 1):
            dd = np.linalg.norm(p - espejo(HOMBRO, lado) - _v([0.03 * lado, 0.0, -0.02]), axis=1)
            out += 0.003 * np.exp(-((dd - 0.15) / 0.012) ** 2) * np.sin(np.arctan2(p[:, 2] - HOMBRO[2], p[:, 1]) * 40.0)
        return out
    S.desplazar.append(det)
    return S


def colores_mono(F, v):
    base = np.tile(F["ROPA"], (len(v), 1))
    base *= (1.0 + fbm(v * 12.0, 3, 7)[:, None] * 0.25)
    g = smoothstep(0.05, 0.35, fbm(v * _v([16.0, 16.0, 22.0]), 4, 51))[:, None] * (0.3 + F["suciedad"] * 0.6)
    base = base * (1 - g) + F["MANCHA_ROPA"] * g
    # quemaduras: el magma chamusca la tela junto a las grietas del pecho
    q = smoothstep(0.55, 0.75, ruido(v * 30.0, 81))[:, None] * 0.7
    base = base * (1 - q) + _v([0.01, 0.006, 0.004]) * q
    return np.clip(base, 0, 1)


def placa_pos(S):
    p = superficie(S, _v([0.1, 0.0, 1.0]), (0, -1, 0.0), 0.4, 0.001)
    e = 0.002
    g = _v([S.evaluar((p + _v(dx))[None])[0] - S.evaluar((p - _v(dx))[None])[0]
            for dx in ((e, 0, 0), (0, e, 0), (0, 0, e))])
    return p, g / np.linalg.norm(g)


# ----------------------------------------------------------------------- cabeza

def _cabeza_base(S, rng):
    S.add(ConoRedondo(P_CUELLO + _v([0, 0.03, -0.1]), P_CRANEO + _v([0, 0.0, 0.03]), 0.09, 0.08, R_CUELLO), 0.0)
    # cráneo bajo y ancho, de bloques
    S.add(Elipsoide(h(0, 0.02, 0.02), (0.1, 0.105, 0.085), R_CABEZA, rot=rot_euler(0.15, 0, 0)), 0.03)
    S.add(CajaRedonda(h(0, 0.0, 0.035), (0.06, 0.07, 0.04), 0.03, R_CABEZA, rot=rot_euler(0.15, 0, 0)), 0.03)
    S.add(CajaRedonda(h(0, -0.045, -0.04), (0.06, 0.04, 0.045), 0.02, R_CABEZA), 0.03)
    for s in (-1, 1):
        # pómulos de losa
        S.add(CajaRedonda(h(0.066 * s, -0.08, -0.03), (0.02, 0.026, 0.02), 0.008, R_CABEZA, rot=rot_euler(0.1, 0, 0.35 * s)), 0.012)
        # losa de la frente (cuelga de las cejas)
        S.add(CajaRedonda(h(0.04 * s, -0.106, 0.034), (0.042, 0.02, 0.016), 0.007, R_CEJA, rot=rot_euler(0.35, 0.12 * s, 0.1 * s)), 0.01)
    # nariz chata
    S.add(CajaRedonda(h(0, -0.127, -0.022), (0.02, 0.015, 0.024), 0.009, R_CABEZA, rot=rot_euler(-0.25, 0, 0)), 0.01)
    # quijada: un bloque enorme, más ancho que la cara
    S.add(CajaRedonda(h(0, -0.075, -0.098), (0.082, 0.06, 0.028), 0.016, R_MANDIBULA, rot=rot_euler(-0.12, 0, 0)), 0.02)
    S.add(CajaRedonda(h(0, -0.125, -0.112), (0.045, 0.02, 0.022), 0.012, R_MANDIBULA), 0.015)
    # crestas de roca sobre el cráneo
    for i in range(6):
        c = h(rng.uniform(-0.06, 0.06), rng.uniform(-0.04, 0.08), 0.085 + rng.uniform(-0.01, 0.015))
        S.add(CajaRedonda(c, (rng.uniform(0.015, 0.028), rng.uniform(0.015, 0.028), rng.uniform(0.008, 0.014)), 0.005, R_ROCA,
                          rot=rot_euler(rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), rng.uniform(-0.6, 0.6))), 0.012)


def cavidad_boca():
    return Elipsoide(h(0, -0.11, BOCA_Z - 0.008), (0.055, 0.03, 0.014))


def cabeza():
    rng = np.random.default_rng(77)
    S = Escultura(banda=0.004)
    _cabeza_base(S, rng)
    for s in (-1, 1):
        # cuencas hondas bajo la losa
        S.sub(Elipsoide(ojo(s) + _v([0.0, -0.008, 0.0]), (0.021, 0.018, 0.0145)), 0.006)
        S.sub(Elipsoide(h(0.011 * s, -0.142, -0.035), (0.005, 0.008, 0.004), rot=rot_euler(0.3, 0, 0.3 * s)), 0.002)
    S.sub(CajaRedonda(h(0, -0.14, BOCA_Z), (0.058, 0.03, 0.0018), 0.001), 0.002)
    S.sub(cavidad_boca(), 0.004)

    def det(p, d, reg):
        return _roca(p, 1.6) - 0.0018 * grietas(p, 1.6)
    S.desplazar.append(det)
    return S


def colores_cabeza(F, v, n):
    c = colores_roca(F, v, n, 1.6)
    q = v - H
    dentro = smoothstep(0.002, -0.002, cavidad_boca().dist(v) - 0.002)[:, None]
    c = c * (1 - dentro) + _v([0.3, 0.05, 0.005]) * dentro       # la boca brilla por dentro
    for s in (-1, 1):
        w = smoothstep(0.03, 0.012, np.linalg.norm(q - _v([OJO[0] * s, OJO[1], OJO[2]]), axis=1))[:, None] * 0.7
        c = c * (1 - w) + _v([0.01, 0.006, 0.004]) * w             # cuencas negras
    return np.clip(c, 0, 1)


def emision_cabeza(v):
    e = grietas(v, 1.6) ** 2
    e = np.maximum(e, smoothstep(0.002, -0.002, cavidad_boca().dist(v) - 0.002) * 0.8)
    return e


def ojos():
    S = Escultura()
    for s in (-1, 1):
        S.add(Esfera(ojo(s), R_OJO, 0), 0.0)
    return S


def uv_ojos(v):
    s = np.where(v[:, 0] < 0, -1.0, 1.0)
    cx = H[0] + OJO[0] * s
    cz = H[2] + OJO[2]
    return np.stack([0.5 + (v[:, 0] - cx) / (2 * R_OJO), 0.5 + (v[:, 2] - cz) / (2 * R_OJO)], axis=1).astype(np.float32)


def colmillos():
    """Colmillos de la quijada hacia arriba y una fila de muelas romas (van con la mandíbula)."""
    S = Escultura()
    for s in (-1, 1):
        S.add(ConoRedondo(h(0.054 * s, -0.128, BOCA_Z - 0.016), h(0.06 * s, -0.142, BOCA_Z + 0.03), 0.0115, 0.0018), 0.0)
    for i in range(6):
        x = -0.03 + i * 0.012
        S.add(CajaRedonda(h(x, -0.132 + 0.012 * (x / 0.03) ** 2, BOCA_Z - 0.006), (0.0048, 0.004, 0.005), 0.0015), 0.0)
    return S


# ----------------------------------------------------------------------- huesos

def huesos_cuerpo(W_R, W_L, placa=None):
    fr = (0, -1, 0)
    hs = [
        dict(nombre="raiz", cabeza=(0, 0.1, 0.45), cola=tuple(P_PELVIS), arriba=fr, padre=None),
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
        hs.append(dict(nombre="ceja" + suf, cabeza=tuple(c), cola=tuple(c + _v([0, -0.02, 0])), arriba=(0, 0, 1), padre="cabeza"))
    if placa is not None:
        p, n = placa
        hs.append(dict(nombre="placa", cabeza=tuple(p), cola=tuple(p + n * 0.02), arriba=(0, 0, 1), padre="pecho", deform=False))
    for lado, s, W in ((-1, "_R", W_R), (1, "_L", W_L)):
        hm = espejo(HOMBRO, lado)
        c = espejo(CODO, lado)
        hs += [
            dict(nombre="clavicula" + s, cabeza=(0.05 * lado, -0.02, 1.15), cola=tuple(hm), arriba=(0, 0, 1), padre="pecho"),
            dict(nombre="brazo" + s, cabeza=tuple(hm), cola=tuple(c), arriba=(lado, 0.3, 0), padre="clavicula" + s),
            dict(nombre="antebrazo" + s, cabeza=tuple(c), cola=tuple(W), arriba=(0, 0, 1), padre="brazo" + s),
        ]
    return hs


def pesos_cabeza(v, dist_seg):
    q = v - H
    cadena = ["pecho", "cuello", "cuello2", "cabeza"]
    D = np.stack([dist_seg(n) for n in cadena], axis=1)
    W = 1.0 / np.maximum(D, 1e-4) ** 4
    W[:, 3] += smoothstep(-0.11, -0.07, q[:, 2] + 0.4 * np.minimum(q[:, 1] + 0.05, 0)) * 1e9
    W[:, 0] *= smoothstep(1.25, 1.17, v[:, 2])
    W /= W.sum(axis=1, keepdims=True)
    jaw = smoothstep(BOCA_Z + 0.002, BOCA_Z - 0.006, q[:, 2]) * smoothstep(0.02, -0.02, q[:, 1]) * smoothstep(-0.17, -0.14, q[:, 2])
    jaw = np.maximum(jaw, (cavidad_boca().dist(v) < 0.004) * (q[:, 2] < BOCA_Z - 0.002) * 1.0)
    ceja = np.zeros(len(v), np.float32)
    for s in (-1, 1):
        dc = np.linalg.norm(q - _v([CEJA[0] * s, CEJA[1], CEJA[2]]), axis=1)
        ceja = np.maximum(ceja, smoothstep(0.045, 0.02, dc))
    ceja *= (1 - jaw)
    resto = np.clip(1 - jaw - ceja, 0, 1)[:, None]
    W = W * resto
    nombres = cadena + ["mandibula", "ceja_R", "ceja_L"]
    W = np.concatenate([W, jaw[:, None], (ceja * (v[:, 0] < 0))[:, None], (ceja * (v[:, 0] >= 0))[:, None]], axis=1)
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    return nombres, W
