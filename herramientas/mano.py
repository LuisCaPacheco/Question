"""INTERROGART - mano humana esculpida (mano DERECHA, palma abajo).
Ejes (Blender): +Y hacia los dedos, +Z dorso, -X hacia el pulgar. Muñeca en el origen.
La izquierda se obtiene reflejando X.
Medidas de un adulto (m). Pose de reposo relajada: dedos algo flexionados y abiertos.
"""
import numpy as np
from sdf import (Escultura, Esfera, Elipsoide, ConoRedondo, CajaRedonda, Funcion,
                 rot_euler, smoothstep, clamp01, ruido, fbm, smax, _v)

# region -> nombre de hueso
R_MANO = 1
R_MUNECA = 2


def r_dedo(f, k):
    return 10 + f * 3 + k


def _norm(v):
    v = _v(v)
    return v / np.linalg.norm(v)


def _dir(yaw, theta):
    return _v([np.sin(yaw) * np.cos(theta), np.cos(yaw) * np.cos(theta), -np.sin(theta)])


# dedos: indice, medio, anular, meñique
DEDOS = [
    # x MCP, y MCP, longitudes falanges, radio base, yaw (grados)
    dict(x=-0.0285, y=0.097, L=(0.043, 0.025, 0.021), r=0.0094, yaw=-4.0),
    dict(x=-0.0090, y=0.101, L=(0.047, 0.029, 0.022), r=0.0097, yaw=0.0),
    dict(x=0.0110, y=0.097, L=(0.044, 0.027, 0.021), r=0.0090, yaw=4.5),
    dict(x=0.0290, y=0.087, L=(0.034, 0.020, 0.019), r=0.0079, yaw=10.0),
]


def articulaciones(flex=(10.0, 20.0, 12.0), escala=1.0):
    """Posiciones de las articulaciones (en reposo). Devuelve dict dedo -> [p0,p1,p2,p3], arriba."""
    res = {}
    for i, d in enumerate(DEDOS):
        f = i + 1
        extra = 1.35 if f == 4 else 1.0
        yaw = np.radians(d["yaw"])
        p0 = _v([d["x"], d["y"], 0.004]) * escala
        th = 0.0
        pts = [p0]
        for k in range(3):
            th += np.radians(flex[k] * extra)
            pts.append(pts[-1] + _dir(yaw, th) * d["L"][k] * escala)
        res[f] = pts
    # pulgar (f=0): CMC, MCP, IP, punta
    t0 = _v([-0.020, 0.022, -0.006]) * escala
    t1 = t0 + _norm([-0.62, 0.72, -0.12]) * 0.046 * escala
    t2 = t1 + _norm([-0.30, 0.94, -0.12]) * 0.032 * escala
    t3 = t2 + _norm([-0.12, 0.97, -0.20]) * 0.026 * escala
    res[0] = [t0, t1, t2, t3]
    return res


def arriba_dedo(f, pts, k):
    d = _norm(pts[k + 1] - pts[k])
    up = _v([-0.55, 0.05, 0.83]) if f == 0 else _v([0, 0, 1])
    up = up - d * np.dot(up, d)
    return up / np.linalg.norm(up)


def esculpir(escala=1.0, flex=(10.0, 20.0, 12.0), antebrazo=0.075, detalle=True):
    e = escala
    A = articulaciones(flex, e)
    S = Escultura()
    # ---- muñeca / antebrazo (entra en el puño de la camisa)
    S.add(ConoRedondo((0, -antebrazo * e, -0.001 * e), (0, 0.012 * e, -0.001 * e), 0.0305 * e, 0.0285 * e, R_MUNECA,
                      aplastar=(1.0, 0.64)), 0.0)
    # apofisis del cubito (bulto en el lado del meñique)
    S.add(Esfera((0.024 * e, -0.012 * e, 0.004 * e), 0.0075 * e, R_MUNECA), 0.008 * e)
    # ---- palma
    S.add(CajaRedonda((0.0005 * e, 0.052 * e, -0.0015 * e), (0.029 * e, 0.037 * e, 0.0055 * e), 0.0085 * e, R_MANO), 0.012 * e)
    S.add(Elipsoide((-0.023 * e, 0.036 * e, -0.0085 * e), (0.0175 * e, 0.029 * e, 0.0125 * e), R_MANO, rot=rot_euler(0, 0, np.radians(28))), 0.01 * e)
    S.add(Elipsoide((0.028 * e, 0.047 * e, -0.006 * e), (0.012 * e, 0.032 * e, 0.0105 * e), R_MANO), 0.009 * e)
    S.add(Elipsoide((0.0 * e, 0.088 * e, -0.0085 * e), (0.036 * e, 0.012 * e, 0.0075 * e), R_MANO), 0.008 * e)
    # metacarpos (relieve en el dorso) y cabezas (nudillos)
    for f in (1, 2, 3, 4):
        p0 = A[f][0]
        S.add(ConoRedondo(_v([p0[0] * 0.55, 0.018 * e, 0.0045 * e]), p0 + _v([0, -0.006 * e, 0.0015 * e]), 0.0052 * e, 0.0062 * e, R_MANO), 0.009 * e)
        S.add(Esfera(p0 + _v([0, -0.002 * e, 0.0028 * e]), DEDOS[f - 1]["r"] * 1.02 * e, R_MANO), 0.006 * e)
    # ---- dedos
    for f in (1, 2, 3, 4):
        pts = A[f]
        r0 = DEDOS[f - 1]["r"] * e
        radios = [r0, r0 * 0.9, r0 * 0.82, r0 * 0.74]
        for k in range(3):
            up = arriba_dedo(f, pts, k)
            S.add(ConoRedondo(pts[k], pts[k + 1] - (_norm(pts[k + 1] - pts[k]) * radios[k + 1] * (0.9 if k == 2 else 0.0)),
                              radios[k], radios[k + 1], r_dedo(f, k), aplastar=(1.0, 0.86), arriba=up), 0.0035 * e)
            if k < 2:
                # relieve dorsal de la articulacion
                S.add(Esfera(pts[k + 1] + up * radios[k + 1] * 0.3, radios[k + 1] * 0.62, r_dedo(f, k + 1)), 0.004 * e)
        # yema (almohadilla palmar)
        dd = _norm(pts[3] - pts[2])
        upd = arriba_dedo(f, pts, 2)
        S.add(Elipsoide(pts[2] + dd * 0.012 * e - upd * radios[3] * 0.25, (radios[3] * 0.92, 0.0085 * e, radios[3] * 0.7), r_dedo(f, 2),
                        rot=np.stack([np.cross(dd, upd), dd, upd], axis=1)), 0.004 * e)
    # ---- pulgar
    t = A[0]
    rt = [0.0125 * e, 0.0102 * e, 0.0094 * e, 0.0082 * e]
    for k in range(3):
        up = arriba_dedo(0, t, k)
        fin = t[k + 1] - (_norm(t[k + 1] - t[k]) * rt[k + 1] * (0.85 if k == 2 else 0.0))
        S.add(ConoRedondo(t[k], fin, rt[k], rt[k + 1], r_dedo(0, k), aplastar=(1.0, 0.84), arriba=up), 0.012 * e if k == 0 else 0.004 * e)
    S.add(Esfera(t[1] + arriba_dedo(0, t, 1) * 0.004 * e, 0.0082 * e, r_dedo(0, 1)), 0.005 * e)
    # ---- lechos de las uñas (hundimiento leve)
    unas = []
    for f in range(5):
        pts = A[f]
        r = (DEDOS[f - 1]["r"] * 0.76 if f else 0.0086) * e
        unas.append(_una(pts[2], pts[3], arriba_dedo(f, pts, 2), r, e, 0.84 if f == 0 else 0.86))
    for u in unas:
        S.sub(Funcion(u["lecho"]), 0.0006 * e)
    if detalle:
        S.desplazar.append(_detalle(A, e))
    return S, A, unas


def _una(a, b, up, r, e, aplaste=0.86):
    """Uña sobre la falange distal a->b (r = radio del dedo a esa altura).
    Devuelve funciones SDF del lecho y de la uña."""
    d = _norm(b - a)
    up = up - d * np.dot(up, d)
    up /= np.linalg.norm(up)
    x = np.cross(d, up)
    L = np.linalg.norm(b - a)
    c = a + d * L * 0.7 + up * (r * aplaste - 0.0002 * e)
    medio_x = r * 0.78
    largo = L * 0.36
    R = np.stack([x, d, up], axis=1)

    def local(p):
        return (p - c) @ R

    def region(q):
        # rectangulo redondeado en (x, y) del plano de la uña
        qx = np.abs(q[..., 0]) - medio_x * 0.72
        qy = np.abs(q[..., 1]) - largo * 0.8
        return np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - medio_x * 0.28

    def curva(q):
        # la uña se curva siguiendo el dedo
        return q[..., 2] + (q[..., 0] ** 2) / (r * 2.2)

    def lecho(p):
        q = local(p)
        return np.maximum(region(q), np.abs(curva(q) + 0.00025 * e) - 0.0004 * e)

    def una(p):
        q = local(p)
        return np.maximum(region(q) + 0.0003 * e, np.abs(curva(q) - 0.00005 * e) - 0.00045 * e)

    return dict(lecho=lecho, una=una, centro=c, base=R)


def _detalle(A, e):
    """Desplazamiento fino: venas del dorso, arrugas de nudillos y pliegues palmares."""
    def fn(p, d, reg):
        out = np.zeros(len(p), dtype=np.float32)
        # venas del dorso (lineas suaves a lo largo de la mano)
        dors = smoothstep(0.002 * e, 0.009 * e, p[:, 2]) * smoothstep(0.08 * e, 0.05 * e, p[:, 1]) * smoothstep(-0.06 * e, -0.03 * e, p[:, 1])
        dors *= smoothstep(0.036 * e, 0.024 * e, np.abs(p[:, 0]))
        if np.any(dors > 0):
            q = p / e * _v([40.0, 9.0, 40.0])
            n = ruido(q + fbm(p / e * 25.0, 2, 3)[:, None] * 0.25, 11)
            vena = smoothstep(0.075, 0.0, np.abs(n))
            out += 0.00022 * e * vena * dors
        # arrugas de los nudillos (dorsales) y pliegues (palmares)
        for f in range(5):
            pts = A[f]
            for k in (1, 2):
                j = pts[k]
                dvec = _norm(pts[k + 1] - pts[k - 1])
                up = arriba_dedo(f, pts, k)
                rel = p - j
                s = rel @ dvec
                u = rel @ up
                lat = rel @ np.cross(dvec, up)
                cerca = np.exp(-(s / (0.0045 * e)) ** 2) * smoothstep(0.013 * e, 0.009 * e, np.abs(lat))
                if not np.any(cerca > 0.02):
                    continue
                dorso = smoothstep(0.0, 0.004 * e, u)
                palma = smoothstep(0.0, -0.004 * e, u)
                ss = s + ruido(p / e * 120.0, 5 + f * 3 + k) * 0.0003 * e + (lat ** 2) * 18.0 / e
                arr = np.sin(ss / (0.00105 * e) * np.pi * 2.0)
                out -= 0.00016 * e * arr * cerca * dorso * (0.6 if k == 2 else 1.0)
                out -= 0.00032 * e * np.exp(-(s / (0.0007 * e)) ** 2) * palma * cerca
        # textura muy suave de piel (no "rugosa")
        out += 0.00004 * e * ruido(p / e * 900.0, 2)
        return out
    return fn


def esculpir_unas(unas):
    S = Escultura()
    for u in unas:
        S.add(Funcion(u["una"]))
    return S


def huesos(A, escala=1.0, prefijo="", sufijo="", antebrazo=0.075):
    e = escala
    hs = []
    hs.append(dict(nombre=f"{prefijo}mano{sufijo}", cabeza=(0, 0, 0), cola=tuple(A[2][0] * _v([0.4, 0.9, 0.0]) + _v([0, 0, 0.002])),
                   arriba=(0, 0, 1), padre=None))
    for f in range(5):
        pts = A[f]
        for k in range(3):
            hs.append(dict(nombre=f"{prefijo}dedo{f}_{k}{sufijo}", cabeza=tuple(pts[k]), cola=tuple(pts[k + 1]),
                           arriba=tuple(arriba_dedo(f, pts, k)),
                           padre=f"{prefijo}mano{sufijo}" if k == 0 else f"{prefijo}dedo{f}_{k - 1}{sufijo}"))
    return hs


def region_a_hueso(reg, prefijo="", sufijo=""):
    if reg == R_MANO or reg == R_MUNECA or reg < 10:
        return f"{prefijo}mano{sufijo}"
    f, k = divmod(reg - 10, 3)
    return f"{prefijo}dedo{f}_{k}{sufijo}"


def candidatos(reg, prefijo="", sufijo=""):
    m = f"{prefijo}mano{sufijo}"
    if reg < 10:
        base = [m] + [f"{prefijo}dedo{f}_0{sufijo}" for f in range(5)]
        if reg == R_MUNECA:
            base = [m, f"{prefijo}antebrazo{sufijo}"]
        return base
    f, k = divmod(reg - 10, 3)
    return [m] + [f"{prefijo}dedo{f}_{j}{sufijo}" for j in range(3)]


def colores(v, reg, n, A, piel=(0.62, 0.43, 0.34), escala=1.0):
    """Color lineal por vertice: base + rojeces en nudillos/yemas + palma mas clara + moteado suave."""
    e = escala
    base = _v(piel)
    c = np.tile(base, (len(v), 1))
    mot = fbm(v / e * 70.0, 3, 21)[:, None]
    c *= 1.0 + mot * 0.06
    rojo = _v([0.72, 0.36, 0.30])
    palma = smoothstep(0.2, -0.6, n[:, 2])[:, None]
    c = c * (1 - palma * 0.25) + _v([0.78, 0.52, 0.44]) * palma * 0.25
    for f in range(5):
        pts = A[f]
        for k in (0, 1, 2):
            j = pts[k]
            dd = np.linalg.norm(v - j, axis=1)
            w = np.exp(-(dd / (0.0085 * e)) ** 2)[:, None] * (0.35 if k == 0 else 0.28)
            c = c * (1 - w) + rojo * w
        tip = pts[3]
        w = np.exp(-(np.linalg.norm(v - tip, axis=1) / (0.012 * e)) ** 2)[:, None] * 0.35
        c = c * (1 - w) + rojo * w
    # dorso de la muñeca algo mas tostado
    tost = (smoothstep(0.01 * e, -0.05 * e, v[:, 1]) * smoothstep(-0.2, 0.6, n[:, 2]))[:, None] * 0.12
    c = c * (1 - tost) + _v([0.5, 0.33, 0.25]) * tost
    return np.clip(c, 0, 1)
