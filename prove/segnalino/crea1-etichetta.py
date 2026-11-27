import pikepdf, math
from pikepdf import Name, Dictionary, Array
pdf = pikepdf.new()
W,H = 595,842
font = pdf.make_indirect(Dictionary(Type=Name.Font, Subtype=Name.Type1, BaseFont=Name.Helvetica, Encoding=Name.WinAnsiEncoding))
gsH = pdf.make_indirect(Dictionary(Type=Name.ExtGState, CA=0.35, ca=0.35))
ocg = pdf.make_indirect(Dictionary(Type=Name.OCG, Name=pikepdf.String("Tratti Appunti")))
pdf.Root.OCProperties = Dictionary(OCGs=Array([ocg]), D=Dictionary(ON=Array([ocg]), Order=Array([ocg])))

def onda(x0,y0,lung,amp,per,n=60):
    pts=[(x0+lung*i/n, y0+amp*math.sin(2*math.pi*i/n*per)) for i in range(n+1)]
    return "%.2f %.2f m "%pts[0] + " ".join("%.2f %.2f l"%p for p in pts[1:]) + " S\n"
def firma():
    s="1 J 1 j\n"
    # penna nera
    s+="0 0 0 RG 1.6 w\n"+onda(80,560,430,14,3)
    # penna blu
    s+="0.1 0.3 0.8 RG 2.4 w\n"+onda(80,500,430,10,5)
    # cerchio rosso
    s+="0.85 0.1 0.1 RG 2 w\n"
    pts=[(300+60*math.cos(t/40*2*math.pi), 380+40*math.sin(t/40*2*math.pi)) for t in range(41)]
    s+="%.2f %.2f m "%pts[0]+" ".join("%.2f %.2f l"%p for p in pts[1:])+" S\n"
    # evidenziatore giallo sopra il testo stampato
    s+="q /GsH gs 2 J 1 1 0 RG 16 w 70 704 m 470 704 l S 70 676 m 330 690 l S Q\n"
    return s
def testo(righe):
    s="BT /F1 13 Tf 0 0 0 rg\n"; y=740
    for r in righe:
        s+="1 0 0 1 72 %d Tm (%s) Tj\n"%(y,r); y-=22
    return s+"ET\n"
pagine=[
 (["PAGINA 1 - etichetta semplice (contenuto marcato)",
   "Testo stampato della pagina: questo resta sempre.",
   "Disegna qui sotto con Anteprima, poi salva."],
  "/AptTratti <</App (Appunti) /V 1>> BDC\n"+firma()+"EMC\n", False),
 (["PAGINA 2 - livello PDF vero (Optional Content)",
   "Testo stampato della pagina: questo resta sempre.",
   "Disegna qui sotto con Anteprima, poi salva."],
  "/OC /AptOC BDC\n"+firma()+"EMC\n", True),
]
for righe, blocco, oc in pagine:
    res=Dictionary(Font=Dictionary(F1=font), ExtGState=Dictionary(GsH=gsH))
    if oc: res.Properties=Dictionary(AptOC=ocg)
    cont = testo(righe) + "q\n" + blocco + "Q\n"
    pg=Dictionary(Type=Name.Page, MediaBox=Array([0,0,W,H]), Resources=res,
                  Contents=pdf.make_stream(cont.encode('latin-1')))
    pdf.pages.append(pikepdf.Page(pg))
pdf.docinfo["/Title"]="Prova etichetta Appunti"
pdf.save("Prova-etichetta.pdf")
