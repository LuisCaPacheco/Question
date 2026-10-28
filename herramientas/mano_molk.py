"""INTERROGART - mano molk (Gruul): tres dedos enormes y un pulgar, de roca viva.
Mismo convenio y mismos huesos que mano_ilvari.py (mano DERECHA, palma abajo, +Y dedos,
+Z dorso, -X hacia el pulgar; dedo0 = pulgar, dedo1..3), así que Ilvari.gd la anima igual.
Rasgos: placas de piedra en el dorso y en cada falange, nudillos como cantos rodados, uñas
de obsidiana romas y grietas de magma (grietas() da la máscara de emisión).
"""
import numpy as np
from sdf import (Escultura, Esfera, Elipsoide, ConoRedondo, CajaRedonda,
                 rot_euler, smoothstep, ruido, fbm, _v)
from mano_ilvari import huesos, candidatos, arriba_dedo, r_dedo, R_MANO, R_MUNECA, N_DEDOS  # noqa: F401


def _norm(v):
    v = _v(v)
    return v / np.linalg.norm(v)


def _dir(yaw, theta):
    return _v([np.sin(yaw) * np.cos(theta), np.cos(yaw) * np.cos(theta), -np.sin(theta)])


DEDOS = [
    # x MCP, y MCP, longitudes de las falanges, radio base, yaw (grados)
    dict(x=-0.031, y=0.112, L=(0.05, 0.037, 0.03), r=0.0175, yaw=-9.0),
    dict(x=0.0, y=0.118, L=(0.054, 0.04, 0.032), r=0.018, yaw=0.0),
    dict(x=0.031, y=0.11, L=(0.047, 0.035, 0.028), r=0.0168, yaw=9.0),
]


def articulaciones(flex=(8.0, 16.0, 10.0), escala=1.0):
    res = {}
    for i, d in enumerate(DEDOS):
        f = i + 1
        yaw = np.radians(d["yaw"])
        p0 = _v([d["x"], d["y"], 0.006]) * escala
        th = 0.0
        pts = [p0]
        for k in range(3):
            th += np.radians(flex[k])
            pts.append(pts[-1] + _dir(yaw, th) * d["L"][k] * escala)
        res[f] = pts
    t0 = _v([-0.036, 0.026, -0.008]) * escala
    t1 = t0 + _norm([-0.7, 0.66, -0.14]) * 0.054 * escala
    t2 = t1 + _norm([-0.36, 0.9, -0.16]) * 0.038 * escala
    t3 = t2 + _norm([-0.16, 0.95, -0.24]) * 0.03 * escala
    res[0] = [t0, t1, t2, t3]
    return res


def grietas(p, escala=1.0):
    """Red de grietas (0..1): cruces por cero de un ruido deformado. La usan la escultura
    (surco), el color y la máscara de emisión."""
    q = p / escala * 16.0
    q = q + fbm(q * 0.6, 2, 71)[:, None] * 0.8
    n = np.abs(ruido(q, 73))
    fino = np.abs(ruido(q * 2.3, 79))
    return np.maximum(smoothstep(0.045, 0.01, n), smoothstep(0.02, 0.005, fino) * 0.45)


def _roca(p, e):
    """Relieve de piedra: facetas (ruido con crestas) y poros."""
    r = (1.0 - np.abs(ruido(p / e * 55.0, 61))) ** 3
    return 0.0011 * e * r + 0.0005 * e * fbm(p / e * 140.0, 2, 63)


def esculpir(escala=1.0, flex=(8.0, 16.0, 10.0), antebrazo=0.1):
    e = escala
    A = articulaciones(flex, e)
    rng = np.random.default_rng(9)
    S = Escultura(banda=0.004 * e)
    S.add(ConoRedondo((0, -antebrazo * e, 0.0), (0, 0.02 * e, -0.001 * e), 0.046 * e, 0.042 * e, R_MUNECA, aplastar=(1.0, 0.72)), 0.0)
    # palma ancha y gruesa
    S.add(CajaRedonda((0.0, 0.065 * e, 0.0), (0.038 * e, 0.042 * e, 0.009 * e), 0.013 * e, R_MANO), 0.016 * e)
    S.add(Elipsoide((-0.036 * e, 0.04 * e, -0.01 * e), (0.022 * e, 0.034 * e, 0.016 * e), R_MANO, rot=rot_euler(0, 0, np.radians(30))), 0.012 * e)
    # placas del dorso
    for k in range(5):
        c = _v([rng.uniform(-0.028, 0.028), rng.uniform(0.025, 0.09), 0.019]) * e
        S.add(CajaRedonda(c, (rng.uniform(0.012, 0.018) * e, rng.uniform(0.012, 0.02) * e, 0.004 * e), 0.003 * e, R_MANO,
                          rot=rot_euler(rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), rng.uniform(-0.6, 0.6))), 0.006 * e)
    for f in (1, 2, 3):
        pts = A[f]
        r0 = DEDOS[f - 1]["r"] * e
        radios = [r0, r0 * 0.9, r0 * 0.82, r0 * 0.76]
        # nudillo: canto rodado
        S.add(Esfera(pts[0] + _v([0, -0.002, 0.006]) * e, r0 * 1.15, R_MANO), 0.008 * e)
        for k in range(3):
            up = arriba_dedo(f, pts, k)
            S.add(ConoRedondo(pts[k], pts[k + 1], radios[k], radios[k + 1], r_dedo(f, k), aplastar=(1.0, 0.9), arriba=up), 0.004 * e)
            # placa sobre la falange
            d = _norm(pts[k + 1] - pts[k])
            c = (pts[k] + pts[k + 1]) * 0.5 + up * radios[k + 1] * 0.75
            S.add(CajaRedonda(c, (radios[k + 1] * 0.8, np.linalg.norm(pts[k + 1] - pts[k]) * 0.38, 0.0035 * e), 0.003 * e, r_dedo(f, k),
                              rot=np.stack([np.cross(d, up), d, up], axis=1)), 0.003 * e)
            if k < 2:
                S.add(Esfera(pts[k + 1], radios[k + 1] * 1.06, r_dedo(f, k + 1)), 0.004 * e)
        # uña de obsidiana, roma
        d = _norm(pts[3] - pts[2])
        up = arriba_dedo(f, pts, 2)
        S.add(ConoRedondo(pts[3] - d * 0.008 * e + up * radios[3] * 0.5, pts[3] + d * 0.013 * e - up * radios[3] * 0.1, radios[3] * 0.75, 0.003 * e,
                          r_dedo(f, 2)), 0.003 * e)
    t = A[0]
    rt = [0.022 * e, 0.018 * e, 0.016 * e, 0.014 * e]
    for k in range(3):
        up = arriba_dedo(0, t, k)
        S.add(ConoRedondo(t[k], t[k + 1], rt[k], rt[k + 1], r_dedo(0, k), aplastar=(1.0, 0.88), arriba=up), 0.014 * e if k == 0 else 0.004 * e)
        if k < 2:
            S.add(Esfera(t[k + 1], rt[k + 1] * 1.05, r_dedo(0, k + 1)), 0.004 * e)
    d = _norm(t[3] - t[2])
    up = arriba_dedo(0, t, 2)
    S.add(ConoRedondo(t[3] - d * 0.008 * e + up * rt[3] * 0.5, t[3] + d * 0.012 * e, rt[3] * 0.72, 0.003 * e, r_dedo(0, 2)), 0.003 * e)

    def detalle(p, dd, reg):
        return _roca(p, e) - 0.0016 * e * grietas(p, e)
    S.desplazar.append(detalle)
    return S, A


def colores(v, n, A, piel, mancha, suciedad, escala=1.0):
    e = escala
    c = np.tile(_v(piel), (len(v), 1))
    c *= 1.0 + fbm(v / e * 40.0, 3, 21)[:, None] * 0.25
    mot = smoothstep(0.0, 0.35, fbm(v / e * 25.0, 3, 5))[:, None] * 0.6
    c = c * (1 - mot) + _v(mancha) * mot
    # aristas más claras (piedra gastada) y polvo en el dorso
    c *= 1.0 + 0.5 * ((1.0 - np.abs(ruido(v / e * 55.0, 61))) ** 6)[:, None]
    polvo = smoothstep(0.2, 0.8, n[:, 2])[:, None] * suciedad * 0.25
    c = c * (1 - polvo) + _v([0.16, 0.14, 0.12]) * polvo
    # uñas de obsidiana (la punta de cada dedo)
    for f in range(N_DEDOS):
        w = smoothstep(0.016 * e, 0.009 * e, np.linalg.norm(v - A[f][3], axis=1))[:, None]
        c = c * (1 - w) + _v([0.008, 0.007, 0.008]) * w
    # el fondo de las grietas, rojo oscuro (la emisión hace el resto)
    g = grietas(v, e)[:, None]
    c = c * (1 - g) + _v([0.35, 0.06, 0.01]) * g
    return np.clip(c, 0, 1)


def emision(v, escala=1.0):
    """Máscara de emisión: solo brillan las grietas gruesas (las finas apenas)."""
    return grietas(v, escala) ** 2
