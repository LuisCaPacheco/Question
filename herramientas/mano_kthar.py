"""INTERROGART - mano kthar: la misma mano de cuatro dedos que la ilvari (mano_ilvari.py,
mismos huesos y convenio: mano DERECHA, palma abajo, +Y dedos, +Z dorso) con garras
córneas que salen del dorso de cada yema, escamas en los nudillos y piel moteada.
Las garras apuntan hacia delante y un poco hacia arriba: con la mano apoyada no tocan la mesa.
"""
import numpy as np
from sdf import ConoRedondo, Esfera, smoothstep, ruido, fbm, _v
import mano_ilvari as MI
from mano_ilvari import DEDOS, N_DEDOS, articulaciones, arriba_dedo, huesos, candidatos, r_dedo, R_MUNECA  # noqa: F401


def _norm(v):
    v = _v(v)
    return v / np.linalg.norm(v)


def garras(A, e=1.0):
    """Segmentos de cada garra: lista de (dedo, [p0, p1, p2], [r0, r1, r2])."""
    out = []
    for f in range(N_DEDOS):
        pts = A[f]
        dd = _norm(pts[3] - pts[2])
        up = arriba_dedo(f, pts, 2)
        largo = 0.022 if f else 0.017
        r0 = (DEDOS[f - 1]["r"] if f else 0.0074) * 0.62
        p0 = pts[3] - dd * 0.006 * e + up * r0 * 0.9
        p1 = pts[3] + dd * largo * 0.55 * e + up * r0 * 0.75
        p2 = pts[3] + dd * largo * e - up * r0 * 0.15
        out.append((f, [p0, p1, p2], [r0 * e, r0 * 0.62 * e, 0.0006 * e]))
    return out


def esculpir(escala=1.0, flex=(8.0, 16.0, 10.0), antebrazo=0.08):
    S, A = MI.esculpir(escala, flex, antebrazo)
    for f, p, r in garras(A, escala):
        reg = r_dedo(f, 2)
        S.add(ConoRedondo(p[0], p[1], r[0], r[1], reg), 0.002 * escala)
        S.add(ConoRedondo(p[1], p[2], r[1], r[2], reg), 0.0)
    # escamas duras sobre los nudillos
    for f in (1, 2, 3):
        S.add(Esfera(A[f][0] + _v([0, 0.001, 0.0075]) * escala, 0.0052 * escala, 1), 0.004 * escala)
    return S, A


def _dist_garras(v, A, e):
    d = np.full(len(v), 1e3, np.float32)
    for f, p, r in garras(A, e):
        for a, b, ra in ((p[0], p[1], r[0]), (p[1], p[2], r[1])):
            ab = b - a
            t = np.clip(((v - a) @ ab) / float(ab @ ab), 0, 1)
            d = np.minimum(d, np.linalg.norm(v - (a + t[:, None] * ab), axis=1) - ra)
    return d


def colores(v, n, A, piel, mancha, escama, garra, escala=1.0):
    """Piel gris verdosa moteada, palma más pálida, nudillos escamosos y garras negras
    con la base algo más clara."""
    e = escala
    c = np.tile(_v(piel), (len(v), 1))
    c *= 1.0 + fbm(v / e * 70.0, 3, 21)[:, None] * 0.1
    mot = smoothstep(0.08, 0.3, fbm(v / e * 45.0, 3, 5))[:, None]
    dorso = smoothstep(-0.3, 0.5, n[:, 2])[:, None]
    c = c * (1 - mot * dorso * 0.7) + _v(mancha) * mot * dorso * 0.7
    palma = smoothstep(0.1, -0.6, n[:, 2])[:, None]
    c = c * (1 - palma * 0.35) + _v([0.2, 0.22, 0.17]) * palma * 0.35
    for f in range(N_DEDOS):
        for k in (0, 1, 2):
            w = np.exp(-(np.linalg.norm(v - A[f][k], axis=1) / (0.009 * e)) ** 2)[:, None] * dorso * 0.55
            c = c * (1 - w) + _v(escama) * w
    dg = _dist_garras(v, A, e)
    w = smoothstep(0.0012 * e, -0.0004 * e, dg)[:, None]
    # la garra aclara hacia la base (queratina vieja)
    base = np.zeros(len(v), np.float32)
    for f, p, r in garras(A, e):
        base = np.maximum(base, np.exp(-(np.linalg.norm(v - p[0], axis=1) / (0.006 * e)) ** 2))
    col_g = _v(garra) * (1 - base[:, None] * 0.6) + _v([0.16, 0.14, 0.1]) * base[:, None] * 0.6
    c = c * (1 - w) + col_g * w
    return np.clip(c, 0, 1)
