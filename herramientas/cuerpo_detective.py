"""INTERROGART - el agente (jugador): cuerpo completo sentado a la mesa, traje y corbata.
Coordenadas de Blender = coordenadas de la sala de Godot rotadas: Godot (x, y, z) = Blender (x, z, -y).
El agente mira hacia +Y de Blender (hacia el sospechoso). Mesa: z = 0.795, borde cercano y = -0.2.
"""
import numpy as np
from sdf import (Escultura, Esfera, Elipsoide, ConoRedondo, CajaRedonda, Toro, Funcion,
                 rot_euler, rot_matriz, smoothstep, smin, smax, ruido, fbm, _v)
import mano as M

MESA = 0.795
OJO = _v([0.0, -0.45, 1.24])
HOMBRO = _v([0.19, -0.515, 1.03])
CODO = _v([0.255, -0.33, 0.83])
MUNECA_XY = _v([0.205, -0.065])
YAW_MANO = 0.18          # rad: los dedos giran hacia el centro
PITCH_MANO = np.radians(4.0)
FLEX_REPOSO = (6.0, 14.0, 8.0)

# columna (de la pelvis al cuello)
P_PELVIS = _v([0.0, -0.705, 0.56])
P_LUMBAR = _v([0.0, -0.67, 0.72])
P_PECHO = _v([0.0, -0.615, 0.90])
P_CUELLO = _v([0.0, -0.575, 1.06])
P_CRANEO = _v([0.0, -0.55, 1.20])
P_CORONILLA = _v([0.0, -0.54, 1.36])
CADERA_J = _v([0.1, -0.705, 0.55])
RODILLA = _v([0.115, -0.285, 0.565])
TOBILLO = _v([0.125, -0.24, 0.10])
PUNTA_PIE = _v([0.13, -0.10, 0.035])

LEAN = -0.28   # rotacion en X del torso (arriba hacia +Y)

# regiones
R_TORSO_B, R_TORSO_A, R_HOMBRO, R_BRAZO, R_ANTEBRAZO, R_CUELLO_CH = 1, 2, 3, 4, 5, 6
R_CUELLO, R_CABEZA = 20, 21
R_PELVIS, R_MUSLO, R_PIERNA, R_PIE = 30, 31, 32, 33


def espejo(p, lado):
    return _v([p[0] * lado, p[1], p[2]])


def mano_transform(lado):
    """Rotacion y posicion de la muñeca (mano en reposo sobre la mesa)."""
    R = rot_matriz((0, 0, 1), YAW_MANO * lado) @ rot_matriz((1, 0, 0), PITCH_MANO)
    return R


def muneca(lado, z):
    return _v([MUNECA_XY[0] * lado, MUNECA_XY[1], z])


def a_mundo(v_local, lado, W):
    """Puntos de la mano derecha local -> mundo para el lado dado (refleja X si lado=-1)."""
    R = mano_transform(1)
    p = v_local @ R.T
    p = p + _v([MUNECA_XY[0], MUNECA_XY[1], W])
    if lado < 0:
        p = p * _v([-1, 1, 1])
    return p


def altura_muneca(v_local_min_z_pts):
    """Altura de la muñeca para que el punto mas bajo de la mano toque la mesa."""
    R = mano_transform(1)
    z = (v_local_min_z_pts @ R.T)[:, 2]
    return MESA + 0.0015 - z.min()


# ----------------------------------------------------------------------- chaqueta

def _torso(S, region_b=R_TORSO_B, region_a=R_TORSO_A, inflar=0.0, k=1.0):
    L = rot_euler(LEAN, 0, 0)
    S.add(Elipsoide((0, -0.71, 0.6), (0.19 + inflar, 0.14 + inflar, 0.1 + inflar), region_b), 0.0)
    S.add(Elipsoide((0, -0.672, 0.74), (0.163 + inflar, 0.113 + inflar, 0.13 + inflar), region_b, rot=L), 0.07 * k)
    S.add(Elipsoide((0, -0.615, 0.895), (0.182 + inflar, 0.122 + inflar, 0.15 + inflar), region_a, rot=L), 0.07 * k)
    S.add(ConoRedondo(espejo(HOMBRO, -1) + _v([0.03, -0.02, -0.01]), HOMBRO + _v([-0.03, -0.02, -0.01]), 0.07 + inflar, 0.07 + inflar, R_HOMBRO,
                      aplastar=(1.0, 0.85), arriba=(0, 0.3, 1)), 0.06 * k)


def _manga(S, lado, W, cuff_end, inflar=0.0):
    h = espejo(HOMBRO, lado)
    c = espejo(CODO, lado)
    S.add(Esfera(h + _v([0.012 * lado, 0.0, 0.012]), 0.066 + inflar, R_HOMBRO), 0.03)
    S.add(ConoRedondo(h, c, 0.061 + inflar, 0.051 + inflar, R_BRAZO), 0.03)
    # antebrazo: seccion algo aplastada (apoya en la mesa) y eje algo elevado
    S.add(ConoRedondo(c, cuff_end, 0.05 + inflar, 0.0445 + inflar, R_ANTEBRAZO, aplastar=(1.0, 0.8), arriba=(0, 0, 1)), 0.025)


def chaqueta(W_R, W_L, cuff_R, cuff_L):
    S = Escultura(banda=0.018)
    _torso(S)
    for lado, W, ce in ((1, W_R, cuff_R), (-1, W_L, cuff_L)):
        _manga(S, lado, W, ce)
    # cuello de la chaqueta (por detras del cuello)
    S.add(Toro((0, -0.585, 1.055), 0.072, 0.017, R_CUELLO_CH, rot=rot_euler(LEAN * 0.9, 0, 0)), 0.02)
    # bajo: la chaqueta termina sobre los muslos
    S.sub(CajaRedonda((0, -0.6, 0.35), (0.5, 0.5, 0.2), 0.0), 0.01)
    # hueco del cuello
    S.sub(ConoRedondo((0, -0.6, 1.0), (0, -0.55, 1.25), 0.058, 0.058), 0.006)
    # huecos de las bocamangas (se ve el puño de la camisa dentro)
    for lado, ce in ((1, cuff_R), (-1, cuff_L)):
        c = espejo(CODO, lado)
        d = (ce - c) / np.linalg.norm(ce - c)
        S.sub(ConoRedondo(ce - d * 0.05, ce + d * 0.03, 0.035, 0.035, aplastar=(1.0, 0.78), arriba=(0, 0, 1)), 0.003)
    S.desplazar.append(_detalle_chaqueta(cuff_R, cuff_L))
    return S


def _v_abertura(p):
    """Mascara del escote en V de la chaqueta (1 dentro de la V) y del borde de las solapas."""
    z = p[:, 2]
    t = np.clip((z - 0.70) / 0.36, 0, 1)
    w = 0.1 * t ** 0.85
    frente = smoothstep(-0.62, -0.55, p[:, 1])
    dentro_v = smoothstep(0.004, -0.004, np.abs(p[:, 0]) - w) * frente * (z > 0.69)
    ancho_sol = 0.012 + 0.052 * np.sin(np.clip(t, 0, 1) * np.pi * 0.95) ** 0.7
    solapa = smoothstep(0.003, -0.002, np.abs(p[:, 0]) - (w + ancho_sol)) * (1 - dentro_v) * frente * (z > 0.71) * (z < 1.07)
    return dentro_v, solapa, w


def _detalle_chaqueta(cuff_R, cuff_L):
    def fn(p, d, reg):
        out = np.zeros(len(p), np.float32)
        dentro_v, solapa, w = _v_abertura(p)
        out -= 0.013 * dentro_v            # escote: hundido para ver la camisa
        out += 0.0042 * solapa             # solapas en relieve
        # costura de la solapa (surco fino)
        out -= 0.0009 * np.exp(-((np.abs(p[:, 0]) - w - 0.002) / 0.0012) ** 2) * (p[:, 2] > 0.71) * smoothstep(-0.62, -0.55, p[:, 1])
        # boton
        bt = _v([0.0, -0.0, 0.715])
        db = np.sqrt(p[:, 0] ** 2 + (p[:, 2] - 0.712) ** 2)
        out += 0.004 * smoothstep(0.0105, 0.0085, db) * smoothstep(-0.62, -0.55, p[:, 1])
        # pliegues de tela: codos y bocamangas, y ondulacion suave general
        for ce, lado in ((cuff_R, 1), (cuff_L, -1)):
            c = espejo(CODO, lado)
            dd = np.linalg.norm(p - c, axis=1)
            fold = np.sin((p[:, 1] * 0.8 + p[:, 2] * 0.6) * 180.0 + ruido(p * 18.0, 4) * 3.0)
            out += 0.0022 * fold * np.exp(-(dd / 0.07) ** 2)
            dc = np.linalg.norm(p - ce, axis=1)
            out += 0.0015 * np.sin(p[:, 1] * 260.0 + ruido(p * 30.0, 9) * 2.0) * np.exp(-(dc / 0.05) ** 2)
        out += 0.0012 * fbm(p * 9.0, 3, 31)
        # arrugas de la espalda/cintura al estar sentado
        out += 0.0016 * np.sin(p[:, 2] * 120.0 + ruido(p * 12.0, 3) * 4.0) * smoothstep(0.8, 0.62, p[:, 2]) * smoothstep(0.5, 0.9, reg_espalda(p))
        return out
    return fn


def reg_espalda(p):
    return np.clip((-0.6 - p[:, 1]) * 10.0, 0, 1)


# ----------------------------------------------------------------------- camisa, corbata, puños

def camisa():
    S = Escultura()
    _torso(S, inflar=-0.006)
    # cuello de la camisa
    S.add(ConoRedondo((0, -0.585, 1.02), (0, -0.565, 1.105), 0.066, 0.064, R_CUELLO_CH, aplastar=(1.0, 0.95), arriba=(0, 1, 0)), 0.01)
    S.sub(ConoRedondo((0, -0.6, 1.0), (0, -0.55, 1.25), 0.057, 0.057), 0.002)
    # puntas del cuello
    for lado in (-1, 1):
        a = _v([0.022 * lado, -0.505, 1.07])
        b = _v([0.05 * lado, -0.49, 1.025])
        S.add(ConoRedondo(a, b, 0.012, 0.006, R_CUELLO_CH, aplastar=(1.0, 0.25), arriba=(0, 1, 0.3)), 0.004)
    S.sub(CajaRedonda((0, -0.6, 0.35), (0.5, 0.5, 0.2), 0.0), 0.01)
    return S


def frente_camisa(S_camisa, x, z):
    """y del frente de la camisa en (x, z) (buscando el cruce de la superficie)."""
    ys = np.linspace(-0.3, -0.7, 800).astype(np.float32)
    P = np.stack([np.full_like(ys, x), ys, np.full_like(ys, z)], axis=1)
    d = S_camisa.evaluar(P)
    i = np.argmax(d < 0)
    return float(ys[i])


def corbata(S_camisa):
    S = Escultura()
    yk = frente_camisa(S_camisa, 0.0, 1.035)

    def hoja(p):
        z = p[:, 2]
        ds = S_camisa.evaluar(p)
        w = 0.011 + np.clip(1.02 - z, 0, 1) * 0.1
        w = np.minimum(w, 0.041)
        placa = np.abs(ds - 0.0048) - 0.0022
        lados = np.abs(p[:, 0]) - w
        abajo = (0.735 + np.abs(p[:, 0]) * 0.75) - z
        arriba = z - 1.03
        frente = -0.62 - p[:, 1]
        return np.maximum.reduce([placa, lados, abajo, arriba, frente])

    S.add(Funcion(hoja), 0.0)
    S.add(Elipsoide((0, yk + 0.006, 1.037), (0.019, 0.011, 0.021)), 0.004)
    def pliegue(p, d, reg):
        return -0.0008 * np.exp(-(p[:, 0] / 0.0015) ** 2) * (p[:, 2] < 1.0) * (p[:, 2] > 0.95)
    S.desplazar.append(pliegue)
    return S


def puno_local():
    """Puño de la camisa en coordenadas locales de la mano derecha."""
    S = Escultura()
    S.add(ConoRedondo((0, -0.11, 0.002), (0, -0.034, 0.002), 0.035, 0.0345, 1, aplastar=(1.0, 0.8), arriba=(0, 0, 1)), 0.0)
    S.sub(ConoRedondo((0, -0.04, 0.002), (0, -0.02, 0.002), 0.031, 0.031, aplastar=(1.0, 0.72), arriba=(0, 0, 1)), 0.002)
    # boton del puño y gemelo
    S.add(Esfera((0.034, -0.05, 0.004), 0.0045), 0.001)
    return S


def reloj_local():
    """Reloj (en la mano derecha local; se refleja para la izquierda)."""
    S = Escultura()
    wr = ConoRedondo((0, -0.075, -0.001), (0, 0.012, -0.001), 0.0305, 0.0285, 0, aplastar=(1.0, 0.64))
    def correa(p):
        dw = wr.dist(p)
        return np.maximum(np.abs(dw - 0.0022) - 0.0016, np.abs(p[:, 1] + 0.03) - 0.0095)
    S.add(Funcion(correa), 0.0)
    S.add(ConoRedondo((0, -0.03, 0.0205), (0, -0.03, 0.0275), 0.0175, 0.0175, 1), 0.001)
    S.add(Esfera((0.02, -0.03, 0.025), 0.0022, 1), 0.0)
    return S


# ----------------------------------------------------------------------- cabeza y pelo

def cabeza():
    S = Escultura()
    S.add(ConoRedondo(P_CUELLO + _v([0, -0.005, -0.03]), P_CRANEO + _v([0, 0.005, -0.01]), 0.058, 0.054, R_CUELLO), 0.0)
    S.add(Elipsoide((0, -0.548, 1.285), (0.074, 0.095, 0.097), R_CABEZA), 0.03)
    S.add(Elipsoide((0, -0.495, 1.215), (0.06, 0.065, 0.062), R_CABEZA), 0.03)
    S.add(Esfera((0, -0.458, 1.18), 0.022, R_CABEZA), 0.02)
    S.add(ConoRedondo((0, -0.447, 1.27), (0, -0.428, 1.232), 0.011, 0.0135, R_CABEZA), 0.012)
    S.add(ConoRedondo((-0.045, -0.462, 1.285), (0.045, -0.462, 1.285), 0.014, 0.014, R_CABEZA), 0.02)
    for lado in (-1, 1):
        S.add(Elipsoide((0.052 * lado, -0.47, 1.24), (0.02, 0.018, 0.016), R_CABEZA), 0.02)
        S.add(Elipsoide((0.078 * lado, -0.55, 1.255), (0.011, 0.029, 0.033), R_CABEZA, rot=rot_euler(0, 0.25 * lado, 0)), 0.006)
        S.sub(Esfera((0.033 * lado, -0.447, 1.262), 0.012), 0.006)
        S.add(Esfera((0.033 * lado, -0.452, 1.262), 0.0115, R_CABEZA), 0.003)
        # mandibula
        S.add(ConoRedondo((0.058 * lado, -0.54, 1.22), (0.02 * lado, -0.47, 1.175), 0.018, 0.016, R_CABEZA), 0.02)
    def poros(p, d, reg):
        return 0.00025 * fbm(p * 400.0, 2, 8)
    S.desplazar.append(poros)
    return S


def _linea_pelo(p):
    y = p[:, 1]
    # altura minima del pelo segun la posicion delante/detras
    return np.interp(y, [-0.66, -0.6, -0.55, -0.5, -0.47, -0.44], [1.19, 1.215, 1.265, 1.30, 1.325, 1.35]).astype(np.float32)


def pelo():
    S = Escultura()
    craneo = Elipsoide((0, -0.548, 1.285), (0.074, 0.095, 0.097))
    def casco(p):
        d = craneo.dist(p) - 0.0075
        return smax(d, _linea_pelo(p) - p[:, 2], 0.004)
    S.add(Funcion(casco), 0.0)
    def mechones(p, d, reg):
        a = p[:, 0] * 700.0 + ruido(p * 90.0, 4) * 2.5
        return 0.0006 * np.sin(a) * smoothstep(0.0, 0.004, p[:, 2] - _linea_pelo(p)) + 0.0007 * fbm(p * 60.0, 2, 5)
    S.desplazar.append(mechones)
    return S


# ----------------------------------------------------------------------- pantalon y zapatos

def pantalon():
    S = Escultura()
    S.add(Elipsoide((0, -0.705, 0.575), (0.185, 0.14, 0.105), R_PELVIS), 0.0)
    for lado in (-1, 1):
        S.add(ConoRedondo(espejo(CADERA_J, lado), espejo(RODILLA, lado), 0.088, 0.062, R_MUSLO), 0.05)
        S.add(ConoRedondo(espejo(RODILLA, lado), espejo(TOBILLO, lado) + _v([0, 0, 0.03]), 0.058, 0.046, R_PIERNA), 0.02)
    def arrugas(p, d, reg):
        return 0.0018 * np.sin(p[:, 1] * 90.0 + p[:, 2] * 40.0 + ruido(p * 14.0, 6) * 3.0) * smoothstep(0.62, 0.5, p[:, 2]) \
            + 0.0009 * fbm(p * 10.0, 2, 17)
    S.desplazar.append(arrugas)
    return S


def zapatos():
    S = Escultura()
    for lado in (-1, 1):
        t = espejo(TOBILLO, lado)
        pp = espejo(PUNTA_PIE, lado)
        S.add(ConoRedondo(t + _v([0, -0.03, -0.045]), pp + _v([0, 0, -0.005]), 0.042, 0.032, R_PIE, aplastar=(0.95, 0.72), arriba=(0, 0, 1)), 0.0)
        S.add(ConoRedondo(t + _v([0, -0.02, -0.03]), t + _v([0, 0.0, 0.02]), 0.043, 0.04, R_PIE), 0.02)
    S.sub(CajaRedonda((0, -0.2, -0.05), (0.5, 0.5, 0.05), 0.0), 0.0)
    return S


# ----------------------------------------------------------------------- huesos

def huesos_cuerpo(W_R, W_L):
    hs = [
        dict(nombre="raiz", cabeza=(0, -0.705, 0.45), cola=tuple(P_PELVIS), arriba=(0, 1, 0), padre=None),
        dict(nombre="cadera", cabeza=tuple(P_PELVIS), cola=tuple(P_LUMBAR), arriba=(0, 1, 0), padre="raiz"),
        dict(nombre="columna", cabeza=tuple(P_LUMBAR), cola=tuple(P_PECHO), arriba=(0, 1, 0), padre="cadera"),
        dict(nombre="pecho", cabeza=tuple(P_PECHO), cola=tuple(P_CUELLO), arriba=(0, 1, 0), padre="columna"),
        dict(nombre="cuello", cabeza=tuple(P_CUELLO), cola=tuple(P_CRANEO), arriba=(0, 1, 0), padre="pecho"),
        dict(nombre="cabeza", cabeza=tuple(P_CRANEO), cola=tuple(P_CORONILLA), arriba=(0, 1, 0), padre="cuello"),
    ]
    for lado, s, W in ((1, "_R", W_R), (-1, "_L", W_L)):
        h = espejo(HOMBRO, lado)
        c = espejo(CODO, lado)
        hs += [
            dict(nombre="clavicula" + s, cabeza=(0.03 * lado, -0.565, 1.035), cola=tuple(h), arriba=(0, 0, 1), padre="pecho"),
            dict(nombre="brazo" + s, cabeza=tuple(h), cola=tuple(c), arriba=(lado, -0.3, 0), padre="clavicula" + s),
            dict(nombre="antebrazo" + s, cabeza=tuple(c), cola=tuple(W), arriba=(0, 0, 1), padre="brazo" + s),
            dict(nombre="muslo" + s, cabeza=tuple(espejo(CADERA_J, lado)), cola=tuple(espejo(RODILLA, lado)), arriba=(0, 0, 1), padre="raiz"),
            dict(nombre="pierna" + s, cabeza=tuple(espejo(RODILLA, lado)), cola=tuple(espejo(TOBILLO, lado)), arriba=(0, 1, 0), padre="muslo" + s),
            dict(nombre="pie" + s, cabeza=tuple(espejo(TOBILLO, lado)), cola=tuple(espejo(PUNTA_PIE, lado)), arriba=(0, 0, 1), padre="pierna" + s),
        ]
    return hs
