"""INTERROGART - Vex'ahl, un kthar (mecánico del puerto orbital), sentado al otro lado de la mesa.
Mismo convenio y misma postura que cuerpo_ilvari.py (reutiliza su esqueleto de tronco y
brazos, así que el animador de Godot le sirve igual): Blender (x, y, z) = Godot (x, -z, y),
mira hacia -Y. Lado -1 = x negativa = su mano DERECHA (_R).
Rasgos: cráneo alargado hacia atrás con crestas óseas, ojos negros rasgados con el iris
encendido, rendijas nasales, boca sin labios con dientes de aguja y dos pinzas (mandíbulas
laterales) con hueso propio. Viste el mono naranja del penal con la placa K-3045-88.
"""
import numpy as np
from sdf import (Escultura, Esfera, Elipsoide, ConoRedondo, CajaRedonda,
                 rot_euler, smoothstep, ruido, fbm, _v)
from cuerpo_ilvari import (MESA, P_PELVIS, P_LUMBAR, P_PECHO, P_CUELLO, P_CUELLO2, P_CRANEO,
                           HOMBRO, CODO, MUNECA_XY, FLEX_REPOSO, CADERA_J, RODILLA, TOBILLO, LEAN,
                           R_TORSO_B, R_TORSO_A, R_HOMBRO, R_BRAZO, R_ANTEBRAZO, R_CUELLO_T, R_FALDA,
                           espejo, mano_transform, muneca, a_mundo, altura_muneca, puno)  # noqa: F401
import cuerpo_ilvari as IL

H = _v([0.0, -0.07, 1.34])           # centro de la cabeza
P_CORONILLA = _v([0.0, -0.01, 1.46])

R_CUELLO, R_CABEZA, R_MANDIBULA, R_CEJA, R_CRESTA = 20, 21, 22, 24, 25

OJO = _v([0.036, -0.09, 0.004])
OJO_R = (0.023, 0.0135, 0.013)
OJO_TILT = 0.45
BOCA_Z = -0.078
BISAGRA = H + _v([0.0, -0.005, -0.045])
MENTON = H + _v([0.0, -0.086, -0.114])
CEJA = _v([0.036, -0.1, 0.026])
# pinzas: base (bajo el pómulo), codo y punta; lado +1 (x>0)
PINZA = [_v([0.046, -0.068, -0.062]), _v([0.053, -0.096, -0.096]), _v([0.031, -0.113, -0.122])]

# colores (lineales)
PIEL = (0.1, 0.135, 0.095)
PIEL_CLARA = (0.2, 0.22, 0.16)
MANCHA = (0.028, 0.042, 0.024)
VENA = (0.03, 0.11, 0.05)
HUESO = (0.3, 0.27, 0.19)
QUITINA = (0.012, 0.01, 0.008)
BOCA_INT = (0.09, 0.01, 0.015)
DIENTE = (0.55, 0.5, 0.36)
ROPA = (0.38, 0.055, 0.006)
GRASA = (0.014, 0.022, 0.006)


def h(x, y, z):
    return H + _v([x, y, z])


def rot_ojo(s):
    return rot_euler(0.0, -OJO_TILT * s, 0.0)


def pinza(s):
    return [p * _v([s, 1, 1]) + H for p in PINZA]


# ----------------------------------------------------------------------- utilidades

def superficie(S, origen, direccion, maximo=0.3, paso=0.002):
    """Primer punto de la superficie de S saliendo de 'origen' (dentro) en 'direccion'."""
    d = _v(direccion) / np.linalg.norm(direccion)
    o = _v(origen)
    t = 0.0
    while t < maximo:
        if S.evaluar((o + d * (t + paso))[None])[0] > 0:
            a, b = t, t + paso
            for _ in range(20):
                m = (a + b) * 0.5
                if S.evaluar((o + d * m)[None])[0] > 0:
                    b = m
                else:
                    a = m
            return o + d * a
        t += paso
    return o + d * maximo


# ----------------------------------------------------------------------- cabeza

def _craneo(S):
    """Volúmenes grandes de la cabeza (sin crestas ni detalle)."""
    S.add(ConoRedondo(P_CUELLO + _v([0, 0.0, -0.06]), P_CRANEO + _v([0, 0.012, 0.02]), 0.056, 0.047, R_CUELLO), 0.0)
    for s in (-1, 1):
        # músculos del cuello, gruesos
        S.add(ConoRedondo(h(0.052 * s, 0.005, -0.06), _v([0.024 * s, -0.05, 1.12]), 0.012, 0.011, R_CUELLO), 0.018)
    # cráneo alargado hacia atrás y arriba, en dos lóbulos
    S.add(Elipsoide(h(0, 0.035, 0.03), (0.074, 0.115, 0.088), R_CABEZA, rot=rot_euler(0.45, 0, 0)), 0.03)
    S.add(Elipsoide(h(0, 0.115, 0.08), (0.05, 0.075, 0.05), R_CABEZA, rot=rot_euler(0.6, 0, 0)), 0.04)
    # cara
    S.add(Elipsoide(h(0, -0.04, -0.03), (0.062, 0.058, 0.078), R_CABEZA), 0.045)
    S.add(Elipsoide(h(0, -0.08, -0.072), (0.03, 0.028, 0.024), R_CABEZA), 0.02)
    for s in (-1, 1):
        S.add(Elipsoide(h(0.048 * s, -0.07, -0.022), (0.016, 0.026, 0.011), R_CABEZA, rot=rot_euler(0, 0, 0.5 * s)), 0.025)
        S.add(ConoRedondo(h(0.05 * s, -0.015, -0.07), h(0.013 * s, -0.079, -0.112), 0.014, 0.011, R_MANDIBULA), 0.02)
        # arco superciliar y su continuación hacia la nuca (cresta temporal)
        S.add(ConoRedondo(h(0.008 * s, -0.101, 0.022), h(0.064 * s, -0.06, 0.03), 0.011, 0.008, R_CEJA), 0.012)
        S.add(ConoRedondo(h(0.064 * s, -0.06, 0.03), h(0.068 * s, 0.07, 0.07), 0.008, 0.005, R_CABEZA), 0.02)
        # alvéolo de la pinza
        S.add(Esfera(pinza(s)[0], 0.0115, R_CABEZA), 0.012)
    S.add(Esfera(MENTON, 0.012, R_MANDIBULA), 0.012)
    # puente nasal plano
    S.add(ConoRedondo(h(0, -0.1, 0.012), h(0, -0.106, -0.04), 0.007, 0.009, R_CABEZA), 0.018)


def crestas(S0):
    """Espinas óseas: cinco en la línea media, hacia atrás, y dos en cada cresta temporal.
    Se apoyan en la superficie del cráneo S0. Devuelve [(base, punta, radio)]."""
    centro = h(0, 0.03, 0.0)
    out = []
    for i, (ang, largo, r) in enumerate(((-0.55, 0.014, 0.0075), (-0.18, 0.024, 0.01), (0.2, 0.03, 0.011),
                                         (0.58, 0.028, 0.0105), (0.95, 0.021, 0.009))):
        d = _v([0.0, np.sin(ang), np.cos(ang)])
        p = superficie(S0, centro, d)
        n = _v([0.0, np.sin(ang + 0.55), np.cos(ang + 0.55)])   # inclinadas hacia la nuca
        out.append((p - d * 0.006, p + n * largo, r))
    for s in (-1, 1):
        for y, largo in ((0.0, 0.012), (0.06, 0.016)):
            d = _v([0.9 * s, y * 3.0, 0.45])
            p = superficie(S0, h(0, y, 0.02), d)
            n = _v([0.5 * s, 0.75, 0.35])
            out.append((p - d / np.linalg.norm(d) * 0.004, p + n / np.linalg.norm(n) * largo, 0.0055))
    return out


def cavidad_boca():
    return Elipsoide(h(0, -0.08, BOCA_Z - 0.003), (0.02, 0.026, 0.011))


def cabeza():
    S0 = Escultura()
    _craneo(S0)
    S = Escultura(banda=0.0025)
    _craneo(S)
    for a, b, r in crestas(S0):
        S.add(ConoRedondo(a, b, r, 0.0012, R_CRESTA), 0.006)
    for s in (-1, 1):
        # cuencas rasgadas (el ojo es otra malla)
        S.sub(Elipsoide(h(OJO[0] * s, OJO[1] - 0.004, OJO[2]), (0.026, 0.021, 0.0165), rot=rot_ojo(s)), 0.005)
        # rendijas nasales
        S.sub(Elipsoide(h(0.0072 * s, -0.109, -0.036), (0.0022, 0.006, 0.0085), rot=rot_euler(0.4, 0, 0.35 * s)), 0.0018)
        # oídos: orificio con reborde
        S.sub(Esfera(h(0.069 * s, 0.02, -0.01), 0.005), 0.003)
    # boca: ranura sin labios + cavidad
    S.sub(Elipsoide(h(0, -0.108, BOCA_Z), (0.025, 0.012, 0.0018)), 0.0015)
    S.sub(cavidad_boca(), 0.003)
    S.desplazar.append(_detalle_piel)
    return S


def _detalle_piel(p, d, reg):
    q = p - H
    # piel curtida: bultitos (escamas finas) que se ven con luz rasante
    out = 0.00022 * (1.0 - np.abs(ruido(p * 330.0, 8))) ** 3
    out += 0.00012 * fbm(p * 150.0, 2, 3)
    # surcos de la frente y alrededor de los ojos
    frente = smoothstep(0.0, 0.03, q[:, 2]) * smoothstep(-0.05, -0.09, q[:, 1]) * smoothstep(0.05, 0.03, np.abs(q[:, 0]))
    out -= 0.0004 * frente * np.maximum(np.sin(q[:, 2] * 520.0 + ruido(p * 40.0, 4) * 1.5), 0.0) ** 4
    for s in (-1, 1):
        o = q - _v([OJO[0] * s, OJO[1], OJO[2]])
        r = np.linalg.norm(o / _v([0.04, 0.05, 0.03]), axis=1)
        ang = np.arctan2(o[:, 2], o[:, 0] * s)
        out -= 0.00028 * smoothstep(1.4, 0.95, r) * smoothstep(0.75, 0.9, r) * np.maximum(np.sin(ang * 14.0), 0) ** 3
    # crestas: hueso estriado
    cr = (reg == R_CRESTA) if reg is not None else np.zeros(len(p), bool)
    out += 0.00025 * cr * np.sin(p[:, 1] * 900.0 + p[:, 2] * 300.0)
    # pliegues laterales del cuello (como agallas cerradas)
    lado = smoothstep(0.03, 0.05, np.abs(q[:, 0]))
    cuello = smoothstep(-0.1, -0.13, q[:, 2]) * smoothstep(1.1, 1.14, p[:, 2]) * lado
    out -= 0.0006 * cuello * np.maximum(np.sin(p[:, 2] * 260.0), 0.0) ** 6
    return out


def colores_cabeza(v, n):
    q = v - H
    c = np.tile(_v(PIEL), (len(v), 1))
    c *= 1.0 + fbm(v * 50.0, 3, 5)[:, None] * 0.1
    # moteado oscuro, más denso en el cráneo y la nuca
    dorsal = np.clip(smoothstep(-0.02, 0.06, q[:, 2] + q[:, 1] * 0.5) + 0.35, 0, 1)[:, None]
    mot = smoothstep(0.05, 0.25, fbm(v * _v([38.0, 26.0, 38.0]), 3, 12))[:, None]
    c = c * (1 - mot * dorsal * 0.8) + _v(MANCHA) * mot * dorsal * 0.8
    # garganta y bajo la mandíbula más claras
    vientre = (smoothstep(-0.07, -0.12, q[:, 2]) * smoothstep(-0.3, -0.8, n[:, 2]))[:, None]
    c = c * (1 - vientre * 0.5) + _v(PIEL_CLARA) * vientre * 0.5
    # venas verdes en las sienes y el cuello
    nv = ruido(v * _v([30.0, 14.0, 30.0]) + fbm(v * 20.0, 2, 3)[:, None] * 0.3, 17)
    zona = np.clip(smoothstep(0.04, 0.065, np.abs(q[:, 0])) + smoothstep(-0.08, -0.13, q[:, 2]) * 0.8, 0, 1)
    vena = smoothstep(0.05, 0.0, np.abs(nv))[:, None] * 0.55 * zona[:, None]
    c = c * (1 - vena) + _v(VENA) * vena
    # crestas: hueso, con la punta oscura
    S = cabeza_sin_detalle()
    reg = S.regiones(v)
    cr = (reg == R_CRESTA)[:, None].astype(np.float32)
    punta = smoothstep(0.004, 0.02, S_dist_craneo(v))[:, None]
    hueso = _v(HUESO) * (1 - punta * 0.7) + _v(QUITINA) * punta * 0.7
    c = c * (1 - cr) + hueso * cr
    # antifaz oscuro alrededor de los ojos (como un depredador nocturno)
    for s in (-1, 1):
        o = (q - _v([OJO[0] * s, OJO[1], OJO[2]])) @ rot_ojo(s)
        do = np.linalg.norm(o / _v([0.038, 0.04, 0.024]), axis=1)
        w = smoothstep(1.25, 0.7, do)[:, None] * 0.85
        c = c * (1 - w) + _v([0.02, 0.025, 0.02]) * w
    # rendijas, oídos, boca
    for pt, r in (((0.0072, -0.109, -0.036), 0.009), ((-0.0072, -0.109, -0.036), 0.009),
                  ((0.069, 0.02, -0.01), 0.008), ((-0.069, 0.02, -0.01), 0.008)):
        w = smoothstep(r, r * 0.35, np.linalg.norm(q - _v(pt), axis=1))[:, None] * 0.9
        c = c * (1 - w) + _v([0.02, 0.012, 0.01]) * w
    lab = (np.exp(-((q[:, 2] - BOCA_Z) / 0.005) ** 2) * smoothstep(0.03, 0.02, np.abs(q[:, 0])) * (q[:, 1] < -0.095))[:, None]
    c = c * (1 - lab * 0.7) + _v([0.04, 0.03, 0.03]) * lab * 0.7
    dentro = smoothstep(0.002, -0.002, cavidad_boca().dist(v) - 0.002)[:, None]
    c = c * (1 - dentro) + _v(BOCA_INT) * dentro
    return np.clip(c, 0, 1)


_S_CR = None


def cabeza_sin_detalle():
    global _S_CR
    if _S_CR is None:
        S0 = Escultura()
        _craneo(S0)
        S = Escultura()
        _craneo(S)
        for a, b, r in crestas(S0):
            S.add(ConoRedondo(a, b, r, 0.0012, R_CRESTA), 0.006)
        _S_CR = (S, S0)
    return _S_CR[0]


def S_dist_craneo(v):
    """Distancia al cráneo sin crestas (para oscurecer las puntas de las espinas)."""
    cabeza_sin_detalle()
    return _S_CR[1].evaluar(v)


def ojos():
    S = Escultura()
    for s in (-1, 1):
        S.add(Elipsoide(h(OJO[0] * s, OJO[1], OJO[2]), OJO_R, 0, rot=rot_ojo(s)), 0.0)
    return S


def pinzas():
    """Dos mandíbulas laterales de quitina: base, codo y punta curvada hacia el mentón."""
    S = Escultura(banda=0.0015)
    for s in (-1, 1):
        a, b, c = pinza(s)
        S.add(ConoRedondo(a, b, 0.0085, 0.0066), 0.0)
        S.add(Esfera(b, 0.0072), 0.003)
        S.add(ConoRedondo(b, c, 0.0066, 0.0011), 0.003)
        # sierra en el borde interior
        for u in (0.25, 0.45, 0.65):
            p = b + (c - b) * u
            S.add(ConoRedondo(p, p + _v([-0.006 * s, -0.002, 0.001]), 0.0022, 0.0004), 0.001)

    def anillos(p, d, r):
        a = np.where(p[:, :1] < 0, pinza(-1)[0], pinza(1)[0])
        return 0.00012 * np.sin(np.linalg.norm(p - a, axis=1) * 900.0)
    S.desplazar.append(anillos)
    return S


def colores_pinza(v):
    col = np.zeros((len(v), 3), np.float32)
    for s in (-1, 1):
        a, b, c = pinza(s)
        m = ((v[:, 0] * s) > 0)[:, None]
        t = np.clip(((v - a) @ (c - a)) / float((c - a) @ (c - a)), 0, 1)[:, None]
        k = smoothstep(0.0, 0.3, t)
        cs = _v(PIEL) * (1 - k) + _v(QUITINA) * k
        cs = cs + _v([0.05, 0.04, 0.02]) * np.exp(-(np.linalg.norm(v - b, axis=1) / 0.006) ** 2)[:, None]
        col = np.where(m, cs, col)
    return np.clip(col, 0, 1)


def dientes():
    """Agujas en dos filas: las de arriba cuelgan de la cabeza, las de abajo van con la mandíbula."""
    sup, inf = Escultura(), Escultura()
    for fila, S, z0, dz in (("sup", sup, BOCA_Z + 0.0035, -0.0085), ("inf", inf, BOCA_Z - 0.0075, 0.0075)):
        n = 12
        for i in range(n):
            u = (i + 0.5) / n * 2 - 1
            x = u * 0.02
            y = -0.098 + (u * u) * 0.012
            ln = dz * (1.0 - 0.35 * abs(u))
            a = h(x, y, z0)
            b = h(x * 1.02, y - 0.002, z0 + ln)
            S.add(ConoRedondo(a, b, 0.0013, 0.0002), 0.0)
    return sup, inf


# ----------------------------------------------------------------------- mono del penal

R_PIERNA = R_FALDA


def mono(W_R, W_L):
    S = Escultura(banda=0.016)
    IL._torso(S, inflar=0.004)
    for lado, W in ((-1, W_R), (1, W_L)):
        hm = espejo(HOMBRO, lado)
        c = espejo(CODO, lado)
        pe = puno(lado, W)
        S.add(Esfera(hm + _v([0.006 * lado, 0.0, 0.004]), 0.052, R_HOMBRO), 0.035)
        S.add(ConoRedondo(hm, c, 0.047, 0.042, R_BRAZO), 0.03)
        S.add(ConoRedondo(c, pe, 0.042, 0.035, R_ANTEBRAZO, aplastar=(1.0, 0.82), arriba=(0, 0, 1)), 0.022)
        # puño elástico, algo fruncido
        d = (pe - c) / np.linalg.norm(pe - c)
        S.add(ConoRedondo(pe - d * 0.022, pe, 0.036, 0.034, R_ANTEBRAZO, aplastar=(1.0, 0.8), arriba=(0, 0, 1)), 0.006)
        S.sub(ConoRedondo(pe - d * 0.05, pe + d * 0.03, 0.03, 0.03, aplastar=(1.0, 0.78), arriba=(0, 0, 1)), 0.003)
        # perneras
        S.add(ConoRedondo(espejo(CADERA_J, lado), espejo(RODILLA, lado), 0.088, 0.07, R_PIERNA), 0.05)
        S.add(ConoRedondo(espejo(RODILLA, lado), espejo(TOBILLO, lado), 0.066, 0.06, R_PIERNA), 0.02)
    # cuello redondo con ribete, más ancho que el del ilvari (el cuello kthar es grueso)
    S.add(ConoRedondo(_v([0, -0.012, 1.04]), _v([0, -0.022, 1.12]), 0.074, 0.068, R_CUELLO_T), 0.03)
    S.sub(ConoRedondo(_v([0, -0.005, 1.0]), _v([0, -0.05, 1.26]), 0.06, 0.057), 0.004)
    # bolsillo en el pecho derecho (x < 0) con solapa
    S.add(CajaRedonda(_v([-0.075, -0.112, 0.93]), (0.03, 0.004, 0.034), 0.002, R_TORSO_A, rot=rot_euler(LEAN * 0.8, 0, 0)), 0.004)
    S.add(CajaRedonda(_v([-0.075, -0.121, 0.963]), (0.032, 0.004, 0.009), 0.002, R_TORSO_A, rot=rot_euler(LEAN * 0.8, 0, 0)), 0.002)
    S.sub(CajaRedonda((0, -0.2, -0.05), (0.6, 0.6, 0.06), 0.0), 0.0)
    S.desplazar.append(_detalle_mono(W_R, W_L))
    return S


def _cremallera(p):
    frente = smoothstep(0.0, -0.08, p[:, 1])
    return smoothstep(0.006, 0.003, np.abs(p[:, 0])) * frente * (p[:, 2] > 0.62) * (p[:, 2] < 1.1)


def _detalle_mono(W_R, W_L):
    def fn(p, d, reg):
        out = np.zeros(len(p), np.float32)
        # cremallera: tira en relieve con dientes
        cz = _cremallera(p)
        out += cz * (0.0012 + 0.0004 * np.sign(np.sin(p[:, 2] * 1400.0)))
        # costuras (hombros, laterales del pecho y ribete del cuello)
        for bx in (0.012, -0.012):
            out -= 0.0006 * np.exp(-((p[:, 0] - bx) / 0.0012) ** 2) * (p[:, 1] < -0.03) * (p[:, 2] > 0.62) * (p[:, 2] < 1.1)
        out -= 0.0008 * np.exp(-((p[:, 2] - 1.118) / 0.002) ** 2) * (p[:, 2] < 1.14)
        # pliegues de algodón basto: codos, sobacos, cintura y puños
        for lado in (-1, 1):
            c = espejo(CODO, lado)
            dd = np.linalg.norm(p - c, axis=1)
            fold = np.sin((p[:, 1] * 0.7 + p[:, 2] * 0.7) * 150.0 + ruido(p * 14.0, 4) * 3.0)
            out += 0.0028 * fold * np.exp(-(dd / 0.09) ** 2)
            W = W_R if lado < 0 else W_L
            dc = np.linalg.norm(p - W, axis=1)
            out += 0.0012 * np.sin(p[:, 1] * 300.0 + ruido(p * 28.0, 9) * 2.0) * np.exp(-(dc / 0.06) ** 2)
            ax = np.linalg.norm(p - espejo(HOMBRO, lado) - _v([-0.03 * lado, 0.0, -0.07]), axis=1)
            out += 0.0018 * np.sin(p[:, 2] * 220.0 + p[:, 1] * 80.0) * np.exp(-(ax / 0.06) ** 2)
        out += 0.0024 * np.sin(p[:, 2] * 90.0 + ruido(p * 10.0, 3) * 4.0) * smoothstep(0.82, 0.66, p[:, 2]) * smoothstep(0.45, 0.62, p[:, 2])
        # tela gastada
        out += 0.0009 * fbm(p * 9.0, 3, 31) + 0.00012 * ruido(p * 600.0, 2)
        return out
    return fn


def colores_mono(v):
    base = np.tile(_v(ROPA), (len(v), 1))
    # desteñido irregular (lavado industrial)
    base *= (1.0 + fbm(v * 14.0, 3, 7)[:, None] * 0.25)
    base = base * 0.85 + _v([0.42, 0.14, 0.05]) * 0.15 * smoothstep(0.0, 0.3, fbm(v * 6.0, 2, 44))[:, None]
    # manchas de grasa: mecánico. Puños, antebrazos, vientre y rodillas
    zona = np.clip(smoothstep(0.3, 0.1, np.abs(v[:, 0]) - 0.1) * smoothstep(0.62, 0.8, v[:, 2]) * 0.35
                   + smoothstep(0.9, 0.8, v[:, 2]) * smoothstep(-0.2, -0.45, v[:, 1]) * 0.9, 0, 1)
    g = smoothstep(0.1, 0.35, fbm(v * _v([22.0, 22.0, 30.0]), 4, 51))[:, None] * zona[:, None]
    base = base * (1 - g * 0.85) + _v(GRASA) * g * 0.85
    # salpicaduras pequeñas por todas partes
    sp = smoothstep(0.62, 0.68, ruido(v * 90.0, 61))[:, None] * 0.4
    base = base * (1 - sp) + _v(GRASA) * sp
    # cremallera metálica y ribete del cuello más oscuro
    cz = _cremallera(v)[:, None]
    base = base * (1 - cz) + _v([0.07, 0.065, 0.06]) * cz
    rib = (smoothstep(1.11, 1.12, v[:, 2]) * (v[:, 2] < 1.16))[:, None] * 0.5
    base = base * (1 - rib) + _v([0.2, 0.03, 0.004]) * rib
    return np.clip(base, 0, 1)


def placa_pos(S):
    """Punto del pecho izquierdo (x > 0) donde va la placa de preso, y su normal."""
    p = superficie(S, _v([0.075, 0.0, 0.93]), (0, -1, 0.0), 0.3, 0.001)
    e = 0.002
    g = _v([S.evaluar((p + _v(dx))[None])[0] - S.evaluar((p - _v(dx))[None])[0]
            for dx in ((e, 0, 0), (0, e, 0), (0, 0, e))])
    return p, g / np.linalg.norm(g)


# ----------------------------------------------------------------------- huesos

def huesos_cuerpo(W_R, W_L, placa=None):
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
    ]
    for s, suf in ((-1, "_R"), (1, "_L")):
        c = h(CEJA[0] * s, CEJA[1], CEJA[2])
        hs.append(dict(nombre="ceja" + suf, cabeza=tuple(c), cola=tuple(c + _v([0, -0.015, 0])), arriba=(0, 0, 1), padre="cabeza"))
        a, b, _ = pinza(s)
        hs.append(dict(nombre="pinza" + suf, cabeza=tuple(a), cola=tuple(b), arriba=(0, -1, 0), padre="cabeza"))
    if placa is not None:
        p, n = placa
        hs.append(dict(nombre="placa", cabeza=tuple(p), cola=tuple(p + n * 0.02), arriba=(0, 0, 1), padre="pecho", deform=False))
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
    """Cadena del cuello por distancia; mandíbula y arcos superciliares con máscaras."""
    q = v - H
    cadena = ["pecho", "cuello", "cuello2", "cabeza"]
    D = np.stack([dist_seg(n) for n in cadena], axis=1)
    W = 1.0 / np.maximum(D, 1e-4) ** 4
    arriba = smoothstep(-0.075, -0.045, q[:, 2])
    W[:, 3] += arriba * 1e9
    W[:, 0] *= smoothstep(1.14, 1.08, v[:, 2])
    W /= W.sum(axis=1, keepdims=True)
    jaw = smoothstep(BOCA_Z + 0.003, BOCA_Z - 0.006, q[:, 2]) * smoothstep(0.005, -0.03, q[:, 1]) \
        * smoothstep(-0.15, -0.118, q[:, 2]) * smoothstep(0.066, 0.048, np.abs(q[:, 0]))
    jaw = np.maximum(jaw, (cavidad_boca().dist(v) < 0.004) * (q[:, 2] < BOCA_Z - 0.002) * 1.0)
    # el alvéolo de la pinza es de la cabeza
    for s in (-1, 1):
        jaw *= smoothstep(0.012, 0.022, np.linalg.norm(v - pinza(s)[0], axis=1))
    ceja = np.zeros(len(v), np.float32)
    for s in (-1, 1):
        dc = np.linalg.norm(q - _v([CEJA[0] * s, CEJA[1], CEJA[2]]), axis=1)
        ceja = np.maximum(ceja, smoothstep(0.03, 0.008, dc))
    ceja *= (1 - jaw)
    resto = np.clip(1 - jaw - ceja, 0, 1)[:, None]
    W = W * resto
    ceja_R = ceja * (v[:, 0] < 0)
    ceja_L = ceja * (v[:, 0] >= 0)
    nombres = cadena + ["mandibula", "ceja_R", "ceja_L"]
    W = np.concatenate([W, jaw[:, None], ceja_R[:, None], ceja_L[:, None]], axis=1)
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    return nombres, W
