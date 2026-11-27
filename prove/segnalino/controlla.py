import pikepdf, sys, re
p=pikepdf.open(sys.argv[1])
print("Producer:", p.docinfo.get('/Producer'), "| OCProperties:", '/OCProperties' in p.Root)
for i,pg in enumerate(p.pages,1):
    c=pg.obj.Contents
    s=b"".join(x.read_bytes() for x in c) if isinstance(c,pikepdf.Array) else c.read_bytes()
    an=pg.obj.get('/Annots') or []
    print(f"PAGINA {i}: AptTratti={b'/AptTratti' in s} OC={b'/OC /' in s} Props={'/Properties' in pg.obj.Resources} "
          f"BDC={s.count(b'BDC')} linee_S={len(re.findall(rb'(?<![A-Za-z])S(?![A-Za-z])',s))} annotazioni={[str(a.get('/Subtype')) for a in an]} XObject={list(pg.obj.Resources.get('/XObject',{}).keys())}")
