# PROVA 4 (27/11/2026) — punti da verificare del progetto `docs/formato-segnalini.md` §8:
#  • blocco in un flusso SEPARATO (/Contents a elenco: [originale, blocco]);
#  • dati lunghi spezzati in pezzi «APT-D i/k» (≈160 000 caratteri, pezzi da 30 000);
#  • testo VERO visibile in Helvetica (con lettere accentate WinAnsi), giustificato con Tw;
#  • evidenziatori: due passate che si incrociano UNITE in una sola forma (incrocio non più scuro) e, per confronto, separate;
#  • PNG con trasparenza (SMask), ruotato; foto JPEG ritagliata a mano libera (clip a poligono);
#  • stessa foto su due pagine = un solo oggetto.
# Uso: python3 crea4-prova.py  → Prova-4.pdf     Controllo dopo Anteprima: python3 analizza4.py <file>
import pikepdf, math, zlib, base64, io, random, hashlib
from pikepdf import Name, Dictionary, Array
from PIL import Image, ImageDraw, ImageFont
random.seed(4)
pdf = pikepdf.new(); W, H = 595, 842
fontF = pdf.make_indirect(Dictionary(Type=Name.Font, Subtype=Name.Type1, BaseFont=Name.Helvetica, Encoding=Name.WinAnsiEncoding))
gsH = pdf.make_indirect(Dictionary(Type=Name.ExtGState, CA=0.35, ca=0.35))
TROCCO = 30000

def stringa(t):  # testo WinAnsi in stringa PDF esadecimale (sicura per qualunque carattere)
    return "<" + t.encode("cp1252").hex() + ">"

def blocco(pagina, disegno, operazioni, elementi, payload):
    h = hashlib.sha256(payload).hexdigest()[:16]
    d = base64.b64encode(zlib.compress(payload, 9)).decode()
    pezzi = [d[i:i + TROCCO] for i in range(0, len(d), TROCCO)] or [""]
    k = len(pezzi)
    m = lambda t: "BT /AptF 1 Tf 3 Tr 1 0 0 1 2 2 Tm (%s) Tj ET\n" % t
    s = "q\n" + m("APT-INIZIO v2 p%d e%d n%d h%s k%d" % (pagina, elementi, operazioni, h, k))
    for i, p in enumerate(pezzi, 1):
        s += m("APT-D %d/%d %s" % (i, k, p))
    s += disegno + m("APT-FINE h%s" % h) + "Q\n"
    return s, len(d), k

def originale(righe):
    s = "BT /F1 13 Tf 0 0 0 rg\n"; y = 790
    for r in righe:
        s += "1 0 0 1 50 %d Tm %s Tj\n" % (y, stringa(r)); y -= 19
    return s + "ET\n0.6 0.6 0.6 RG 1 w 50 690 m 545 690 l S\n"

def pagina(cont_orig, cont_blocco, risorse):
    s1 = pdf.make_stream(cont_orig.encode("latin-1"))
    s2 = pdf.make_stream(cont_blocco.encode("latin-1"))
    pdf.pages.append(pikepdf.Page(Dictionary(Type=Name.Page, MediaBox=Array([0, 0, W, H]),
                                             Resources=risorse, Contents=Array([s1, s2]))))

def banda(x0, y0, x1, y1, larg):  # rettangolo ruotato (evidenziatore dritto) come percorso
    a = math.atan2(y1 - y0, x1 - x0); nx, ny = -math.sin(a) * larg / 2, math.cos(a) * larg / 2
    p = [(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)]
    return "%.2f %.2f m " % p[0] + " ".join("%.2f %.2f l" % q for q in p[1:]) + " h\n"

# ---------------- PAGINA 1: dati lunghi, testo vero, evidenziatori
op = 0
dis = ""
# evidenziatori UNITI: due bande nello stesso percorso, un solo riempimento (regola nonzero) → l'incrocio non si scurisce
dis += "q /AptGs1 gs 1 0.85 0 rg\n" + banda(60, 560, 280, 640, 22) + banda(60, 640, 280, 560, 22) + "f Q\n"; op += 1
# evidenziatori SEPARATI (come oggi): due riempimenti → l'incrocio si scurisce
dis += "q /AptGs1 gs 1 0.85 0 rg\n" + banda(320, 560, 540, 640, 22) + "f\n" + banda(320, 640, 540, 560, 22) + "f Q\n"; op += 2
# tratti di penna (contorno pieno come i tratti dell'app)
for k in range(3):
    pts = [(60 + i * 4.8, 470 - k * 40 + 12 * math.sin(i / 7 + k)) for i in range(100)]
    up = [(x, y + 1.2) for x, y in pts]; dn = [(x, y - 1.2) for x, y in pts][::-1]
    poli = up + dn
    dis += "0.05 0.1 0.45 rg %.2f %.2f m " % poli[0] + " ".join("%.2f %.2f l" % q for q in poli[1:]) + " h f\n"; op += 1
# testo VERO giustificato (Helvetica, WinAnsi)
righe = ["Testo vero dell'app: perché è così, città, più, però.",
         "Questa riga è giustificata con Tw per riempire il blocco.",
         "Cerca «città» in Anteprima: deve trovarla qui."]
dis += "BT /AptF 12 Tf 0 Tr 0.6 0 0 rg\n"   # 0 Tr obbligatorio: il 3 Tr dei segnalini resta attivo dopo ET\n"
for i, r in enumerate(righe):
    tw = 2.0 if i < 2 else 0
    dis += "%.2f Tw 1 0 0 1 60 %d Tm %s Tj\n" % (tw, 330 - i * 17, stringa(r))
dis += "ET\n"; op += 1
payload = random.randbytes(120000)   # dati «pesanti», non comprimibili: ≈ 160 000 caratteri base64
b1, lung, k = blocco(1, dis, op, 7, payload)
res = Dictionary(Font=Dictionary(F1=fontF, AptF=fontF), ExtGState=Dictionary(AptGs1=gsH))
pagina(originale(["PROVA 4 - PAGINA 1: dati lunghi, testo vero, evidenziatori",
                  "A sinistra evidenziatori UNITI (incrocio uguale), a destra SEPARATI (incrocio più scuro).",
                  "Scarabocchia con Anteprima, cerca «città», poi Fine."]), b1, res)
print("pagina 1: %d caratteri di dati in %d pezzi" % (lung, k))

# ---------------- immagini
img = Image.new("RGB", (1200, 900)); d = ImageDraw.Draw(img)
for y in range(900):
    d.line([(0, y), (1200, y)], fill=(int(30 + 180 * y / 900), int(120 + 70 * math.sin(y / 60) ** 2), int(210 - 150 * y / 900)))
for gx in range(0, 1200, 6): d.line([(gx, 0), (gx, 30)], fill=(0, 0, 0) if gx % 12 else (255, 255, 255))
fnt = ImageFont.load_default()
for i in range(14): d.text((30, 50 + i * 60), "FOTO riga %02d - dettaglio fine 0123456789" % i, fill=(255, 255, 255), font=fnt)
buf = io.BytesIO(); img.save(buf, "JPEG", quality=90); jpg = buf.getvalue()
foto = pdf.make_stream(jpg); foto.Type = Name.XObject; foto.Subtype = Name.Image; foto.Width = 1200; foto.Height = 900
foto.ColorSpace = Name.DeviceRGB; foto.BitsPerComponent = 8; foto.Filter = Name.DCTDecode
# PNG con trasparenza: disco colorato con buco e bordo sfumato
png = Image.new("RGBA", (600, 600), (0, 0, 0, 0)); dp = ImageDraw.Draw(png)
for r in range(280, 0, -4):
    dp.ellipse([300 - r, 300 - r, 300 + r, 300 + r], fill=(220, 40 + r // 2, 90, min(255, 40 + (280 - r) * 2)))
dp.ellipse([230, 230, 370, 370], fill=(0, 0, 0, 0)); dp.text((240, 120), "PNG TRASPARENTE", fill=(255, 255, 255, 255), font=fnt)
rgb = png.convert("RGB").tobytes(); alfa = png.split()[3].tobytes()
sm = pdf.make_stream(zlib.compress(alfa, 9)); sm.Type = Name.XObject; sm.Subtype = Name.Image; sm.Width = 600; sm.Height = 600
sm.ColorSpace = Name.DeviceGray; sm.BitsPerComponent = 8; sm.Filter = Name.FlateDecode
im2 = pdf.make_stream(zlib.compress(rgb, 9)); im2.Type = Name.XObject; im2.Subtype = Name.Image; im2.Width = 600; im2.Height = 600
im2.ColorSpace = Name.DeviceRGB; im2.BitsPerComponent = 8; im2.Filter = Name.FlateDecode; im2.SMask = sm
open("foto4.jpg", "wb").write(jpg); png.save("png4.png")

# ---------------- PAGINA 2: PNG ruotato + foto ritagliata a mano libera
a = math.radians(20); c, s_ = math.cos(a), math.sin(a)
dis = "q %.4f %.4f %.4f %.4f %.2f %.2f cm /AptIm2 Do Q\n" % (220 * c, 220 * s_, -220 * s_, 220 * c, 360, 430)
# poligono a mano libera (stella irregolare) come ritaglio della foto
cx, cy = 200, 300
poli = [(cx + (150 if i % 2 == 0 else 70) * math.cos(i * math.pi / 7) + random.uniform(-10, 10),
         cy + (150 if i % 2 == 0 else 70) * math.sin(i * math.pi / 7) + random.uniform(-10, 10)) for i in range(14)]
clip = "%.2f %.2f m " % poli[0] + " ".join("%.2f %.2f l" % q for q in poli[1:]) + " h W n\n"
dis += "q " + clip + "320 0 0 240 40 180 cm /AptIm1 Do Q\n"
b2, _, _ = blocco(2, dis, 2, 2, b"pagina2-" + bytes(range(256)) * 8)
res = Dictionary(Font=Dictionary(F1=fontF, AptF=fontF), XObject=Dictionary(AptIm1=foto, AptIm2=im2))
pagina(originale(["PROVA 4 - PAGINA 2: PNG trasparente ruotato, foto ritagliata a stella",
                  "Il PNG deve avere il buco al centro e i bordi sfumati; la foto è tagliata a stella.",
                  "Scarabocchia con Anteprima, poi Fine."]), b2, res)

# ---------------- PAGINA 3: stessa foto (stesso oggetto) intera
dis = "q 400 0 0 300 97 250 cm /AptIm1 Do Q\n"
b3, _, _ = blocco(3, dis, 1, 1, b"pagina3-" + bytes(range(256)) * 4)
res = Dictionary(Font=Dictionary(F1=fontF, AptF=fontF), XObject=Dictionary(AptIm1=foto))
pagina(originale(["PROVA 4 - PAGINA 3: la stessa foto della pagina 2, intera",
                  "Nel file deve esserci UNA sola copia della foto.",
                  "Scarabocchia con Anteprima, poi Fine."]), b3, res)

pdf.docinfo["/Title"] = "Prova 4 Appunti"
pdf.save("Prova-4.pdf")
print("jpg", len(jpg), "byte; sha", hashlib.sha256(jpg).hexdigest()[:16])
