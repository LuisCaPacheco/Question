"""INTERROGART - mano ilvari: tres dedos largos y un pulgar oponible ("sus cuatro dedos").
Mismo convenio que mano.py (mano DERECHA, palma abajo): +Y hacia los dedos, +Z dorso,
-X hacia el pulgar, muñeca en el origen. Dedos: 0 = pulgar, 1..3.
Rasgos: falanges largas y finas, nudillos marcados, yemas abultadas (almohadillas
adhesivas), sin uñas: la punta es una placa córnea oscura (se pinta en colores()).
"""
import numpy as np
from sdf import (Escultura, Esfera, Elipsoide, ConoRedondo, CajaRedonda,
                 rot_euler, smoothstep, ruido, fbm, _v)

R_MANO = 1
R_MUNECA = 2


def r_dedo(f, k):
    return 10 + f * 3 + k


def _norm(v):
    v = _v(v)
    return v / np.linalg.norm(v)


def _dir(yaw, theta):
    return _v([np.sin(yaw) * np.cos(theta), np.cos(yaw) * np.cos(theta), -np.sin(theta)])


DEDOS = [
    # x MCP, y MCP, longitudes de las falanges, radio base, yaw (grados)
    dict(x=-0.0215, y=0.098, L=(0.056, 0.040, 0.030), r=0.0088, yaw=-6.0),
    dict(x=0.0005, y=0.104, L=(0.062, 0.044, 0.032), r=0.0091, yaw=0.0),
    dict(x=0.0215, y=0.096, L=(0.054, 0.038, 0.029), r=0.0085, yaw=7.0),
]
N_DEDOS = 1 + len(DEDOS)


def articulaciones(flex=(8.0, 16.0, 10.0), escala=1.0):
    res = {}
    for i, d in enumerate(DEDOS):
        f = i + 1
        yaw = np.radians(d["yaw"])
        p0 = _v([d["x"], d["y"], 0.004]) * escala
        th = 0.0
        pts = [p0]
        for k in range(3):
            th += np.radians(flex[k])
            pts.append(pts[-1] + _dir(yaw, th) * d["L"][k] * escala)
        res[f] = pts
    # pulgar largo, muy separado
    t0 = _v([-0.019, 0.020, -0.006]) * escala
    t1 = t0 + _norm([-0.70, 0.66, -0.14]) * 0.050 * escala
    t2 = t1 + _norm([-0.38, 0.90, -0.14]) * 0.038 * escala
    t3 = t2 + _norm([-0.16, 0.96, -0.22]) * 0.030 * escala
    res[0] = [t0, t1, t2, t3]
    return res


def arriba_dedo(f, pts, k):
    d = _norm(pts[k + 1] - pts[k])
    up = _v([-0.55, 0.05, 0.83]) if f == 0 else _v([0, 0, 1])
    up = up - d * np.dot(up, d)
    return up / np.linalg.norm(up)


def esculpir(escala=1.0, flex=(8.0, 16.0, 10.0), antebrazo=0.08):
    e = escala
    A = articulaciones(flex, e)
    S = Escultura(banda=0.003 * e)
    # muñeca fina (entra en la manga)
    S.add(ConoRedondo((0, -antebrazo * e, -0.001 * e), (0, 0.014 * e, -0.001 * e), 0.026 * e, 0.024 * e, R_MUNECA,
                      aplastar=(1.0, 0.62)), 0.0)
    # palma estrecha y larga
    S.add(CajaRedonda((0.0, 0.056 * e, -0.0015 * e), (0.022 * e, 0.04 * e, 0.0045 * e), 0.008 * e, R_MANO), 0.012 * e)
    S.add(Elipsoide((-0.02 * e, 0.036 * e, -0.008 * e), (0.015 * e, 0.03 * e, 0.011 * e), R_MANO, rot=rot_euler(0, 0, np.radians(30))), 0.01 * e)
    S.add(Elipsoide((0.022 * e, 0.05 * e, -0.006 * e), (0.01 * e, 0.034 * e, 0.009 * e), R_MANO), 0.009 * e)
    S.add(Elipsoide((0.0, 0.09 * e, -0.008 * e), (0.029 * e, 0.012 * e, 0.007 * e), R_MANO), 0.008 * e)
    # tendones marcados en el dorso y nudillos grandes
    for f in (1, 2, 3):
        p0 = A[f][0]
        S.add(ConoRedondo(_v([p0[0] * 0.4, 0.012 * e, 0.004 * e]), p0 + _v([0, -0.006 * e, 0.002 * e]), 0.0038 * e, 0.0055 * e, R_MANO), 0.007 * e)
        S.add(Esfera(p0 + _v([0, -0.001 * e, 0.0032 * e]), DEDOS[f - 1]["r"] * 1.12 * e, R_MANO), 0.005 * e)
    for f in (1, 2, 3):
        pts = A[f]
        r0 = DEDOS[f - 1]["r"] * e
        radios = [r0, r0 * 0.82, r0 * 0.74, r0 * 0.7]
        for k in range(3):
            up = arriba_dedo(f, pts, k)
            S.add(ConoRedondo(pts[k], pts[k + 1], radios[k], radios[k + 1], r_dedo(f, k), aplastar=(1.0, 0.88), arriba=up), 0.003 * e)
            if k < 2:
                # articulación nudosa (más ancha que la falange)
                S.add(Esfera(pts[k + 1] + up * radios[k + 1] * 0.15, radios[k + 1] * 1.08, r_dedo(f, k + 1)), 0.003 * e)
        # yema abultada (almohadilla)
        dd = _norm(pts[3] - pts[2])
        upd = arriba_dedo(f, pts, 2)
        S.add(Elipsoide(pts[3] - dd * 0.004 * e - upd * radios[3] * 0.1, (radios[3] * 1.45, 0.0105 * e, radios[3] * 1.15), r_dedo(f, 2),
                        rot=np.stack([np.cross(dd, upd), dd, upd], axis=1)), 0.004 * e)
    # pulgar
    t = A[0]
    rt = [0.0115 * e, 0.0092 * e, 0.0082 * e, 0.0074 * e]
    for k in range(3):
        up = arriba_dedo(0, t, k)
        S.add(ConoRedondo(t[k], t[k + 1], rt[k], rt[k + 1], r_dedo(0, k), aplastar=(1.0, 0.86), arriba=up), 0.012 * e if k == 0 else 0.003 * e)
        if k < 2:
            S.add(Esfera(t[k + 1], rt[k + 1] * 1.08, r_dedo(0, k + 1)), 0.003 * e)
    dd = _norm(t[3] - t[2])
    upt = arriba_dedo(0, t, 2)
    S.add(Elipsoide(t[3] - dd * 0.004 * e, (rt[3] * 1.4, 0.0098 * e, rt[3] * 1.1), r_dedo(0, 2),
                    rot=np.stack([np.cross(dd, upt), dd, upt], axis=1)), 0.004 * e)
    S.desplazar.append(_detalle(A, e))
    return S, A


def _detalle(A, e):
    """Pliegues finos en las articulaciones y una textura de piel lisa, casi gomosa."""
    def fn(p, d, reg):
        out = np.zeros(len(p), dtype=np.float32)
        for f in range(N_DEDOS):
            pts = A[f]
            for k in (1, 2):
                j = pts[k]
                dvec = _norm(pts[k + 1] - pts[k - 1])
                up = arriba_dedo(f, pts, k)
                rel = p - j
                s = rel @ dvec
                u = rel @ up
                cerca = np.exp(-(s / (0.005 * e)) ** 2)
                if not np.any(cerca > 0.02):
                    continue
                dorso = smoothstep(0.0, 0.004 * e, u)
                arr = np.sin((s + ruido(p / e * 110.0, 5 + f * 3 + k) * 0.0003 * e) / (0.0012 * e) * np.pi * 2.0)
                out -= 0.00018 * e * arr * cerca * dorso
        # surcos longitudinales muy leves en el dorso (tendones bajo piel fina)
        dors = smoothstep(0.002 * e, 0.008 * e, p[:, 2]) * smoothstep(0.1 * e, 0.06 * e, p[:, 1])
        out += 0.00012 * e * dors * np.sin(p[:, 0] / e * 260.0 + ruido(p / e * 30.0, 3))
        out += 0.00003 * e * ruido(p / e * 700.0, 2)
        return out
    return fn


def huesos(A, sufijo=""):
    hs = [dict(nombre=f"mano{sufijo}", cabeza=(0, 0, 0), cola=tuple(A[2][0] * _v([0.4, 0.9, 0.0]) + _v([0, 0, 0.002])),
               arriba=(0, 0, 1), padre=None)]
    for f in range(N_DEDOS):
        pts = A[f]
        for k in range(3):
            hs.append(dict(nombre=f"dedo{f}_{k}{sufijo}", cabeza=tuple(pts[k]), cola=tuple(pts[k + 1]),
                           arriba=tuple(arriba_dedo(f, pts, k)),
                           padre=f"mano{sufijo}" if k == 0 else f"dedo{f}_{k - 1}{sufijo}"))
    return hs


def candidatos(reg, sufijo=""):
    m = f"mano{sufijo}"
    if reg == R_MUNECA:
        return [m, f"antebrazo{sufijo}"]
    if reg < 10:
        return [m] + [f"dedo{f}_0{sufijo}" for f in range(N_DEDOS)]
    f, k = divmod(reg - 10, 3)
    return [m] + [f"dedo{f}_{j}{sufijo}" for j in range(3)]


def colores(v, n, A, piel, venas, punta, escala=1.0):
    """Color lineal por vértice: piel translúcida, venas azuladas en el dorso,
    placas córneas oscuras en las puntas y palma más clara."""
    e = escala
    c = np.tile(_v(piel), (len(v), 1))
    c *= 1.0 + fbm(v / e * 60.0, 3, 21)[:, None] * 0.07
    palma = smoothstep(0.2, -0.6, n[:, 2])[:, None]
    c = c * (1 - palma * 0.3) + _v([0.74, 0.7, 0.74]) * palma * 0.3
    # venas del dorso: líneas ramificadas
    dors = (smoothstep(0.0, 0.006 * e, v[:, 2]) * smoothstep(0.11 * e, 0.04 * e, v[:, 1]))[:, None]
    q = v / e * _v([55.0, 11.0, 55.0])
    vena = smoothstep(0.09, 0.0, np.abs(ruido(q + fbm(v / e * 30.0, 2, 3)[:, None] * 0.3, 11)))[:, None]
    c = c * (1 - vena * dors * 0.55) + _v(venas) * vena * dors * 0.55
    # nudillos algo más oscuros, yemas y puntas córneas
    for f in range(N_DEDOS):
        pts = A[f]
        for k in (1, 2):
            w = np.exp(-(np.linalg.norm(v - pts[k], axis=1) / (0.008 * e)) ** 2)[:, None] * 0.25
            c = c * (1 - w) + _v(venas) * w
        dd = _norm(pts[3] - pts[2])
        rel = v - pts[3]
        s = rel @ dd
        w = (smoothstep(-0.012 * e, -0.003 * e, s) * smoothstep(0.018 * e, 0.012 * e, np.linalg.norm(rel, axis=1)))[:, None]
        dorsal = smoothstep(-0.2, 0.4, n @ arriba_dedo(f, pts, 2))[:, None]
        c = c * (1 - w * dorsal * 0.85) + _v(punta) * w * dorsal * 0.85
    return np.clip(c, 0, 1)
