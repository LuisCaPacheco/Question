"""INTERROGART - escultor SDF en numpy (sin dependencias fuera de numpy).

Una "escultura" es una lista de operaciones sobre un campo de distancia con signo:
  add(forma, k)  -> union suave (k = radio de fusion)
  sub(forma, k)  -> resta suave
Cada forma devuelve distancias (negativo = dentro) y lleva una etiqueta de region, que
luego sirve para pintar el color (nudillos, labios, uñas...) y asignar pesos de huesos.

La malla se extrae con "surface nets": un vertice por celda que cruza la superficie y un
quad por arista que cruza. Da mallas cerradas, suaves y con buena topologia.
"""
import numpy as np

# ---------------------------------------------------------------- utilidades

def _v(x):
    return np.asarray(x, dtype=np.float32)


def rot_matriz(eje, ang):
    eje = _v(eje) / np.linalg.norm(eje)
    x, y, z = eje
    c, s = np.cos(ang), np.sin(ang)
    C = 1 - c
    return _v([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
               [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
               [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def rot_euler(rx=0.0, ry=0.0, rz=0.0):
    return rot_matriz((0, 0, 1), rz) @ rot_matriz((0, 1, 0), ry) @ rot_matriz((1, 0, 0), rx)


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def clamp01(x):
    return np.clip(x, 0.0, 1.0)


def smoothstep(e0, e1, x):
    t = clamp01((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- ruido

_PERM = None


def _perm():
    global _PERM
    if _PERM is None:
        rng = np.random.default_rng(1337)
        p = rng.permutation(256)
        _PERM = np.concatenate([p, p]).astype(np.int32)
    return _PERM


def _grad3():
    g = []
    for a in (-1, 1):
        for b in (-1, 1):
            g += [(a, b, 0), (a, 0, b), (0, a, b)]
    return _v(g)


_G3 = _grad3()


def ruido(p, semilla=0):
    """Ruido de gradiente 3D (tipo Perlin) en [-1, 1] aprox. p: (..., 3)."""
    P = _perm()
    p = p + semilla * 17.31
    pi = np.floor(p).astype(np.int32)
    pf = p - pi
    u = pf * pf * pf * (pf * (pf * 6 - 15) + 10)
    xi, yi, zi = pi[..., 0] & 255, pi[..., 1] & 255, pi[..., 2] & 255
    res = 0.0
    out = np.zeros(p.shape[:-1], dtype=np.float32)
    for dx in (0, 1):
        wx = u[..., 0] if dx else 1 - u[..., 0]
        for dy in (0, 1):
            wy = u[..., 1] if dy else 1 - u[..., 1]
            for dz in (0, 1):
                wz = u[..., 2] if dz else 1 - u[..., 2]
                h = P[P[P[(xi + dx) & 255] + ((yi + dy) & 255)] + ((zi + dz) & 255)] % 12
                g = _G3[h]
                d = (pf[..., 0] - dx) * g[..., 0] + (pf[..., 1] - dy) * g[..., 1] + (pf[..., 2] - dz) * g[..., 2]
                out += wx * wy * wz * d
    return out


def fbm(p, oct=4, semilla=0, lac=2.0, gan=0.5):
    a, f, s = 1.0, 1.0, 0.0
    tot = 0.0
    for i in range(oct):
        s = s + a * ruido(p * f, semilla + i * 7)
        tot += a
        a *= gan
        f *= lac
    return s / tot


# ---------------------------------------------------------------- formas

class Forma:
    """Forma con transformacion propia (rotacion + escala no uniforme)."""
    def __init__(self, region=0, centro=(0, 0, 0), rot=None, escala=(1, 1, 1)):
        self.region = region
        self.c = _v(centro)
        self.R = _v(rot) if rot is not None else np.eye(3, dtype=np.float32)
        self.s = _v(escala)
        self.caja = None   # (min, max) aprox. en mundo para saltarse puntos lejanos

    def local(self, p):
        q = (p - self.c) @ self.R          # R^T (p - c)  (filas)
        return q / self.s

    def dist(self, p):
        d = self._d(self.local(p))
        return d * float(np.min(self.s))

    def _d(self, q):
        raise NotImplementedError


class Esfera(Forma):
    def __init__(self, c, r, region=0, **kw):
        super().__init__(region, c, **kw)
        self.r = r

    def _d(self, q):
        return np.linalg.norm(q, axis=-1) - self.r


class Elipsoide(Forma):
    def __init__(self, c, radios, region=0, rot=None):
        super().__init__(region, c, rot)
        self.rr = _v(radios)

    def _d(self, q):
        k0 = np.linalg.norm(q / self.rr, axis=-1)
        k1 = np.linalg.norm(q / (self.rr * self.rr), axis=-1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


class ConoRedondo(Forma):
    """Capsula de radio variable entre a (ra) y b (rb). Escala opcional para aplastar."""
    def __init__(self, a, b, ra, rb, region=0, aplastar=None, arriba=(0, 0, 1)):
        a, b = _v(a), _v(b)
        c = (a + b) * 0.5
        rot = None
        esc = (1, 1, 1)
        if aplastar is not None:
            # base local: y = eje, z = "arriba" (se escala por aplastar[1]), x lateral (aplastar[0])
            y = (b - a) / max(np.linalg.norm(b - a), 1e-9)
            z = _v(arriba) - y * np.dot(_v(arriba), y)
            z /= max(np.linalg.norm(z), 1e-9)
            x = np.cross(y, z)
            rot = np.stack([x, y, z], axis=1)
            esc = (aplastar[0], 1.0, aplastar[1])
        super().__init__(region, c, rot, esc)
        R = self.R
        s = self.s
        self.a = ((a - c) @ R) / s
        self.b = ((b - c) @ R) / s
        self.ra, self.rb = ra, rb

    def _d(self, p):
        a, b, r1, r2 = self.a, self.b, self.ra, self.rb
        ba = b - a
        l2 = float(np.dot(ba, ba))
        rr = r1 - r2
        a2 = l2 - rr * rr
        il2 = 1.0 / l2
        pa = p - a
        y = pa @ ba
        z = y - l2
        xv = pa * l2 - y[..., None] * ba
        x2 = np.sum(xv * xv, axis=-1)
        y2 = y * y * l2
        z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        d3 = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + y * rr) * il2 - r1
        d1 = np.sqrt(x2 + z2) * il2 - r2
        d2 = np.sqrt(x2 + y2) * il2 - r1
        out = np.where(np.sign(z) * a2 * z2 > k, d1, np.where(np.sign(y) * a2 * y2 < k, d2, d3))
        return out


class CajaRedonda(Forma):
    def __init__(self, c, medio, radio, region=0, rot=None):
        super().__init__(region, c, rot)
        self.b = _v(medio)
        self.r = radio

    def _d(self, q):
        d = np.abs(q) - self.b
        return np.linalg.norm(np.maximum(d, 0), axis=-1) + np.minimum(np.max(d, axis=-1), 0) - self.r


class Toro(Forma):
    """Toro en el plano XY local (eje z local)."""
    def __init__(self, c, R, r, region=0, rot=None):
        super().__init__(region, c, rot)
        self.R_, self.r_ = R, r

    def _d(self, q):
        qx = np.linalg.norm(q[..., :2], axis=-1) - self.R_
        return np.sqrt(qx * qx + q[..., 2] ** 2) - self.r_


class Funcion(Forma):
    """Forma arbitraria: fn(p_mundo) -> distancia."""
    def __init__(self, fn, region=0):
        super().__init__(region)
        self.fn = fn

    def dist(self, p):
        return self.fn(p)


# ---------------------------------------------------------------- escultura

class Escultura:
    def __init__(self, banda=0.004):
        self.ops = []          # (tipo, forma, k)
        self.desplazar = []    # funciones fn(p, d, region) -> desplazamiento (m, + hacia fuera)
        self.banda = banda     # el desplazamiento solo se evalua a esta distancia de la superficie

    def add(self, forma, k=0.0):
        self.ops.append(("add", forma, k))
        return forma

    def sub(self, forma, k=0.0):
        self.ops.append(("sub", forma, k))
        return forma

    def inter(self, forma, k=0.0):
        self.ops.append(("int", forma, k))
        return forma

    def evaluar(self, p, con_region=False):
        d = np.full(p.shape[:-1], 1e3, dtype=np.float32)
        reg = np.zeros(p.shape[:-1], dtype=np.int16)
        mejor = np.full(p.shape[:-1], 1e3, dtype=np.float32)
        for tipo, f, k in self.ops:
            df = f.dist(p).astype(np.float32)
            if tipo == "add":
                d = smin(d, df, k)
                if con_region:
                    m = df < mejor
                    reg = np.where(m, f.region, reg)
                    mejor = np.minimum(mejor, df)
            elif tipo == "sub":
                d = smax(d, -df, k)
            else:
                d = smax(d, df, k)
        for fn in self.desplazar:
            # el detalle fino solo importa cerca de la superficie
            m = np.abs(d) < self.banda
            if np.any(m):
                d[m] = d[m] - fn(p[m], d[m], reg[m] if con_region else None)
        if con_region:
            return d, reg
        return d

    def regiones(self, p):
        """Region dominante (forma aditiva mas cercana) en cada punto."""
        mejor = np.full(p.shape[:-1], 1e3, dtype=np.float32)
        reg = np.zeros(p.shape[:-1], dtype=np.int16)
        for tipo, f, k in self.ops:
            if tipo != "add":
                continue
            df = f.dist(p)
            m = df < mejor
            reg = np.where(m, f.region, reg)
            mejor = np.minimum(mejor, df)
        return reg


# ---------------------------------------------------------------- surface nets

_ESQ = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1]])
_ARISTAS = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]


def muestrear(esc, bmin, bmax, h, bloque=40):
    """Evalua la escultura en una rejilla regular. Devuelve (F, origen, h)."""
    bmin = _v(bmin)
    bmax = _v(bmax)
    n = np.ceil((bmax - bmin) / h).astype(int) + 1
    F = np.empty(tuple(n), dtype=np.float32)
    xs = bmin[0] + np.arange(n[0], dtype=np.float32) * h
    ys = bmin[1] + np.arange(n[1], dtype=np.float32) * h
    zs = bmin[2] + np.arange(n[2], dtype=np.float32) * h
    for i0 in range(0, n[0], bloque):
        i1 = min(n[0], i0 + bloque)
        X, Y, Z = np.meshgrid(xs[i0:i1], ys, zs, indexing="ij")
        P = np.stack([X, Y, Z], axis=-1)
        F[i0:i1] = esc.evaluar(P)
    return F, bmin, h


def surface_nets(F, origen, h):
    """Devuelve (verts (N,3), quads (M,4)) de la isosuperficie F=0 (dentro = negativo)."""
    nx, ny, nz = F.shape
    dentro = F < 0
    # celdas activas: mezcla de signos en sus 8 esquinas
    c = [F[_ESQ[i][0]:nx - 1 + _ESQ[i][0], _ESQ[i][1]:ny - 1 + _ESQ[i][1], _ESQ[i][2]:nz - 1 + _ESQ[i][2]] for i in range(8)]
    cmin = np.minimum.reduce(c)
    cmax = np.maximum.reduce(c)
    activa = (cmin < 0) & (cmax >= 0)
    idx = np.full(activa.shape, -1, dtype=np.int64)
    ai = np.nonzero(activa)
    nv = len(ai[0])
    idx[ai] = np.arange(nv)
    # vertice = media de los cruces de las 12 aristas
    suma = np.zeros((nv, 3), dtype=np.float64)
    cuenta = np.zeros(nv, dtype=np.float64)
    ca = [ci[ai] for ci in c]
    for (e0, e1) in _ARISTAS:
        f0, f1 = ca[e0], ca[e1]
        m = (f0 < 0) != (f1 < 0)
        t = np.where(m, f0 / np.where(m, f0 - f1, 1.0), 0.0)
        p = _ESQ[e0] + t[:, None] * (_ESQ[e1] - _ESQ[e0])
        suma += np.where(m[:, None], p, 0.0)
        cuenta += m
    loc = suma / np.maximum(cuenta, 1)[:, None]
    verts = origen + (np.stack(ai, axis=1) + loc) * h
    quads = []
    # aristas en x: entre (i,j,k) y (i+1,j,k); celdas vecinas (i, j-1..j, k-1..k)
    for eje in range(3):
        if eje == 0:
            a = dentro[:-1, 1:-1, 1:-1]
            b = dentro[1:, 1:-1, 1:-1]
        elif eje == 1:
            a = dentro[1:-1, :-1, 1:-1]
            b = dentro[1:-1, 1:, 1:-1]
        else:
            a = dentro[1:-1, 1:-1, :-1]
            b = dentro[1:-1, 1:-1, 1:]
        cruza = a != b
        e = np.nonzero(cruza)
        if len(e[0]) == 0:
            continue
        i, j, k = [x.copy() for x in e]
        if eje == 0:
            j += 1; k += 1
            q = [idx[i, j - 1, k - 1], idx[i, j, k - 1], idx[i, j, k], idx[i, j - 1, k]]
        elif eje == 1:
            i += 1; k += 1
            q = [idx[i - 1, j, k - 1], idx[i - 1, j, k], idx[i, j, k], idx[i, j, k - 1]]
        else:
            i += 1; j += 1
            q = [idx[i - 1, j - 1, k], idx[i, j - 1, k], idx[i, j, k], idx[i - 1, j, k]]
        q = np.stack(q, axis=1)
        voltear = a[e]  # dentro en el lado bajo -> invertir orden
        q[voltear] = q[voltear][:, ::-1]
        quads.append(q)
    quads = np.concatenate(quads, axis=0) if quads else np.zeros((0, 4), dtype=np.int64)
    quads = quads[np.all(quads >= 0, axis=1)]
    return verts.astype(np.float32), quads


def muestrear_disperso(esc, bmin, bmax, h, B=12, lote=1_500_000):
    """Como muestrear(), pero solo evalua a resolucion fina los bloques cerca de la
    superficie; el resto se rellena con el valor grueso del centro del bloque."""
    bmin = _v(bmin)
    bmax = _v(bmax)
    n = np.ceil((bmax - bmin) / h).astype(int) + 1
    nb = -(-n // B)
    F = np.empty(tuple(n), dtype=np.float32)
    bi = np.stack(np.meshgrid(*[np.arange(k) for k in nb], indexing="ij"), axis=-1).reshape(-1, 3)
    centros = bmin + (bi * B + (B - 1) * 0.5) * h
    dc = esc.evaluar(centros.astype(np.float32))
    medio = B * h * 0.8660254 * 1.35 + 2 * h
    cerca = np.abs(dc) < medio
    # bloques lejanos: valor constante (solo importa el signo)
    for (i, j, k), d in zip(bi[~cerca], dc[~cerca]):
        F[i * B:(i + 1) * B, j * B:(j + 1) * B, k * B:(k + 1) * B] = d
    loc = np.stack(np.meshgrid(np.arange(B), np.arange(B), np.arange(B), indexing="ij"), axis=-1).reshape(-1, 3)
    sel = bi[cerca]
    por_lote = max(1, lote // (B ** 3))
    for s in range(0, len(sel), por_lote):
        bloque = sel[s:s + por_lote]
        idx = (bloque[:, None, :] * B + loc[None, :, :]).reshape(-1, 3)
        dentro = np.all(idx < n, axis=1)
        idx = idx[dentro]
        P = (bmin + idx * h).astype(np.float32)
        F[idx[:, 0], idx[:, 1], idx[:, 2]] = esc.evaluar(P)
    return F, bmin, h


def malla(esc, bmin, bmax, h, disperso=True):
    if disperso:
        F, o, h = muestrear_disperso(esc, bmin, bmax, h)
    else:
        F, o, h = muestrear(esc, bmin, bmax, h)
    return surface_nets(F, o, h)
