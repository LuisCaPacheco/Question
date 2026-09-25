"""INTERROGART - Vehl Iskaar, un ilvari (2,1 m), sentado al otro lado de la mesa.
Coordenadas de Blender = coordenadas LOCALES del nodo Sospechoso en Godot rotadas:
Godot (x, y, z) = Blender (x, z, -y). El ilvari mira hacia -Y de Blender (hacia la cámara).
Mesa: z = 0.795; su borde (lado del sospechoso) en y = -0.35.
Lado: -1 = x negativa = su mano DERECHA (sufijo _R); +1 = izquierda (_L).
"""
import numpy as np
from sdf import (Escultura, Esfera, Elipsoide, ConoRedondo, CajaRedonda, Toro, Funcion,
                 rot_euler, rot_matriz, smoothstep, smin, smax, ruido, fbm, _v)

MESA = 0.795
H = _v([0.0, -0.07, 1.36])          # centro de la cabeza

P_PELVIS = _v([0.0, 0.07, 0.56])
P_LUMBAR = _v([0.0, 0.06, 0.72])
P_PECHO = _v([0.0, 0.02, 0.92])
P_CUELLO = _v([0.0, -0.02, 1.11])
P_CUELLO2 = _v([0.0, -0.037, 1.185])
P_CRANEO = _v([0.0, -0.052, 1.265])
P_CORONILLA = _v([0.0, -0.03, 1.465])
HOMBRO = _v([0.163, -0.035, 1.065])
CODO = _v([0.27, -0.40, 0.836])
MUNECA_XY = _v([0.15, -0.64])
YAW_MANO = 0.22
PITCH_MANO = np.radians(3.0)
FLEX_REPOSO = (8.0, 16.0, 10.0)
CADERA_J = _v([0.1, 0.05, 0.54])
RODILLA = _v([0.12, -0.33, 0.56])
TOBILLO = _v([0.13, -0.36, 0.08])
LEAN = 0.22                          # el torso se inclina hacia la mesa (-Y)

# regiones de la túnica
R_TORSO_B, R_TORSO_A, R_HOMBRO, R_BRAZO, R_ANTEBRAZO, R_CUELLO_T, R_FALDA = 1, 2, 3, 4, 5, 6, 7
# regiones de la piel
R_CUELLO, R_CABEZA, R_MANDIBULA, R_GARGANTA, R_CEJA = 20, 21, 22, 23, 24

# rasgos de la cara (coordenadas relativas a H)
OJO = _v([0.034, -0.095, 0.001])
OJO_R = (0.021, 0.017, 0.0145)
OJO_TILT = 0.32
BOCA_Z = -0.075
SACO = H + _v([0.0, -0.03, -0.128])  # saco vocal (absoluto)
SACO_R = (0.023, 0.021, 0.026)
BISAGRA = H + _v([0.0, -0.005, -0.045])
MENTON = H + _v([0.0, -0.088, -0.108])
CEJA = _v([0.035, -0.103, 0.024])

# colores (lineales)
PIEL = (0.29, 0.325, 0.4)
PIEL_CLARA = (0.46, 0.4, 0.48)
PIGMENTO = (0.13, 0.15, 0.22)
VENA = (0.2, 0.25, 0.46)
LABIO = (0.26, 0.2, 0.3)
BOCA_INT = (0.1, 0.025, 0.045)
PUNTA = (0.08, 0.08, 0.11)


def h(x, y, z):
    return H + _v([x, y, z])


def espejo(p, lado):
    return _v([p[0] * lado, p[1], p[2]])


def rot_ojo(s):
    return rot_euler(0.0, -OJO_TILT * s, 0.0)


# ----------------------------------------------------------------------- manos

def mano_transform(lado):
    """Rotación de la mano (la local es derecha, dedos +Y). Para lado -1 los dedos
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


# ----------------------------------------------------------------------- túnica

def _torso(S, inflar=0.0, k=1.0):
    L = rot_euler(LEAN, 0, 0)
    S.add(Elipsoide((0, 0.07, 0.6), (0.17 + inflar, 0.13 + inflar, 0.1 + inflar), R_TORSO_B), 0.0)
    S.add(Elipsoide((0, 0.05, 0.75), (0.135 + inflar, 0.098 + inflar, 0.13 + inflar), R_TORSO_B, rot=L), 0.07 * k)
    S.add(Elipsoide((0, 0.012, 0.925), (0.148 + inflar, 0.104 + inflar, 0.15 + inflar), R_TORSO_A, rot=L), 0.07 * k)
    S.add(ConoRedondo(espejo(HOMBRO, -1) + _v([0.035, 0.0, -0.012]), HOMBRO + _v([-0.035, 0.0, -0.012]), 0.049 + inflar, 0.049 + inflar,
                      R_HOMBRO, aplastar=(1.0, 0.82), arriba=(0, -0.3, 1)), 0.06 * k)


def puno(lado, W):
    """Final de la manga (un poco antes de la muñeca, por el lado del codo)."""
    c = espejo(CODO, lado)
    d = (W - c) / np.linalg.norm(W - c)
    return W - d * 0.035


def tunica(W_R, W_L):
    S = Escultura(banda=0.016)
    _torso(S)
    for lado, W in ((-1, W_R), (1, W_L)):
        hm = espejo(HOMBRO, lado)
        c = espejo(CODO, lado)
        pe = puno(lado, W)
        S.add(Esfera(hm + _v([0.006 * lado, 0.0, 0.004]), 0.05, R_HOMBRO), 0.035)
        S.add(ConoRedondo(hm, c, 0.046, 0.041, R_BRAZO), 0.03)
        S.add(ConoRedondo(c, pe, 0.041, 0.036, R_ANTEBRAZO, aplastar=(1.0, 0.82), arriba=(0, 0, 1)), 0.022)
        # bocamanga algo acampanada
        d = (pe - c) / np.linalg.norm(pe - c)
        S.add(ConoRedondo(pe - d * 0.03, pe, 0.04, 0.043, R_ANTEBRAZO, aplastar=(1.0, 0.8), arriba=(0, 0, 1)), 0.01)
        S.sub(ConoRedondo(pe - d * 0.05, pe + d * 0.03, 0.033, 0.035, aplastar=(1.0, 0.78), arriba=(0, 0, 1)), 0.003)
        # falda sobre las piernas (túnica larga)
        S.add(ConoRedondo(espejo(CADERA_J, lado), espejo(RODILLA, lado), 0.1, 0.08, R_FALDA), 0.06)
        S.add(ConoRedondo(espejo(RODILLA, lado), espejo(TOBILLO, lado), 0.078, 0.085, R_FALDA), 0.03)
    # cuello alto (mandarín) con hueco para el cuello
    S.add(ConoRedondo(_v([0, -0.012, 1.04]), _v([0, -0.026, 1.145]), 0.06, 0.054, R_CUELLO_T), 0.03)
    S.sub(ConoRedondo(_v([0, -0.005, 1.0]), _v([0, -0.05, 1.26]), 0.047, 0.044), 0.004)
    S.sub(CajaRedonda((0, -0.2, -0.05), (0.6, 0.6, 0.06), 0.0), 0.0)
    S.desplazar.append(_detalle_tunica(W_R, W_L))
    return S


def _franja(p):
    """Máscara del ribete (cuello y tira central del pecho)."""
    frente = smoothstep(0.0, -0.08, p[:, 1])
    tira = smoothstep(0.011, 0.007, np.abs(p[:, 0])) * frente * (p[:, 2] > 0.66) * (p[:, 2] < 1.08)
    cuello = smoothstep(1.13, 1.14, p[:, 2]) * (p[:, 2] < 1.2)
    return np.clip(tira + cuello, 0, 1)


def _detalle_tunica(W_R, W_L):
    def fn(p, d, reg):
        out = np.zeros(len(p), np.float32)
        out += 0.0016 * _franja(p)
        # costuras del ribete
        for bx in (0.011, -0.011):
            out -= 0.0007 * np.exp(-((p[:, 0] - bx) / 0.0012) ** 2) * (p[:, 1] < -0.03) * (p[:, 2] > 0.66) * (p[:, 2] < 1.08)
        # pliegues: codos, hombros, cintura y regazo
        for lado in (-1, 1):
            c = espejo(CODO, lado)
            dd = np.linalg.norm(p - c, axis=1)
            fold = np.sin((p[:, 1] * 0.7 + p[:, 2] * 0.7) * 170.0 + ruido(p * 16.0, 4) * 3.0)
            out += 0.0024 * fold * np.exp(-(dd / 0.08) ** 2)
            W = W_R if lado < 0 else W_L
            dc = np.linalg.norm(p - W, axis=1)
            out += 0.0014 * np.sin(p[:, 1] * 240.0 + ruido(p * 28.0, 9) * 2.0) * np.exp(-(dc / 0.07) ** 2)
        out += 0.0022 * np.sin(p[:, 2] * 95.0 + ruido(p * 10.0, 3) * 4.0) * smoothstep(0.82, 0.66, p[:, 2]) * smoothstep(0.45, 0.62, p[:, 2])
        out += 0.0012 * fbm(p * 8.0, 3, 31)
        return out
    return fn


def colores_tunica(v):
    base = np.tile(_v([0.045, 0.06, 0.068]), (len(v), 1))
    base *= 1.0 + fbm(v * 25.0, 3, 7)[:, None] * 0.15
    fr = _franja(v)[:, None]
    ribete = _v([0.12, 0.105, 0.075]) * (1.0 + 0.25 * np.sin(v[:, 2:3] * 900.0))   # bordado
    return np.clip(base * (1 - fr) + ribete * fr, 0, 1)


# ----------------------------------------------------------------------- cabeza y cuello

def cavidad_boca():
    return Elipsoide(h(0, -0.074, BOCA_Z - 0.003), (0.016, 0.028, 0.011))


def cabeza():
    S = Escultura(banda=0.0025)
    # cuello largo y fino, con los tendones marcados
    S.add(ConoRedondo(P_CUELLO + _v([0, 0.0, -0.06]), P_CRANEO + _v([0, 0.01, 0.02]), 0.046, 0.037, R_CUELLO), 0.0)
    for s in (-1, 1):
        S.add(ConoRedondo(h(0.05 * s, 0.0, -0.055), _v([0.017 * s, -0.052, 1.13]), 0.009, 0.008, R_CUELLO), 0.016)
    # saco vocal bajo la mandíbula
    S.add(Elipsoide(SACO, SACO_R, R_GARGANTA), 0.016)
    # cráneo alargado hacia atrás y arriba
    S.add(Elipsoide(h(0, 0.04, 0.035), (0.08, 0.13, 0.095), R_CABEZA, rot=rot_euler(0.42, 0, 0)), 0.03)
    # cara estrecha
    S.add(Elipsoide(h(0, -0.045, -0.03), (0.06, 0.055, 0.08), R_CABEZA), 0.045)
    S.add(Elipsoide(h(0, -0.088, BOCA_Z), (0.025, 0.018, 0.02), R_CABEZA), 0.02)
    for s in (-1, 1):
        # pómulos altos
        S.add(Elipsoide(h(0.041 * s, -0.078, -0.03), (0.012, 0.024, 0.008), R_CABEZA, rot=rot_euler(0, 0, 0.45 * s)), 0.03)
        # mandíbula
        S.add(ConoRedondo(h(0.046 * s, -0.02, -0.07), h(0.012 * s, -0.085, -0.11), 0.015, 0.012, R_MANDIBULA), 0.02)
        # arco superciliar pesado sobre los ojos
        S.add(ConoRedondo(h(0.01 * s, -0.103, 0.02), h(0.062 * s, -0.068, 0.034), 0.0105, 0.007, R_CEJA), 0.014)
        # crestas laterales de resonancia
        S.add(ConoRedondo(h(0.058 * s, -0.05, 0.04), h(0.066 * s, 0.1, 0.08), 0.008, 0.006, R_CABEZA), 0.026)
    S.add(Esfera(MENTON, 0.0125, R_MANDIBULA), 0.012)
    # cresta central
    S.add(ConoRedondo(h(0, -0.098, 0.045), h(0, 0.0, 0.122), 0.006, 0.007, R_CABEZA), 0.02)
    S.add(ConoRedondo(h(0, 0.0, 0.122), h(0, 0.13, 0.1), 0.007, 0.006, R_CABEZA), 0.026)
    # puente nasal plano
    S.add(ConoRedondo(h(0, -0.1, 0.012), h(0, -0.112, -0.038), 0.0075, 0.0095, R_CABEZA), 0.018)
    # labios finos
    S.add(ConoRedondo(h(-0.018, -0.103, BOCA_Z + 0.004), h(0.018, -0.103, BOCA_Z + 0.004), 0.0033, 0.0033, R_CABEZA), 0.006)
    S.add(ConoRedondo(h(-0.016, -0.1, BOCA_Z - 0.005), h(0.016, -0.1, BOCA_Z - 0.005), 0.0035, 0.0035, R_MANDIBULA), 0.006)
    for s in (-1, 1):
        # cuencas grandes (el ojo es otra malla)
        S.sub(Elipsoide(h(OJO[0] * s, OJO[1] - 0.004, OJO[2]), (0.0245, 0.024, 0.0172), rot=rot_ojo(s)), 0.006)
        # fosas nasales en ranura
        S.sub(Elipsoide(h(0.0075 * s, -0.113, -0.047), (0.0022, 0.006, 0.0065), rot=rot_euler(0.5, 0, 0.25 * s)), 0.002)
        # oídos: un orificio sin oreja
        S.sub(Esfera(h(0.071 * s, 0.015, -0.012), 0.0055), 0.003)
    # boca: ranura + cavidad (se abre al bajar la mandíbula)
    S.sub(Elipsoide(h(0, -0.105, BOCA_Z), (0.019, 0.012, 0.0018)), 0.0015)
    S.sub(cavidad_boca(), 0.003)
    S.desplazar.append(_detalle_piel)
    return S


def _detalle_piel(p, d, reg):
    q = p - H
    out = 0.00014 * fbm(p * 380.0, 2, 8)
    # anillos del cuello
    en_cuello = smoothstep(H[2] - 0.12, H[2] - 0.15, p[:, 2]) * smoothstep(1.1, 1.14, p[:, 2]) * smoothstep(-0.075, -0.05, q[:, 1])
    out -= 0.00045 * en_cuello * np.maximum(np.sin(p[:, 2] * 520.0 + ruido(p * 40.0, 5) * 1.5), 0.0) ** 3
    # venas en relieve en sienes y cráneo
    craneo = smoothstep(-0.02, 0.03, q[:, 2]) * smoothstep(0.03, 0.06, np.abs(q[:, 0]) + np.maximum(q[:, 1], 0) * 0.6)
    n = ruido(p * _v([28.0, 12.0, 28.0]) + fbm(p * 20.0, 2, 3)[:, None] * 0.3, 17)
    out += 0.00055 * craneo * smoothstep(0.07, 0.0, np.abs(n))
    # arrugas finas del saco vocal
    ds = np.linalg.norm((p - SACO) / _v(SACO_R), axis=1)
    out += 0.0003 * smoothstep(1.3, 0.8, ds) * np.sin(p[:, 2] * 700.0 + p[:, 0] * 200.0)
    return out


def colores_cabeza(v, n):
    q = v - H
    c = np.tile(_v(PIEL), (len(v), 1))
    c *= 1.0 + fbm(v * 45.0, 3, 5)[:, None] * 0.07
    # pigmento dorsal en manchas (cráneo y nuca)
    dorsal = (smoothstep(0.0, 0.08, q[:, 1] + q[:, 2] * 0.6) * smoothstep(-0.2, 0.5, n[:, 1] + n[:, 2]))[:, None]
    manchas = smoothstep(0.05, 0.2, fbm(v * _v([30.0, 18.0, 30.0]), 3, 12))[:, None]
    c = c * (1 - dorsal * manchas * 0.75) + _v(PIGMENTO) * dorsal * manchas * 0.75
    # banda oscura de la cresta central
    cresta = (smoothstep(0.01, 0.0, np.abs(q[:, 0])) * smoothstep(0.02, 0.05, q[:, 2]))[:, None]
    c = c * (1 - cresta * 0.5) + _v(PIGMENTO) * cresta * 0.5
    # venas azules visibles bajo la piel translúcida
    nv = ruido(v * _v([28.0, 12.0, 28.0]) + fbm(v * 20.0, 2, 3)[:, None] * 0.3, 17)
    sienes = (smoothstep(0.035, 0.06, np.abs(q[:, 0])) * smoothstep(-0.06, 0.0, q[:, 2]) + smoothstep(-0.01, 0.04, q[:, 1]) + smoothstep(1.25, 1.2, v[:, 2]) * 0.6)
    vena = smoothstep(0.045, 0.0, np.abs(nv))[:, None] * 0.5 * np.clip(sienes, 0, 1)[:, None]
    c = c * (1 - vena) + _v(VENA) * vena
    # contorno de los ojos
    for s in (-1, 1):
        do = np.linalg.norm((q - _v([OJO[0] * s, OJO[1], OJO[2]])) / _v([0.032, 0.04, 0.026]), axis=1)
        w = smoothstep(1.2, 0.75, do)[:, None] * 0.7
        c = c * (1 - w) + _v([0.1, 0.1, 0.14]) * w
    # saco vocal claro con red de venas
    ds = np.linalg.norm((v - SACO) / _v(SACO_R), axis=1)
    w = smoothstep(1.35, 0.85, ds)[:, None]
    c = c * (1 - w * 0.6) + _v(PIEL_CLARA) * w * 0.6
    red = smoothstep(0.06, 0.0, np.abs(ruido(v * 90.0, 23)))[:, None] * w * 0.5
    c = c * (1 - red) + _v([0.35, 0.2, 0.32]) * red
    # labios, fosas, oídos
    lab = (np.exp(-((q[:, 2] - BOCA_Z) / 0.007) ** 2) * smoothstep(0.024, 0.016, np.abs(q[:, 0])) * (q[:, 1] < -0.09))[:, None]
    c = c * (1 - lab * 0.7) + _v(LABIO) * lab * 0.7
    for pt, r in (((0.0075, -0.113, -0.047), 0.007), ((-0.0075, -0.113, -0.047), 0.007), ((0.071, 0.015, -0.012), 0.009), ((-0.071, 0.015, -0.012), 0.009)):
        w = smoothstep(r, r * 0.4, np.linalg.norm(q - _v(pt), axis=1))[:, None] * 0.85
        c = c * (1 - w) + _v([0.06, 0.04, 0.06]) * w
    # interior de la boca
    dentro = smoothstep(0.002, -0.002, cavidad_boca().dist(v) - 0.002)[:, None]
    c = c * (1 - dentro) + _v(BOCA_INT) * dentro
    return np.clip(c, 0, 1)


def ojos():
    S = Escultura()
    for s in (-1, 1):
        S.add(Elipsoide(h(OJO[0] * s, OJO[1], OJO[2]), OJO_R, 0, rot=rot_ojo(s)), 0.0)
    return S


# ----------------------------------------------------------------------- collar traductor

def _base(eje):
    z = _v(eje) / np.linalg.norm(eje)
    x = np.cross(_v([0, -1, 0]), z)
    if np.linalg.norm(x) < 1e-3:
        x = _v([1, 0, 0])
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return np.stack([x, y, z], axis=1)


def collar():
    eje = P_CRANEO - P_CUELLO
    C = P_CUELLO + eje * 0.5
    R = _base(eje)
    radio = 0.046 + (0.037 - 0.046) * 0.62 + 0.004
    S = Escultura()
    S.add(Toro(C, radio, 0.0055, rot=R), 0.0)
    S.add(Toro(C + R[:, 2] * 0.011, radio - 0.001, 0.0035, rot=R), 0.004)
    frente = C + _v([0, -(radio + 0.006), 0])
    S.add(CajaRedonda(frente, (0.013, 0.004, 0.009), 0.002, rot=R), 0.003)
    return S, frente + _v([0, -0.0065, 0.0])


def lente(pos):
    S = Escultura()
    S.add(Esfera(pos, 0.0035), 0.0)
    return S


# ----------------------------------------------------------------------- huesos

def huesos_cuerpo(W_R, W_L):
    fr = (0, -1, 0)
    hs = [
        dict(nombre="raiz", cabeza=(0, 0.07, 0.45), cola=tuple(P_PELVIS), arriba=fr, padre=None),
        dict(nombre="cadera", cabeza=tuple(P_PELVIS), cola=tuple(P_LUMBAR), arriba=fr, padre="raiz"),
        dict(nombre="columna", cabeza=tuple(P_LUMBAR), cola=tuple(P_PECHO), arriba=fr, padre="cadera"),
        dict(nombre="pecho", cabeza=tuple(P_PECHO), cola=tuple(P_CUELLO), arriba=fr, padre="columna"),
        dict(nombre="cuello", cabeza=tuple(P_CUELLO), cola=tuple(P_CUELLO2), arriba=fr, padre="pecho"),
        dict(nombre="cuello2", cabeza=tuple(P_CUELLO2), cola=tuple(P_CRANEO), arriba=fr, padre="cuello"),
        dict(nombre="cabeza", cabeza=tuple(P_CRANEO), cola=tuple(P_CORONILLA), arriba=fr, padre="cuello2"),
        dict(nombre="mandibula", cabeza=tuple(BISAGRA), cola=tuple(MENTON), arriba=(0, -0.6, 0.8), padre="cabeza"),
        dict(nombre="garganta", cabeza=tuple(SACO), cola=tuple(SACO + _v([0, -0.03, 0])), arriba=(0, 0, 1), padre="cuello2"),
    ]
    for s, suf in ((-1, "_R"), (1, "_L")):
        c = h(CEJA[0] * s, CEJA[1], CEJA[2])
        hs.append(dict(nombre="ceja" + suf, cabeza=tuple(c), cola=tuple(c + _v([0, -0.015, 0])), arriba=(0, 0, 1), padre="cabeza"))
    for lado, s, W in ((-1, "_R", W_R), (1, "_L", W_L)):
        hm = espejo(HOMBRO, lado)
        c = espejo(CODO, lado)
        hs += [
            dict(nombre="clavicula" + s, cabeza=(0.03 * lado, -0.02, 1.09), cola=tuple(hm), arriba=(0, 0, 1), padre="pecho"),
            dict(nombre="brazo" + s, cabeza=tuple(hm), cola=tuple(c), arriba=(lado, 0.3, 0), padre="clavicula" + s),
            dict(nombre="antebrazo" + s, cabeza=tuple(c), cola=tuple(W), arriba=(0, 0, 1), padre="brazo" + s),
        ]
    return hs


def pesos_cabeza(v, dist_seg):
    """Pesos de la piel de cabeza y cuello: cadena del cuello por distancia y, encima,
    máscaras explícitas para mandíbula, saco vocal y arcos superciliares.
    dist_seg(nombre) -> distancias de v al hueso. Devuelve (nombres, W)."""
    q = v - H
    cadena = ["pecho", "cuello", "cuello2", "cabeza"]
    D = np.stack([dist_seg(n) for n in cadena], axis=1)
    W = 1.0 / np.maximum(D, 1e-4) ** 4
    # por encima de la base del cráneo todo es cabeza
    arriba = smoothstep(-0.07, -0.04, q[:, 2])
    W[:, 3] += arriba * 1e9
    W[:, 0] *= smoothstep(1.14, 1.08, v[:, 2])
    W /= W.sum(axis=1, keepdims=True)
    # mandíbula: bajo la línea de la boca y por delante de la bisagra
    jaw = smoothstep(BOCA_Z + 0.003, BOCA_Z - 0.006, q[:, 2]) * smoothstep(0.005, -0.03, q[:, 1]) \
        * smoothstep(-0.15, -0.115, q[:, 2]) * smoothstep(0.07, 0.05, np.abs(q[:, 0]))
    jaw = np.maximum(jaw, (cavidad_boca().dist(v) < 0.004) * (q[:, 2] < BOCA_Z - 0.002) * 1.0)
    ds = np.linalg.norm((v - SACO) / _v(SACO_R), axis=1)
    saco = smoothstep(1.25, 0.6, ds) * (1 - jaw)
    ceja = np.zeros(len(v), np.float32)
    for s in (-1, 1):
        dc = np.linalg.norm(q - _v([CEJA[0] * s, CEJA[1], CEJA[2]]), axis=1)
        ceja = np.maximum(ceja, smoothstep(0.03, 0.008, dc))
    ceja *= (1 - jaw)
    resto = np.clip(1 - jaw - saco - ceja, 0, 1)[:, None]
    W = W * resto
    lado_ceja = np.where(v[:, 0] < 0, 0, 1)
    ceja_R = ceja * (lado_ceja == 0)
    ceja_L = ceja * (lado_ceja == 1)
    nombres = cadena + ["mandibula", "garganta", "ceja_R", "ceja_L"]
    W = np.concatenate([W, jaw[:, None], saco[:, None], ceja_R[:, None], ceja_L[:, None]], axis=1)
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    return nombres, W
