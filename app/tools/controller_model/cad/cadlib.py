"""Shared helpers: STEP reading and per-face tessellation with OCP."""
import numpy as np
from OCP.STEPCAFControl import STEPCAFControl_Reader
from OCP.TDocStd import TDocStd_Document
from OCP.TCollection import TCollection_ExtendedString
from OCP.XCAFDoc import XCAFDoc_DocumentTool
from OCP.TDF import TDF_LabelSequence
from OCP.TDataStd import TDataStd_Name
from OCP.TopExp import TopExp_Explorer
from OCP.TopAbs import TopAbs_FACE, TopAbs_SOLID, TopAbs_REVERSED
from OCP.TopoDS import TopoDS
from OCP.BRepMesh import BRepMesh_IncrementalMesh
from OCP.BRep import BRep_Tool
from OCP.TopLoc import TopLoc_Location
from OCP.BRepAdaptor import BRepAdaptor_Surface
from OCP.GeomAbs import GeomAbs_SurfaceType


def read_step(path):
    """Return list of (name, shape) for free shapes in a STEP file."""
    doc = TDocStd_Document(TCollection_ExtendedString("XmlOcaf"))
    r = STEPCAFControl_Reader(); r.SetNameMode(True); r.SetColorMode(True)
    if r.ReadFile(path) != 1:
        raise RuntimeError("cannot read " + path)
    r.Transfer(doc)
    st = XCAFDoc_DocumentTool.ShapeTool_s(doc.Main())
    labels = TDF_LabelSequence(); st.GetFreeShapes(labels)
    out = []
    for i in range(1, labels.Length() + 1):
        L = labels.Value(i)
        nm = TDataStd_Name()
        name = nm.Get().ToExtString() if L.FindAttribute(TDataStd_Name.GetID_s(), nm) else "shape%d" % i
        out.append((name, st.GetShape_s(L)))
    return out


def faces_of(shape):
    ex = TopExp_Explorer(shape, TopAbs_FACE); fs = []
    while ex.More():
        fs.append(TopoDS.Face_s(ex.Current())); ex.Next()
    return fs


def tessellate(shape, lin=0.05, ang=0.3):
    """Mesh shape; return (V [n,3] mm, F [m,3], face_id [m]) with consistent outward winding."""
    BRepMesh_IncrementalMesh(shape, lin, False, ang, True)
    Vs, Fs, ids = [], [], []
    off = 0
    for fi, f in enumerate(faces_of(shape)):
        loc = TopLoc_Location()
        tri = BRep_Tool.Triangulation_s(f, loc)
        if tri is None:
            continue
        trsf = loc.Transformation()
        n = tri.NbNodes()
        v = np.empty((n, 3))
        for i in range(1, n + 1):
            p = tri.Node(i).Transformed(trsf)
            v[i - 1] = (p.X(), p.Y(), p.Z())
        m = tri.NbTriangles()
        t = np.empty((m, 3), dtype=np.int64)
        for i in range(1, m + 1):
            a, b, c = tri.Triangle(i).Get()
            t[i - 1] = (a - 1, b - 1, c - 1)
        if f.Orientation() == TopAbs_REVERSED:
            t = t[:, [0, 2, 1]]
        Vs.append(v); Fs.append(t + off); ids.append(np.full(m, fi)); off += n
    return np.vstack(Vs), np.vstack(Fs), np.concatenate(ids)


def surf_type(f):
    s = BRepAdaptor_Surface(f)
    return str(s.GetType()).split('_')[-1]
