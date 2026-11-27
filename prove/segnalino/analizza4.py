# Analizza un PDF della Prova 4 (prima o dopo Anteprima): per ogni pagina ritrova il blocco interpretando gli OPERATORI,
# ricompone i pezzi APT-D, controlla impronta/numero di operazioni, immagini (SMask, copie), annotazioni.
# Uso: python3 analizza4.py <file.pdf> [foto4.jpg]
import pikepdf, sys, zlib, base64, hashlib, collections
p = pikepdf.open(sys.argv[1])
jpg_sha = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()[:16] if len(sys.argv) > 2 else None
print("Producer:", p.docinfo.get("/Producer"), "| oggetti:", len(p.objects))
DIS = {"f", "f*", "F", "S", "s", "B", "B*", "b", "b*", "Do"}
immagini = collections.Counter()
for n, pg in enumerate(p.pages, 1):
    c = pg.obj.Contents
    nflussi = len(c) if isinstance(c, pikepdf.Array) else 1
    ops = pikepdf.parse_content_stream(pg)
    stato, pezzi, inizio, fine, conta, testi_vis, in_bt, testo_bt = None, {}, None, None, 0, [], False, []
    for operandi, op in ops:
        o = str(op)
        if o == "BT": in_bt, testo_bt = True, []
        if o in ("Tj", "TJ"):
            t = operandi[0]
            if isinstance(t, pikepdf.Array):
                t = b"".join(bytes(x) for x in t if isinstance(x, pikepdf.String))
            else:
                t = bytes(t)
            s = t.decode("latin-1")
            if s.startswith("APT-INIZIO"): inizio, stato = s, "dentro"
            elif s.startswith("APT-FINE"): fine, stato = s, "fuori"
            elif s.startswith("APT-D "):
                i, k = s.split()[1].split("/"); pezzi[int(i)] = s.split(" ", 2)[2]
            elif stato == "dentro": testo_bt.append(s)
        if o == "ET":
            in_bt = False
            if testo_bt: testi_vis.append(" | ".join(x.encode("latin-1").decode("cp1252") for x in testo_bt)); conta += 1
        if stato == "dentro" and o in DIS: conta += 1
    esito = "BLOCCO NON TROVATO"
    if inizio and fine:
        campi = dict((x[0], x[1:]) for x in inizio.split()[2:])
        k = int(campi["k"]); h = campi["h"]
        ok_pezzi = sorted(pezzi) == list(range(1, k + 1))
        try:
            dati = zlib.decompress(base64.b64decode("".join(pezzi[i] for i in range(1, k + 1))))
            ok_h = hashlib.sha256(dati).hexdigest()[:16] == h and fine.endswith(h)
        except Exception as e:
            ok_h = "ERRORE %s" % e; dati = b""
        esito = "pezzi %d/%d %s | impronta %s | operazioni %d attese %s | dati %d byte" % (
            len(pezzi), k, "OK" if ok_pezzi else "MANCANO", "OK" if ok_h is True else ok_h, conta, campi["n"], len(dati))
    xo = pg.obj.Resources.get("/XObject", {})
    info = []
    for nome, x in xo.items():
        immagini[x.objgen] += 1
        dati_x = x.read_raw_bytes()
        info.append("%s %dx%d %s%s%s" % (nome, x.Width, x.Height, x.get("/Filter"), " SMask" if "/SMask" in x else "",
                                         " =JPEG originale" if jpg_sha and hashlib.sha256(dati_x).hexdigest()[:16] == jpg_sha else ""))
    an = [str(a.get("/Subtype")) for a in (pg.obj.get("/Annots") or [])]
    print("PAGINA %d: flussi=%d | %s" % (n, nflussi, esito))
    print("   immagini:", info, "| annotazioni:", an)
    if testi_vis: print("   testo visibile nel blocco:", testi_vis)
print("Oggetti immagine distinti:", len(immagini), dict((str(k), v) for k, v in immagini.items()))
